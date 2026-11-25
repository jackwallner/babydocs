import Foundation
import SwiftData
import Testing

@testable import BabyDocs

/// Regression tests for the fixes from the 2026-11-24 state machine audit
/// (`project-docs/audits/state-machines-2026-11-24-fixes.md`).
@MainActor
struct StateMachineRegressionTests {

    private func makeContext() -> ModelContext {
        ModelContext(BabyModelStore.makeInMemoryContainer())
    }

    /// An employer-covered family, nobody taking leave yet.
    private func seed(_ context: ModelContext) -> (Child, FamilyProfile) {
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = "CA"
        profile.insuranceKind = .employer
        profile.parentage = .married
        profile.secondParentOnRecord = true
        profile.parentalLeaveTakers = .nobody

        let child = Child(
            name: "Rosa",
            birthDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            birthStateCode: "CA"
        )
        context.insert(child)
        return (child, profile)
    }

    private func documents(titled title: String, in child: Child) -> [DocumentItem] {
        child.liveTasks.flatMap(\.liveDocuments).filter { $0.title == title }
    }

    /// What `DocumentsView.setOnHand` does: tick every row of one child that
    /// carries the title.
    private func tickInDocumentsTab(_ title: String, in child: Child, context: ModelContext) -> Date {
        let when = Date(timeIntervalSince1970: 1_780_000_000)
        let matches = documents(titled: title, in: child)
        for match in matches {
            match.isOnHand = true
            match.markedOnHandAt = when
        }
        matches.first?.recordLocalChange(in: context)
        return when
    }

    // MARK: - B1

    @Test("B1: a task added by a changed answer inherits a document already in hand")
    func newTaskInheritsDocumentAlreadyInHand() throws {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        try #require(documents(titled: "Proof of the birth", in: child).count >= 2)
        try #require(!child.liveTasks.contains { $0.catalogKey == "parental_leave_claim" })
        let tickedAt = tickInDocumentsTab("Proof of the birth", in: child, context: context)

        profile.parentalLeaveTakers = .oneParent
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let leave = try #require(child.liveTasks.first { $0.catalogKey == "parental_leave_claim" })
        let proof = try #require(leave.liveDocuments.first { $0.title == "Proof of the birth" })
        #expect(proof.isOnHand, "proof of birth is in hand, but the new leave task asks for it again")
        #expect(proof.markedOnHandAt == tickedAt)
    }

    @Test("B1: \"Not sure\" coverage answered later does not ask again for proof of birth")
    func coverageAnsweredLaterInheritsDocument() throws {
        let context = makeContext()
        let (child, profile) = seed(context)
        profile.insuranceKind = .unknown
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        try #require(!child.liveTasks.contains { $0.catalogKey == "insurance_employer" })
        _ = tickInDocumentsTab("Proof of the birth", in: child, context: context)

        profile.insuranceKind = .marketplace
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let proofs = documents(titled: "Proof of the birth", in: child)
        try #require(proofs.count >= 2)
        #expect(proofs.allSatisfy(\.isOnHand))
    }

    @Test("B1 control: a document nobody ticked stays to find")
    func untickedDocumentStaysToFind() throws {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        _ = tickInDocumentsTab("Proof of the birth", in: child, context: context)

        profile.parentalLeaveTakers = .oneParent
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let leave = try #require(child.liveTasks.first { $0.catalogKey == "parental_leave_claim" })
        let form = try #require(leave.liveDocuments.first { $0.catalogKey == "employer_form" })
        #expect(!form.isOnHand)
    }

    @Test("B1 control: one child's tick does not reach a sibling's new task")
    func tickStopsAtTheChild() throws {
        let context = makeContext()
        let (rosa, profile) = seed(context)
        let ivy = Child(name: "Ivy", birthDate: rosa.birthDate, birthStateCode: "CA")
        context.insert(ivy)
        RequirementEngine.reconcileAll(in: context)
        _ = tickInDocumentsTab("Proof of the birth", in: rosa, context: context)

        profile.parentalLeaveTakers = .oneParent
        RequirementEngine.reconcileAll(in: context)

        let leave = try #require(ivy.liveTasks.first { $0.catalogKey == "parental_leave_claim" })
        let proof = try #require(leave.liveDocuments.first { $0.title == "Proof of the birth" })
        #expect(!proof.isOnHand)
    }

    /// Upgrade: a family's stored rows are left exactly as they were. Rows
    /// already on disk, ticked or not, are not rewritten by a pass, and a pass
    /// over an unchanged family still writes nothing.
    @Test("B1 upgrade: stored rows are not rewritten")
    func storedRowsAreUntouched() throws {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        let proofs = documents(titled: "Proof of the birth", in: child)
        try #require(proofs.count >= 2)
        // A store written by an older build: one row ticked, one not.
        proofs[0].isOnHand = true
        proofs[0].markedOnHandAt = Date(timeIntervalSince1970: 1_780_000_000)
        try context.save()

        let pass = RequirementEngine.reconcile(child: child, profile: profile, in: context)
        #expect(pass.created == 0)
        #expect(pass.updated == 0)
        #expect(proofs[0].isOnHand)
        #expect(!proofs[1].isOnHand)
    }
}
