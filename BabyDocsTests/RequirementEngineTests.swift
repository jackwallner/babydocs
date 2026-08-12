import Foundation
import SwiftData
import Testing

@testable import BabyDocs

/// The engine's three promises: same plan on both phones, no churn when nothing
/// changed, and never destroying work a parent has already done.
@MainActor
struct RequirementEngineTests {

    private func makeContext() -> ModelContext {
        ModelContext(BabyModelStore.makeInMemoryContainer())
    }

    private func seed(_ context: ModelContext) -> (Child, FamilyProfile) {
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = "CA"
        profile.insuranceKind = .employer
        profile.parentage = .married
        profile.secondParentOnRecord = true

        let child = Child(
            name: "Rosa",
            birthDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            birthStateCode: "CA"
        )
        context.insert(child)
        return (child, profile)
    }

    // MARK: - Determinism

    @Test("Two devices generate the same task ids")
    func taskIDsAreDeterministic() {
        let childID = UUID()
        let first = RequirementEngine.taskID(childID: childID, catalogKey: "ssn_card")
        let second = RequirementEngine.taskID(childID: childID, catalogKey: "ssn_card")
        #expect(first == second)
        #expect(first != RequirementEngine.taskID(childID: childID, catalogKey: "birth_certificate"))
        #expect(first != RequirementEngine.taskID(childID: UUID(), catalogKey: "ssn_card"))
    }

    @Test("Two separate stores produce identical plans for the same family")
    func twoStoresAgree() {
        let childID = UUID()
        var idsPerRun: [Set<UUID>] = []

        for _ in 0..<2 {
            let context = makeContext()
            let (child, profile) = seed(context)
            child.id = childID
            RequirementEngine.reconcile(child: child, profile: profile, in: context)
            idsPerRun.append(Set(child.liveTasks.map(\.id)))
        }

        #expect(idsPerRun[0] == idsPerRun[1])
        #expect(!idsPerRun[0].isEmpty)
    }

    // MARK: - Idempotence

    @Test("A second pass over an unchanged family writes nothing")
    func secondPassIsANoOp() {
        let context = makeContext()
        let (child, profile) = seed(context)

        let first = RequirementEngine.reconcile(child: child, profile: profile, in: context)
        #expect(first.created > 0)

        let second = RequirementEngine.reconcile(child: child, profile: profile, in: context)
        #expect(second.created == 0)
        // This is the one that matters: an engine that bumps `updatedAt` every
        // launch puts the whole plan in the outbox every launch, and sync
        // spends its life pushing rows nobody edited.
        #expect(second.updated == 0)
        #expect(second.retired == 0)
        #expect(second.total == first.total)
    }

    @Test("Changing an answer moves the deadline in place, not into a new row")
    func changingCoverageRewritesTheSameRow() {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let employerTask = child.liveTasks.first { $0.catalogKey == "insurance_employer" }
        #expect(employerTask != nil)

        profile.insuranceKind = .marketplace
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        #expect(child.liveTasks.contains { $0.catalogKey == "insurance_marketplace" })
        #expect(!child.liveTasks.contains { $0.catalogKey == "insurance_employer" })
    }

    // MARK: - Not destroying the family's work

    @Test("A task the family has worked on survives becoming inapplicable")
    func touchedTasksAreNotRetired() {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        guard let task = child.liveTasks.first(where: { $0.catalogKey == "insurance_employer" }) else {
            Issue.record("no employer insurance task")
            return
        }
        task.completedAt = Date()
        task.completedByName = "Sam"

        profile.insuranceKind = .marketplace
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let survivor = child.liveTasks.first { $0.catalogKey == "insurance_employer" }
        #expect(survivor != nil, "a completed task was deleted by an answer change")
        #expect(survivor?.completedByName == "Sam")
    }

    @Test("Rewriting a rule never clears completion, assignment or receipts")
    func engineOwnedFieldsOnly() {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        guard let task = child.liveTasks.first(where: { $0.catalogKey == "birth_certificate" }) else {
            Issue.record("no birth certificate task")
            return
        }
        task.completedAt = Date()
        task.assigneeName = "Sam"
        task.parentNotes = "Alameda county office, 8am"
        task.liveDocuments.first?.isOnHand = true

        // Force a rule change by moving the birth date, which moves the date.
        child.birthDate = Calendar.current.date(byAdding: .day, value: -1, to: child.birthDate)!
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        #expect(task.completedAt != nil)
        #expect(task.assigneeName == "Sam")
        #expect(task.parentNotes == "Alameda county office, 8am")
        #expect(task.liveDocuments.first?.isOnHand == true)
    }

    @Test("An untouched task is retired when it stops applying")
    func untouchedTasksAreRetired() {
        let context = makeContext()
        let (child, profile) = seed(context)
        profile.wantsPassport = true
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        #expect(child.liveTasks.contains { $0.catalogKey == "passport" })

        profile.wantsPassport = false
        let result = RequirementEngine.reconcile(child: child, profile: profile, in: context)
        #expect(result.retired > 0)
        #expect(!child.liveTasks.contains { $0.catalogKey == "passport" })
    }

