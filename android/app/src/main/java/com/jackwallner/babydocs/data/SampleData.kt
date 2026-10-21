package com.jackwallner.babydocs.data

import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.ParentalLeaveTakers
import com.jackwallner.babydocs.model.Receipt
import com.jackwallner.babydocs.model.ReceiptKind
import com.jackwallner.babydocs.model.SSNStatus
import com.jackwallner.babydocs.rules.RequirementEngine
import java.time.LocalDate
import java.time.ZoneId

/**
 * The sample family of `SampleData.swift`, whose answers switch on the awkward
 * rules: unmarried parents not yet on the record, a job-based plan, a birth in
 * California, one task underway and one thing sent and overdue back.
 */
object SampleData {
    fun seed(data: BabyData, today: LocalDate = LocalDate.now()): Child {
        data.profile.apply {
            residenceStateCode = "CA"
            parentage = ParentageSituation.UNMARRIED_BOTH_PARENTS
            secondParentOnRecord = false
            insuranceKind = InsuranceKind.EMPLOYER
            employerPlanName = "Acme PPO"
            benefitsContactNote = "Dana in HR, 555 0134"
            hasDependentCareFSA = true
            parentalLeaveTakers = ParentalLeaveTakers.BOTH_PARENTS
            wantsPassport = true
            wants529 = true
            wantsNewbornAccount = true
        }
        val child = Child(name = "Rosa", birthDate = today.minusDays(11), birthStateCode = "CA", birthCounty = "Alameda County", ssnStatus = SSNStatus.REQUESTED_AT_HOSPITAL)
        data.children += child
        RequirementEngine.reconcile(child, data.profile, data)

        val now = System.currentTimeMillis()
        data.liveTasks(child).firstOrNull { it.catalogKey == "insurance_employer" }?.let { insurance ->
            insurance.assigneeName = "Sam"
            data.liveDocuments(insurance).firstOrNull()?.let {
                it.isOnHand = true
                it.markedOnHandAt = now
            }
            data.receipts += Receipt(taskId = insurance.id, kind = ReceiptKind.CONFIRMATION_NUMBER, value = "ENR-4471-22", recordedByName = "Sam")
        }
        data.liveTasks(child).firstOrNull { it.catalogKey == "birth_certificate" }?.let {
            it.submittedAt = today.minusDays(34).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
            it.expectedByAt = today.minusDays(6)
        }
        return child
    }
}
