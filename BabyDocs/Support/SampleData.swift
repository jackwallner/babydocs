import Foundation
import SwiftData

/// Seeds previews and simulator runs.
///
/// Deliberately a family whose answers switch on the awkward rules: unmarried
/// parents with the second parent not yet on the record, a job-based plan (the
/// 30-day window, not the comfortable 60-day one), and a birth in the one state
/// with verified detail. A sample family that triggers nothing is a screenshot,
/// not a test.
@MainActor
enum SampleData {
    static func previewContainer() -> ModelContainer {
        let container = BabyModelStore.makeInMemoryContainer()
        seed(into: container.mainContext)
        return container
    }

    @discardableResult
    static func seed(into context: ModelContext) -> Child {
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = "CA"
        profile.parentage = .unmarriedBothParents
        profile.secondParentOnRecord = false
        profile.insuranceKind = .employer
        profile.employerPlanName = "Acme PPO"
        profile.hasDependentCareFSA = true
        profile.takingParentalLeave = true
        profile.wantsPassport = true
        profile.wants529 = true
        profile.wantsTrumpAccount = true

        let child = Child(
            name: "Rosa",
            birthDate: Calendar.current.date(byAdding: .day, value: -11, to: Date()) ?? Date(),
            birthStateCode: "CA"
        )
        child.birthCounty = "Alameda"
        child.ssnStatus = .requestedAtHospital
        context.insert(child)

        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        // One task already underway, so the detail screen and the export have
        // something other than an empty state to render.
        if let insurance = child.liveTasks.first(where: { $0.catalogKey == "insurance_employer" }) {
            insurance.assigneeName = "Sam"
            if let form = insurance.liveDocuments.first {
                form.isOnHand = true
                form.markedOnHandAt = Date()
            }
            let receipt = Receipt(kind: .confirmationNumber, value: "ENR-4471-22")
            receipt.task = insurance
            receipt.recordedByName = "Sam"
            context.insert(receipt)
        }

        try? context.save()
        return child
    }
}