    // MARK: - Retiring and coming back

    @Test("A rule that applies again restores its row instead of duplicating the id")
    func retiredTasksAreRestoredInPlace() {
        // Employer to Marketplace and back is an ordinary week for a family
        // changing jobs. Because the id is derived from (child, catalog key),
        // recreating the row would put two rows with one id in the store, and
        // one server key with two writers.
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let originalID = child.liveTasks.first { $0.catalogKey == "insurance_employer" }?.id
        #expect(originalID != nil)

        profile.insuranceKind = .marketplace
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        #expect(!child.liveTasks.contains { $0.catalogKey == "insurance_employer" })

        profile.insuranceKind = .employer
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let rows = (child.tasks ?? []).filter { $0.catalogKey == "insurance_employer" }
        #expect(rows.count == 1, "the retired row was recreated rather than restored")
        #expect(rows.first?.deletedAt == nil)
        #expect(rows.first?.id == originalID)
    }

    @Test("Restoring a task brings its documents back without duplicating them")
    func restoredTasksKeepOneSetOfDocuments() {
        let context = makeContext()
        let (child, profile) = seed(context)
        profile.wantsPassport = true
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let expected = RequirementCatalog.passport.documents.count
        #expect(child.liveTasks.first { $0.catalogKey == "passport" }?.liveDocuments.count == expected)

        profile.wantsPassport = false
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        profile.wantsPassport = true
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        guard let task = child.liveTasks.first(where: { $0.catalogKey == "passport" }) else {
            Issue.record("the passport task did not come back")
            return
        }
        #expect((task.documents ?? []).count == expected, "documents were duplicated on restore")
        #expect(task.liveDocuments.count == expected)
        #expect(Set(task.liveDocuments.map(\.catalogKey)).count == expected)
    }

    @Test("A restored task and its documents keep the ids both phones derived")
    func restoreKeepsEveryDerivedID() {
        // The reason this matters is not tidiness. Both parents' phones derive
        // the same ids offline, so a row that comes back under a fresh identity
        // is a row the other phone will never recognise as the same task.
        let context = makeContext()
        let (child, profile) = seed(context)
        profile.wants529 = true
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        guard let task = child.liveTasks.first(where: { $0.catalogKey == "plan_529" }) else {
            Issue.record("no 529 task")
            return
        }
        let taskID = task.id
        let documentIDs = Set(task.liveDocuments.map(\.id))

        profile.wants529 = false
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        profile.wants529 = true
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let restored = child.liveTasks.first { $0.catalogKey == "plan_529" }
        #expect(restored?.id == taskID)
        #expect(Set(restored?.liveDocuments.map(\.id) ?? []) == documentIDs)
    }

    @Test("A retired row is not re-tombstoned on every later pass")
    func retirementIsQuietOnceItHasHappened() {
        let context = makeContext()
        let (child, profile) = seed(context)
        profile.wantsPassport = true
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        profile.wantsPassport = false
        #expect(RequirementEngine.reconcile(child: child, profile: profile, in: context).retired == 1)
        // Every launch afterwards would otherwise queue the same delete again.
        #expect(RequirementEngine.reconcile(child: child, profile: profile, in: context).retired == 0)
    }

    // MARK: - Documents

    @Test("Each task gets its document checklist")
    func documentsAreMaterialised() {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        guard let task = child.liveTasks.first(where: { $0.catalogKey == "birth_certificate" }) else {
            Issue.record("no birth certificate task")
            return
        }
        #expect(task.liveDocuments.count == RequirementCatalog.birthCertificate.documents.count)
        #expect(task.liveDocuments.map(\.catalogKey).allSatisfy { !$0.isEmpty })
    }

    @Test("Document ids are stable across passes")
    func documentIDsAreStable() {
        let context = makeContext()
        let (child, profile) = seed(context)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let task = child.liveTasks.first { $0.catalogKey == "birth_certificate" }
        let before = Set(task?.liveDocuments.map(\.id) ?? [])

        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        let after = Set(task?.liveDocuments.map(\.id) ?? [])

        #expect(before == after)
    }

    // MARK: - Whole-store pass

    @Test("Every child gets a plan when the household answer changes")
    func reconcileAllCoversEveryChild() {
        let context = makeContext()
        let (first, profile) = seed(context)
        let second = Child(
            name: "Theo",
            birthDate: Calendar.current.date(byAdding: .day, value: -400, to: Date())!,
            birthStateCode: "OR"
        )
        context.insert(second)

        _ = profile
        RequirementEngine.reconcileAll(in: context)

        #expect(!first.liveTasks.isEmpty)
        #expect(!second.liveTasks.isEmpty)
        // Different children, different rows, no shared ids.
        #expect(Set(first.liveTasks.map(\.id)).isDisjoint(with: Set(second.liveTasks.map(\.id))))
    }
}
