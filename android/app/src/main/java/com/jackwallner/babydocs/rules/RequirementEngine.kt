package com.jackwallner.babydocs.rules

import com.jackwallner.babydocs.data.BabyData
import com.jackwallner.babydocs.data.DeterministicID
import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.DocumentItem
import com.jackwallner.babydocs.model.FamilyProfile
import com.jackwallner.babydocs.model.RequirementTask
import java.util.UUID

/**
 * Reconciles the catalog into task rows (`RequirementEngine.swift`). The
 * engine owns the rule and the family owns the work: completion, assignment,
 * receipts and ticked documents are never rewritten. Row ids derive from
 * (child, catalog key), so a rule that stops applying is retired and later
 * restored with the family's work attached, never inserted twice. A pass that
 * changes nothing reports nothing, so the store writes nothing.
 */
object RequirementEngine {
    data class Result(var created: Int = 0, var updated: Int = 0, var retired: Int = 0, var total: Int = 0) {
        val changed: Boolean get() = created > 0 || updated > 0 || retired > 0
    }

    fun makeInput(child: Child, profile: FamilyProfile) = RuleInput(
        childName = child.name,
        birthDate = child.birthDate,
        birthStateCode = child.birthStateCode,
        isUSCitizen = child.isUSCitizen,
        hasSSN = child.hasSSN,
        ssnStatus = child.ssnStatus,
        hasBirthCertificate = child.birthCertificateReceivedAt != null,
        residenceStateCode = profile.residenceStateCode,
        parentage = profile.parentage,
        secondParentOnRecord = profile.secondParentOnRecord,
        insuranceKind = profile.insuranceKind,
        marketplaceKind = profile.marketplaceKind,
        hasDependentCareFSA = profile.hasDependentCareFSA,
        wantsPassport = profile.wantsPassport,
        wants529 = profile.wants529,
        wantsNewbornAccount = profile.wantsNewbornAccount,
        parentalLeaveTakers = profile.parentalLeaveTakers,
        employerPlanName = profile.employerPlanName,
        benefitsContactNote = profile.benefitsContactNote,
    )

    fun taskID(childID: UUID, catalogKey: String): UUID = DeterministicID.v5(childID, "task:$catalogKey")

    fun documentID(taskID: UUID, catalogKey: String): UUID = DeterministicID.v5(taskID, "doc:$catalogKey")

    fun reconcileAll(data: BabyData, now: Long = System.currentTimeMillis()): Result {
        val profile = data.profile
        val combined = Result()
        for (child in data.children.filter { it.deletedAt == null }) {
            val one = reconcile(child, profile, data, now)
            combined.created += one.created
            combined.updated += one.updated
            combined.retired += one.retired
            combined.total += one.total
        }
        return combined
    }

    fun reconcile(child: Child, profile: FamilyProfile, data: BabyData, now: Long = System.currentTimeMillis()): Result {
        val result = Result()
        val input = makeInput(child, profile)
        // Tombstones included: a retired row is restored, never recreated.
        val existing = data.tasks
            .filter { it.childId == child.id && it.catalogKey.isNotEmpty() }
            .groupBy { it.catalogKey }
            .mapValues { (_, rows) -> rows.firstOrNull { it.deletedAt == null } ?: rows.first() }

        val currentKeys = RequirementCatalog.all.map { it.key }.toSet()
        for (task in data.liveTasks(child)) {
            if (task.catalogKey.isNotEmpty() && task.catalogKey !in currentKeys) {
                task.deletedAt = now
                task.updatedAt = now
                result.retired += 1
            }
        }

        for (rule in RequirementCatalog.all) {
            val applies = rule.applies(input)
            val row = existing[rule.key]
            when {
                applies && row != null -> {
                    val wasRetired = row.deletedAt != null
                    if (wasRetired) restore(row, data, now)
                    if (update(row, rule, input, data, now) || wasRetired) result.updated += 1
                    result.total += 1
                }
                applies -> {
                    val task = RequirementTask(id = taskID(child.id, rule.key), childId = child.id, catalogKey = rule.key, updatedAt = now)
                    applyRule(rule, input, task)
                    data.tasks += task
                    syncDocuments(task, rule.documents, data, now)
                    result.created += 1
                    result.total += 1
                }
                row != null && row.deletedAt == null -> {
                    // A changed answer removes the rule from the plan but never destroys the family's work.
                    row.deletedAt = now
                    row.updatedAt = now
                    result.retired += 1
                }
            }
        }
        return result
    }

