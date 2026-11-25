import Foundation
import SwiftData
import Testing

@testable import BabyDocs

/// Repro suite for the 2026-11-24 state machine audit. Kept beside the audit as
/// `project-docs/audits/state-machines-2026-11-24-repro.swift`, out of the test
/// target; copy it into `BabyDocsTests/` to run it. Each claim asserts its
/// preconditions first, then the promise. Each has a passing control.
@MainActor
struct StateMachineAuditRepro {

    // MARK: - Fixtures

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
    private func tickInDocumentsTab(_ title: String, in child: Child, context: ModelContext) {
        let matches = documents(titled: title, in: child)
        for match in matches {
            match.isOnHand = true
            match.markedOnHandAt = Date()
        }
        matches.first?.recordLocalChange(in: context)
    }

    // MARK: - B1: a document already in hand is asked for again

    /// Promise: `DocumentsView.swift:277-280`, "A document title appears on
    /// several of one child's tasks, so ticking it has to tick all of them.
    /// Anything else means a parent finds the certificate, ticks it, and the app
    /// keeps asking for it on three other screens."
    @Test("B1: a task added by a changed answer inherits a document already in hand")
    func newTaskInheritsDocumentAlreadyInHand() throws {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        // Preconditions: several tasks ask for proof of birth, no leave task yet.
        let before = documents(titled: "Proof of the birth", in: child)
        try #require(before.count >= 2)
        try #require(!child.liveTasks.contains { $0.catalogKey == "parental_leave_claim" })

        tickInDocumentsTab("Proof of the birth", in: child, context: context)
        try #require(documents(titled: "Proof of the birth", in: child).allSatisfy(\.isOnHand))

        // Plan > Change household answers > one parent takes leave.
        profile.parentalLeaveTakers = .oneParent
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let leave = try #require(child.liveTasks.first { $0.catalogKey == "parental_leave_claim" })
        let proof = try #require(leave.liveDocuments.first { $0.title == "Proof of the birth" })
        #expect(proof.isOnHand, "proof of birth is in hand, but the new leave task asks for it again")
    }

    @Test("B1 control: a document nobody has ticked stays to find")
    func controlUntickedDocumentStaysToFind() throws {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        tickInDocumentsTab("Proof of the birth", in: child, context: context)

        profile.parentalLeaveTakers = .oneParent
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let leave = try #require(child.liveTasks.first { $0.catalogKey == "parental_leave_claim" })
        let form = try #require(leave.liveDocuments.first { $0.catalogKey == "employer_form" })
        #expect(!form.isOnHand)
    }

    // MARK: - B2: one beaten deadline counted twice

    private func freshTracker() {
        let suite = UserDefaults(suiteName: "babydocs.audit.\(UUID().uuidString)") ?? .standard
        ReviewPromptTracker.useDefaultsForTesting(suite)
    }

    private func hardTask(dueInDays days: Int, now: Date) -> RequirementTask {
        let task = RequirementTask(title: "Add the baby to the job-based plan")
        task.deadlineKind = .hard
        task.dueAt = Calendar.current.date(byAdding: .day, value: days, to: now)
        return task
    }

    /// Promise: `ReviewPromptTracker.swift:50-52`, "Deadlines beaten. Two,
    /// because one could be luck". Ticking, unticking and ticking the same task
    /// is one deadline beaten.
    @Test("B2: ticking one hard task twice is one deadline beaten")
    func retickingOneTaskCountsOnce() {
        freshTracker()
        let now = Date()
        let task = hardTask(dueInDays: 20, now: now)

        task.setCompleted(true, at: now)
        ReviewPromptTracker.recordCompletion(of: task, now: now)
        #expect(ReviewPromptTracker.positiveMomentCount == 1)
        task.setCompleted(false, at: now)
        task.setCompleted(true, at: now)
        ReviewPromptTracker.recordCompletion(of: task, now: now)
        #expect(ReviewPromptTracker.positiveMomentCount == 1, "one task, two moments")
    }

    @Test("B2 control: two different hard tasks are two moments")
    func controlTwoTasksCountTwice() {
        freshTracker()
        let now = Date()
        ReviewPromptTracker.recordCompletion(of: hardTask(dueInDays: 20, now: now), now: now)
        ReviewPromptTracker.recordCompletion(of: hardTask(dueInDays: 40, now: now), now: now)
        #expect(ReviewPromptTracker.positiveMomentCount == 2)
    }

    // MARK: - Product call evidence: one hard deadline per child

    /// Not a claim. Shows why the review gate's "two deadlines beaten" is out
    /// of reach for a one-child family: every coverage answer yields at most
    /// one hard deadline.
    @Test("Evidence: no coverage answer gives a child two hard deadlines")
    func atMostOneHardDeadlinePerChild() {
        for kind in InsuranceKind.allCases {
            let context = makeContext()
            let (child, profile) = seed(context)
            profile.insuranceKind = kind
            profile.parentalLeaveTakers = .bothParents
            profile.hasDependentCareFSA = true
            profile.wantsPassport = true
            profile.wants529 = true
            profile.wantsNewbornAccount = true
            RequirementEngine.reconcile(child: child, profile: profile, in: context)
            let hard = child.liveTasks.filter { $0.deadlineKind == .hard }
            #expect(hard.count <= 1, "\(kind): \(hard.map(\.catalogKey))")
        }
    }
}
