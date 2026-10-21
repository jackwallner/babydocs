package com.jackwallner.babydocs.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.DocumentItem
import com.jackwallner.babydocs.model.FamilyProfile
import com.jackwallner.babydocs.model.Receipt
import com.jackwallner.babydocs.model.RequirementTask
import com.jackwallner.babydocs.model.VaultDocument
import com.jackwallner.babydocs.rules.RequirementEngine
import java.io.File

/** The whole household, one device, no server. */
class BabyData(
    var profile: FamilyProfile = FamilyProfile(),
    val children: MutableList<Child> = mutableListOf(),
    val tasks: MutableList<RequirementTask> = mutableListOf(),
    val documents: MutableList<DocumentItem> = mutableListOf(),
    val receipts: MutableList<Receipt> = mutableListOf(),
    val vault: MutableList<VaultDocument> = mutableListOf(),
) {
    /** Reads skip tombstones; every list in the UI goes through these. */
    val liveChildren: List<Child> get() = children.filter { it.deletedAt == null && !it.isEphemeralDraft }

    fun liveTasks(child: Child): List<RequirementTask> = tasks.filter { it.childId == child.id && it.deletedAt == null }

    fun liveDocuments(task: RequirementTask): List<DocumentItem> =
        documents.filter { it.taskId == task.id && it.deletedAt == null }.sortedBy { it.sortWeight }

    fun liveReceipts(task: RequirementTask): List<Receipt> =
        receipts.filter { it.taskId == task.id && it.deletedAt == null }.sortedByDescending { it.recordedAt }

    fun liveVault(child: Child): List<VaultDocument> = vault
        .filter { it.childId == child.id && it.deletedAt == null }
        .sortedWith(compareBy<VaultDocument> { it.kind.sortWeight }.thenBy { it.addedAt })

    fun task(id: java.util.UUID): RequirementTask? = tasks.firstOrNull { it.id == id }

    fun child(id: java.util.UUID?): Child? = children.firstOrNull { it.id == id }

    fun allLiveTasks(): List<RequirementTask> {
        val live = liveChildren.map { it.id }.toSet()
        return tasks.filter { it.deletedAt == null && it.childId in live }
    }
}

/**
 * The SwiftData container of this port: one JSON file in app-private storage,
 * excluded from every backup by the manifest's extraction rules.
 *
 * Every change goes through [commit]. A write that fails, or that would store
 * something shaped like a Social Security number, is rolled back to the last
 * saved state and reported once through [failureMessage], so a tick the disk
 * disagreed with never looks saved (`SaveFailureReporter` on iOS).
 */
class BabyStore(private val file: File?) {
    var data: BabyData = load()
        private set

    /** Bumped after every committed change; Compose reads it to recompose. */
    var revision by mutableIntStateOf(0)
        private set

    var failureMessage by mutableStateOf<String?>(null)

    private var lastSaved: String = Codecs.encode(data)

    /** Applies [change], reconciles every plan, and writes. Returns false if nothing was kept. */
    fun commit(reconcile: Boolean = true, change: (BabyData) -> Unit = {}): Boolean {
        change(data)
        if (reconcile) RequirementEngine.reconcileAll(data)
        if (Sensitive.containsAny(data)) {
            rollback()
            failureMessage = Sensitive.MESSAGE
            return false
        }
        val encoded = Codecs.encode(data)
        if (encoded == lastSaved) {
            revision += 1
            return true
        }
        return try {
            file?.let { writeAtomically(it, encoded) }
            lastSaved = encoded
            revision += 1
            true
        } catch (_: Exception) {
            rollback()
            failureMessage = SAVE_FAILED
            false
        }
    }

    fun replaceAll(newData: BabyData) {
        data = newData
        commit()
    }

    private fun rollback() {
        data = Codecs.decode(lastSaved)
        revision += 1
    }

    private fun load(): BabyData {
        val f = file ?: return BabyData()
        if (!f.exists()) return BabyData()
        return runCatching { Codecs.decode(f.readText()) }.getOrElse { BabyData() }
    }

    private fun writeAtomically(target: File, text: String) {
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, target.name + ".tmp")
        temp.writeText(text)
        if (!temp.renameTo(target)) {
            target.delete()
            check(temp.renameTo(target)) { "rename failed" }
        }
    }

    companion object {
        const val SAVE_FAILED = "Your last change could not be saved to this phone, so what you are looking at may not survive closing the app. This is usually storage being full. Free some space and make the change again."
    }
}

/** The SSN guard of `LocalRecord.containsSensitiveText`, over the same fields. */
object Sensitive {
    const val MESSAGE = "That text looks like a Social Security number. Baby Docs never needs the number, so it was not saved. Use the status or a non-sensitive reference instead."

    fun containsAny(data: BabyData): Boolean {
        val p = data.profile
        val texts = sequence {
            yield(p.employerPlanName); yield(p.benefitsContactNote)
            data.children.forEach { yield(it.name); yield(it.birthCounty); yield(it.notes) }
            data.tasks.forEach {
                yield(it.title); yield(it.detail); yield(it.deadlineBasis)
                yield(it.assigneeName); yield(it.completedByName); yield(it.parentNotes)
            }
            data.receipts.forEach { yield(it.value); yield(it.recordedByName) }
            data.vault.forEach { yield(it.customTitle); yield(it.notes) }
        }
        return texts.any(PlanSeed::containsSocialSecurityNumber)
    }
}
