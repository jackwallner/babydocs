package com.jackwallner.babydocs.data

import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.DocumentItem
import com.jackwallner.babydocs.model.FamilyProfile
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.MarketplaceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.Receipt
import com.jackwallner.babydocs.model.ReceiptKind
import com.jackwallner.babydocs.model.RequirementCategory
import com.jackwallner.babydocs.model.RequirementTask
import com.jackwallner.babydocs.model.SSNStatus
import com.jackwallner.babydocs.model.VaultDocument
import com.jackwallner.babydocs.model.VaultDocumentKind
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.util.UUID

/** The store file format. Field names match the iOS model properties. */
object Codecs {
    fun encode(data: BabyData): String = JSONObject().apply {
        put("version", 1)
        put("profile", profile(data.profile))
        put("children", JSONArray(data.children.map(::child)))
        put("tasks", JSONArray(data.tasks.map(::task)))
        put("documents", JSONArray(data.documents.map(::document)))
        put("receipts", JSONArray(data.receipts.map(::receipt)))
        put("vault", JSONArray(data.vault.map(::vault)))
    }.toString()

    fun decode(text: String): BabyData {
        val o = JSONObject(text)
        return BabyData(
            profile = o.optJSONObject("profile")?.let(::profile) ?: FamilyProfile(),
            children = o.list("children", ::child),
            tasks = o.list("tasks", ::task),
            documents = o.list("documents", ::document),
            receipts = o.list("receipts", ::receipt),
            vault = o.list("vault", ::vault),
        )
    }

    private fun <T> JSONObject.list(key: String, decode: (JSONObject) -> T): MutableList<T> {
        val array = optJSONArray(key) ?: return mutableListOf()
        return (0 until array.length()).map { decode(array.getJSONObject(it)) }.toMutableList()
    }

    private fun JSONObject.long(key: String): Long? = if (has(key) && !isNull(key)) getLong(key) else null
    private fun JSONObject.day(key: String): LocalDate? = if (has(key) && !isNull(key)) LocalDate.parse(getString(key)) else null
    private fun JSONObject.uuid(key: String): UUID? = if (has(key) && !isNull(key)) UUID.fromString(getString(key)) else null
    private fun JSONObject.str(key: String) = optString(key, "")
    private fun JSONObject.putOpt(key: String, value: Any?) = put(key, value ?: JSONObject.NULL)

    private fun profile(p: FamilyProfile) = JSONObject().apply {
        put("id", p.id.toString())
        put("residenceStateCode", p.residenceStateCode)
        put("parentageRaw", p.parentage.raw)
        put("secondParentOnRecord", p.secondParentOnRecord)
        put("insuranceKindRaw", p.insuranceKind.raw)
        put("marketplaceKindRaw", p.marketplaceKind.raw)
        put("hasDependentCareFSA", p.hasDependentCareFSA)
        put("wantsPassport", p.wantsPassport)
        put("wants529", p.wants529)
        put("wantsNewbornAccount", p.wantsNewbornAccount)
        put("takingParentalLeave", p.takingParentalLeave)
        put("parentalLeaveTakersRaw", p.parentalLeaveTakersRaw)
        put("employerPlanName", p.employerPlanName)
        put("benefitsContactNote", p.benefitsContactNote)
        put("updatedAt", p.updatedAt)
        putOpt("deletedAt", p.deletedAt)
    }

    private fun profile(o: JSONObject) = FamilyProfile(
        id = o.uuid("id") ?: UUID.randomUUID(),
        residenceStateCode = o.str("residenceStateCode"),
        parentage = ParentageSituation.of(o.str("parentageRaw")),
        secondParentOnRecord = o.optBoolean("secondParentOnRecord"),
        insuranceKind = InsuranceKind.of(o.str("insuranceKindRaw")),
        marketplaceKind = MarketplaceKind.of(o.str("marketplaceKindRaw")),
        hasDependentCareFSA = o.optBoolean("hasDependentCareFSA"),
        wantsPassport = o.optBoolean("wantsPassport"),
        wants529 = o.optBoolean("wants529"),
        wantsNewbornAccount = o.optBoolean("wantsNewbornAccount", true),
        takingParentalLeave = o.optBoolean("takingParentalLeave", true),
        parentalLeaveTakersRaw = o.str("parentalLeaveTakersRaw"),
        employerPlanName = o.str("employerPlanName"),
        benefitsContactNote = o.str("benefitsContactNote"),
        updatedAt = o.optLong("updatedAt"),
        deletedAt = o.long("deletedAt"),
    )

