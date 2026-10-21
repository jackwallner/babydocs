package com.jackwallner.babydocs.model

import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * The SwiftData models of `BabyModels.swift`, as plain mutable records held by
 * `BabyStore`. Calendar days (a birth date, a deadline) are `LocalDate`, which
 * is what iOS's UTC-noon `DateOnly` encoding exists to approximate; moments
 * (ticked, sent, edited) are epoch milliseconds.
 *
 * Every row carries `updatedAt` and `deletedAt`: deleting is a tombstone, so a
 * mis-swipe on a task carrying receipts is recoverable, exactly as on iOS.
 */
interface LocalRecord {
    val id: UUID
    var updatedAt: Long
    var deletedAt: Long?
}

class Child(
    override val id: UUID = UUID.randomUUID(),
    var name: String = "",
    var birthDate: LocalDate = LocalDate.now(),
    var birthStateCode: String = "",
    var birthCounty: String = "",
    var isUSCitizen: Boolean = true,
    var isEphemeralDraft: Boolean = false,
    var ssnStatus: SSNStatus = SSNStatus.UNKNOWN,
    var ssnReceivedAt: Long? = null,
    var birthCertificateReceivedAt: Long? = null,
    var certifiedCopiesOnHand: Int = 0,
    var colorIndex: Int = 0,
    var notes: String = "",
    override var updatedAt: Long = System.currentTimeMillis(),
    override var deletedAt: Long? = null,
) : LocalRecord {
    val hasSSN: Boolean get() = ssnStatus == SSNStatus.CARD_RECEIVED

    val displayName: String get() = if (name.isBlank()) "Your baby" else name

    val initials: String
        get() {
            val letters = name.split(" ").filter { it.isNotEmpty() }.take(2).map { it.first() }
            return if (letters.isEmpty()) "?" else letters.joinToString("").uppercase()
        }

    fun ageInDays(today: LocalDate = LocalDate.now()): Long = ChronoUnit.DAYS.between(birthDate, today)
}

class FamilyProfile(
    override val id: UUID = UUID.randomUUID(),
    var residenceStateCode: String = "",
    var parentage: ParentageSituation = ParentageSituation.UNKNOWN,
    var secondParentOnRecord: Boolean = false,
    var insuranceKind: InsuranceKind = InsuranceKind.UNKNOWN,
    var marketplaceKind: MarketplaceKind = MarketplaceKind.UNKNOWN,
    var hasDependentCareFSA: Boolean = false,
    var wantsPassport: Boolean = false,
    var wants529: Boolean = false,
    var wantsNewbornAccount: Boolean = true,
    /** Legacy storage kept in step with [parentalLeaveTakers], as on iOS. */
    var takingParentalLeave: Boolean = true,
    var parentalLeaveTakersRaw: String = "",
    var employerPlanName: String = "",
    var benefitsContactNote: String = "",
    override var updatedAt: Long = System.currentTimeMillis(),
    override var deletedAt: Long? = null,
) : LocalRecord {
    var parentalLeaveTakers: ParentalLeaveTakers
        get() = ParentalLeaveTakers.parse(parentalLeaveTakersRaw)
            ?: if (takingParentalLeave) ParentalLeaveTakers.ONE_PARENT else ParentalLeaveTakers.NOBODY
        set(value) {
            parentalLeaveTakersRaw = value.raw
            takingParentalLeave = value != ParentalLeaveTakers.NOBODY
        }

    /** A residence state and a coverage answer already produce the two hard deadlines. */
    val isComplete: Boolean get() = residenceStateCode.isNotEmpty() && insuranceKind != InsuranceKind.UNKNOWN
}

class RequirementTask(
    override var id: UUID = UUID.randomUUID(),
    var childId: UUID? = null,
    var catalogKey: String = "",
    var title: String = "",
    var detail: String = "",
    var category: RequirementCategory = RequirementCategory.IDENTITY,
    var dueAt: LocalDate? = null,
    var deadlineKind: DeadlineKind = DeadlineKind.NONE,
    var deadlineBasis: String = "",
    var officialURLString: String = "",
    var officialLinkLabel: String = "",
    var sourceURLString: String = "",
    var sourceVerifiedOn: LocalDate? = null,
    var assigneeName: String = "",
    var completedAt: Long? = null,
    var completedByName: String = "",
    var isPostedAway: Boolean = false,
    var submittedAt: Long? = null,
    var expectedByAt: LocalDate? = null,
    var dismissedAt: Long? = null,
    var parentNotes: String = "",
    /** A reminder the family asked for, never drawn as a deadline. Epoch millis. */
    var customReminderAt: Long? = null,
    var sortWeight: Int = 100,
    var isCustom: Boolean = false,
    override var updatedAt: Long = System.currentTimeMillis(),
    override var deletedAt: Long? = null,
) : LocalRecord {
    val isDone: Boolean get() = completedAt != null
    val isDismissed: Boolean get() = dismissedAt != null
    val isOpen: Boolean get() = !isDone && !isDismissed

    /** Completion and dismissal are different answers, so they are mutually exclusive. */
    fun setCompleted(completed: Boolean, at: Long = System.currentTimeMillis()) {
        completedAt = if (completed) at else null
        if (completed) dismissedAt = null
    }

    fun setDismissed(dismissed: Boolean, at: Long = System.currentTimeMillis()) {
        dismissedAt = if (dismissed) at else null
        if (dismissed) completedAt = null
    }

    /** Sent, past the date it should have come back, and still not ticked off. */
    fun isLate(today: LocalDate = LocalDate.now()): Boolean {
        val expected = expectedByAt ?: return false
        return isOpen && submittedAt != null && expected.isBefore(today)
    }

    /** Whole days from today until the deadline. Negative once it has passed. */
    fun daysRemaining(today: LocalDate = LocalDate.now()): Int? =
        dueAt?.let { ChronoUnit.DAYS.between(today, it).toInt() }
}

class DocumentItem(
    override var id: UUID = UUID.randomUUID(),
    var taskId: UUID? = null,
    var catalogKey: String = "",
    var title: String = "",
    var detail: String = "",
    var isOnHand: Boolean = false,
    var markedOnHandAt: Long? = null,
    var sortWeight: Int = 100,
    override var updatedAt: Long = System.currentTimeMillis(),
    override var deletedAt: Long? = null,
) : LocalRecord

class Receipt(
    override val id: UUID = UUID.randomUUID(),
    var taskId: UUID? = null,
    var kind: ReceiptKind = ReceiptKind.NOTE,
    var value: String = "",
    var recordedAt: Long = System.currentTimeMillis(),
    var recordedByName: String = "",
    override var updatedAt: Long = System.currentTimeMillis(),
    override var deletedAt: Long? = null,
) : LocalRecord

class VaultDocument(
    override val id: UUID = UUID.randomUUID(),
    var childId: UUID? = null,
    var kind: VaultDocumentKind = VaultDocumentKind.OTHER,
    var customTitle: String = "",
    /** Filenames within the vault directory, never paths and never image bytes. */
    var pageFileNames: List<String> = emptyList(),
    var addedAt: Long = System.currentTimeMillis(),
    var notes: String = "",
    override var updatedAt: Long = System.currentTimeMillis(),
    override var deletedAt: Long? = null,
) : LocalRecord {
    val displayTitle: String
        get() = if (kind == VaultDocumentKind.OTHER) customTitle.trim().ifEmpty { VaultDocumentKind.OTHER.label } else kind.label
}

fun Long.toLocalDate(zone: ZoneId = ZoneId.systemDefault()): LocalDate =
    java.time.Instant.ofEpochMilli(this).atZone(zone).toLocalDate()