    private fun update(task: RequirementTask, rule: RequirementRule, input: RuleInput, data: BabyData, now: Long): Boolean {
        val before = fingerprint(task)
        applyRule(rule, input, task)
        val changed = fingerprint(task) != before
        val documentsChanged = syncDocuments(task, rule.documents, data, now)
        if (changed || documentsChanged) task.updatedAt = now
        return changed || documentsChanged
    }

    private fun applyRule(rule: RequirementRule, input: RuleInput, task: RequirementTask) {
        val deadline = rule.deadline(input)
        val link = rule.link(input)
        task.title = rule.title(input)
        task.detail = rule.detail(input)
        task.category = rule.category
        task.sortWeight = rule.sortWeight
        task.dueAt = deadline.date
        task.deadlineKind = deadline.kind
        task.deadlineBasis = deadline.basis
        task.officialURLString = link?.urlString.orEmpty()
        task.officialLinkLabel = link?.label.orEmpty()
        task.isPostedAway = rule.isPostedAway
        task.isCustom = false
        task.sourceURLString = rule.source?.urlString.orEmpty()
        task.sourceVerifiedOn = rule.source?.reviewedOn
    }

    private fun restore(task: RequirementTask, data: BabyData, now: Long) {
        task.deletedAt = null
        task.updatedAt = now
        data.documents.filter { it.taskId == task.id && it.deletedAt != null }.forEach {
            it.deletedAt = null
            it.updatedAt = now
        }
    }

    private fun fingerprint(task: RequirementTask): String = listOf(
        task.title, task.detail, task.category.raw, task.sortWeight.toString(), task.dueAt?.toString().orEmpty(),
        task.deadlineKind.raw, task.deadlineBasis, task.officialURLString, task.officialLinkLabel,
        task.isPostedAway.toString(), task.sourceURLString, task.sourceVerifiedOn?.toString().orEmpty(),
    ).joinToString("\u001F")

    private fun syncDocuments(task: RequirementTask, specs: List<DocumentSpec>, data: BabyData, now: Long): Boolean {
        var changed = false
        val existing = data.documents
            .filter { it.taskId == task.id && it.catalogKey.isNotEmpty() }
            .groupBy { it.catalogKey }
            .mapValues { (_, rows) -> rows.firstOrNull { it.deletedAt == null } ?: rows.first() }

        specs.forEachIndexed { index, spec ->
            val item = existing[spec.key]
            if (item != null) {
                val wasRetired = item.deletedAt != null
                if (wasRetired) item.deletedAt = null
                if (wasRetired || item.title != spec.title || item.detail != spec.detail || item.sortWeight != index) {
                    item.title = spec.title
                    item.detail = spec.detail
                    item.sortWeight = index
                    item.updatedAt = now
                    changed = true
                }
            } else {
                data.documents += DocumentItem(
                    id = documentID(task.id, spec.key),
                    taskId = task.id,
                    catalogKey = spec.key,
                    title = spec.title,
                    detail = spec.detail,
                    sortWeight = index,
                    updatedAt = now,
                )
                changed = true
            }
        }

        val currentKeys = specs.map { it.key }.toSet()
        for (item in data.liveDocuments(task)) {
            if (item.catalogKey.isNotEmpty() && item.catalogKey !in currentKeys) {
                item.deletedAt = now
                item.updatedAt = now
                changed = true
            }
        }
        return changed
    }
}