    private fun child(c: Child) = JSONObject().apply {
        put("id", c.id.toString())
        put("name", c.name)
        put("birthDate", c.birthDate.toString())
        put("birthStateCode", c.birthStateCode)
        put("birthCounty", c.birthCounty)
        put("isUSCitizen", c.isUSCitizen)
        put("isEphemeralDraft", c.isEphemeralDraft)
        put("ssnStatusRaw", c.ssnStatus.raw)
        putOpt("ssnReceivedAt", c.ssnReceivedAt)
        putOpt("birthCertificateReceivedAt", c.birthCertificateReceivedAt)
        put("certifiedCopiesOnHand", c.certifiedCopiesOnHand)
        put("colorIndex", c.colorIndex)
        put("notes", c.notes)
        put("updatedAt", c.updatedAt)
        putOpt("deletedAt", c.deletedAt)
    }

    private fun child(o: JSONObject) = Child(
        id = o.uuid("id") ?: UUID.randomUUID(),
        name = o.str("name"),
        birthDate = o.day("birthDate") ?: LocalDate.now(),
        birthStateCode = o.str("birthStateCode"),
        birthCounty = o.str("birthCounty"),
        isUSCitizen = o.optBoolean("isUSCitizen", true),
        isEphemeralDraft = o.optBoolean("isEphemeralDraft"),
        ssnStatus = SSNStatus.of(o.str("ssnStatusRaw")),
        ssnReceivedAt = o.long("ssnReceivedAt"),
        birthCertificateReceivedAt = o.long("birthCertificateReceivedAt"),
        certifiedCopiesOnHand = o.optInt("certifiedCopiesOnHand"),
        colorIndex = o.optInt("colorIndex"),
        notes = o.str("notes"),
        updatedAt = o.optLong("updatedAt"),
        deletedAt = o.long("deletedAt"),
    )

    private fun task(t: RequirementTask) = JSONObject().apply {
        put("id", t.id.toString())
        putOpt("childId", t.childId?.toString())
        put("catalogKey", t.catalogKey)
        put("title", t.title)
        put("detail", t.detail)
        put("categoryRaw", t.category.raw)
        putOpt("dueAt", t.dueAt?.toString())
        put("deadlineKindRaw", t.deadlineKind.raw)
        put("deadlineBasis", t.deadlineBasis)
        put("officialURLString", t.officialURLString)
        put("officialLinkLabel", t.officialLinkLabel)
        put("sourceURLString", t.sourceURLString)
        putOpt("sourceVerifiedOn", t.sourceVerifiedOn?.toString())
        put("assigneeName", t.assigneeName)
        putOpt("completedAt", t.completedAt)
        put("completedByName", t.completedByName)
        put("isPostedAway", t.isPostedAway)
        putOpt("submittedAt", t.submittedAt)
        putOpt("expectedByAt", t.expectedByAt?.toString())
        putOpt("dismissedAt", t.dismissedAt)
        put("parentNotes", t.parentNotes)
        putOpt("customReminderAt", t.customReminderAt)
        put("sortWeight", t.sortWeight)
        put("isCustom", t.isCustom)
        put("updatedAt", t.updatedAt)
        putOpt("deletedAt", t.deletedAt)
    }

    private fun task(o: JSONObject) = RequirementTask(
        id = o.uuid("id") ?: UUID.randomUUID(),
        childId = o.uuid("childId"),
        catalogKey = o.str("catalogKey"),
        title = o.str("title"),
        detail = o.str("detail"),
        category = RequirementCategory.of(o.str("categoryRaw")),
        dueAt = o.day("dueAt"),
        deadlineKind = DeadlineKind.of(o.str("deadlineKindRaw")),
        deadlineBasis = o.str("deadlineBasis"),
        officialURLString = o.str("officialURLString"),
        officialLinkLabel = o.str("officialLinkLabel"),
        sourceURLString = o.str("sourceURLString"),
        sourceVerifiedOn = o.day("sourceVerifiedOn"),
        assigneeName = o.str("assigneeName"),
        completedAt = o.long("completedAt"),
        completedByName = o.str("completedByName"),
        isPostedAway = o.optBoolean("isPostedAway"),
        submittedAt = o.long("submittedAt"),
        expectedByAt = o.day("expectedByAt"),
        dismissedAt = o.long("dismissedAt"),
        parentNotes = o.str("parentNotes"),
        customReminderAt = o.long("customReminderAt"),
        sortWeight = o.optInt("sortWeight", 100),
        isCustom = o.optBoolean("isCustom"),
        updatedAt = o.optLong("updatedAt"),
        deletedAt = o.long("deletedAt"),
    )

    private fun document(d: DocumentItem) = JSONObject().apply {
        put("id", d.id.toString())
        putOpt("taskId", d.taskId?.toString())
        put("catalogKey", d.catalogKey)
        put("title", d.title)
        put("detail", d.detail)
        put("isOnHand", d.isOnHand)
        putOpt("markedOnHandAt", d.markedOnHandAt)
        put("sortWeight", d.sortWeight)
        put("updatedAt", d.updatedAt)
        putOpt("deletedAt", d.deletedAt)
    }

    private fun document(o: JSONObject) = DocumentItem(
        id = o.uuid("id") ?: UUID.randomUUID(),
        taskId = o.uuid("taskId"),
        catalogKey = o.str("catalogKey"),
        title = o.str("title"),
        detail = o.str("detail"),
        isOnHand = o.optBoolean("isOnHand"),
        markedOnHandAt = o.long("markedOnHandAt"),
        sortWeight = o.optInt("sortWeight", 100),
        updatedAt = o.optLong("updatedAt"),
        deletedAt = o.long("deletedAt"),
    )

    private fun receipt(r: Receipt) = JSONObject().apply {
        put("id", r.id.toString())
        putOpt("taskId", r.taskId?.toString())
        put("kindRaw", r.kind.raw)
        put("value", r.value)
        put("recordedAt", r.recordedAt)
        put("recordedByName", r.recordedByName)
        put("updatedAt", r.updatedAt)
        putOpt("deletedAt", r.deletedAt)
    }

    private fun receipt(o: JSONObject) = Receipt(
        id = o.uuid("id") ?: UUID.randomUUID(),
        taskId = o.uuid("taskId"),
        kind = ReceiptKind.of(o.str("kindRaw")),
        value = o.str("value"),
        recordedAt = o.optLong("recordedAt"),
        recordedByName = o.str("recordedByName"),
        updatedAt = o.optLong("updatedAt"),
        deletedAt = o.long("deletedAt"),
    )

    private fun vault(v: VaultDocument) = JSONObject().apply {
        put("id", v.id.toString())
        putOpt("childId", v.childId?.toString())
        put("kindRaw", v.kind.raw)
        put("customTitle", v.customTitle)
        put("pageFileNames", JSONArray(v.pageFileNames))
        put("addedAt", v.addedAt)
        put("notes", v.notes)
        put("updatedAt", v.updatedAt)
        putOpt("deletedAt", v.deletedAt)
    }

    private fun vault(o: JSONObject) = VaultDocument(
        id = o.uuid("id") ?: UUID.randomUUID(),
        childId = o.uuid("childId"),
        kind = VaultDocumentKind.of(o.str("kindRaw")),
        customTitle = o.str("customTitle"),
        pageFileNames = o.optJSONArray("pageFileNames")?.let { a -> (0 until a.length()).map { a.getString(it) } }.orEmpty(),
        addedAt = o.optLong("addedAt"),
        notes = o.str("notes"),
        updatedAt = o.optLong("updatedAt"),
        deletedAt = o.long("deletedAt"),
    )
}
