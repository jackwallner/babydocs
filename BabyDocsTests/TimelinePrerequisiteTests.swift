import Foundation
import SwiftData
import Testing

@testable import BabyDocs

/// "Waiting on something else" has to stop when the something else has arrived,
/// however the family says so.
///
/// There are two ways to say it. Ticking the ordering task is one, and the
/// timeline always honoured it. Recording on the child that the certificate or
/// the card is in hand is the other, and it is the one the Children screen
/// offers by name ("Marking the certificate in hand unblocks the passport
/// task"). That one retires the ordering task instead of completing it, so a
/// timeline that only looks for ticked tasks waits for ever.
@MainActor
struct TimelinePrerequisiteTests {
    private let today = DateOnly.date(from: "2026-08-22")!

    private func makeFamily(in context: ModelContext) -> (child: Child, profile: FamilyProfile) {
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = "CA"
        profile.parentage = .married
        profile.secondParentOnRecord = true
        profile.insuranceKind = .employer
        profile.parentalLeaveTakers = .nobody
        profile.wantsPassport = true
        profile.wants529 = true
        profile.wantsNewbornAccount = true

        let child = Child(name: "Rosa", birthDate: DateOnly.date(from: "2026-08-17")!, birthStateCode: "CA")
        child.isUSCitizen = true
        context.insert(child)
        RequirementEngine.reconcile(child: child, profile: profile, in: context, now: today)
        return (child, profile)
    }

    private func task(_ key: String, of child: Child) -> RequirementTask? {
        child.liveTasks.first { $0.catalogKey == key }
    }

    private func timelineStep(_ key: String, of child: Child) -> PlanTimeline.Step? {
        guard let match = task(key, of: child) else { return nil }
        return PlanTimeline.groups(for: child.liveTasks, now: today)
            .flatMap(\.steps)
            .first { $0.taskID == match.id }
    }

    @Test("The passport stops waiting once the certificate is recorded as in hand")
    func certificateInHandOpensThePassport() throws {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let (child, profile) = makeFamily(in: context)
        let before = try #require(timelineStep("passport", of: child))
        #expect(before.isBlocked, "Nothing has arrived yet, so the passport should be waiting")

        child.birthCertificateReceivedAt = today
        RequirementEngine.reconcile(child: child, profile: profile, in: context, now: today)

        let after = try #require(timelineStep("passport", of: child))
        #expect(!after.isBlocked, "The certificate is in hand and the passport still says it is waiting")
        #expect(after.phase == .now)
    }

    @Test("The check on the certificate is not blocked on the certificate it exists because of")
    func nameCheckIsOpenOnceTheCertificateIsInHand() throws {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let (child, profile) = makeFamily(in: context)
        #expect(timelineStep("birth_record_name_check", of: child) == nil, "It only exists once the certificate does")

        child.birthCertificateReceivedAt = today
        RequirementEngine.reconcile(child: child, profile: profile, in: context, now: today)

        let check = try #require(timelineStep("birth_record_name_check", of: child))
        #expect(!check.isBlocked, "A task that only exists because the copy is in hand is waiting for the copy")
        #expect(check.phase == .now)
    }

    @Test("Everything that waits on the Social Security card opens when the card is received")
    func cardReceivedOpensWhatWaitedOnIt() throws {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let (child, profile) = makeFamily(in: context)
        let waiting = ["trump_account", "tax_dependent", "plan_529"]
        for key in waiting {
            let before = try #require(timelineStep(key, of: child))
            #expect(before.isBlocked, "\(key) should wait for the card")
        }

        child.ssnStatus = .cardReceived
        RequirementEngine.reconcile(child: child, profile: profile, in: context, now: today)

        for key in waiting {
            let after = try #require(timelineStep(key, of: child))
            #expect(!after.isBlocked, "\(key) is still waiting for a card the family has received")
        }
    }

    @Test("The task screen's own timing line agrees with the timeline")
    func taskScreenAgreesWithTheTimeline() throws {
        // TaskDetailView asks `PlanTimeline.step` directly, with the keys of
        // the child's ticked tasks, rather than going through `groups`.
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let (child, profile) = makeFamily(in: context)
        child.birthCertificateReceivedAt = today
        RequirementEngine.reconcile(child: child, profile: profile, in: context, now: today)

        let passport = try #require(task("passport", of: child))
        let ticked = Set(child.liveTasks.filter(\.isDone).map(\.catalogKey))
        let line = PlanTimeline.step(for: passport, completedKeys: ticked, now: today)

        #expect(!line.isBlocked)
        #expect(!line.reason.isEmpty, "The reason line says why it is open")
    }

    @Test("Ticking the ordering task still opens what waits on it")
    func tickingTheOrderingTaskStillWorks() throws {
        let context = ModelContext(BabyModelStore.makeInMemoryContainer())
        let (child, _) = makeFamily(in: context)
        let ordering = try #require(task("birth_certificate", of: child))
        ordering.setCompleted(true, at: today)

        let passport = try #require(timelineStep("passport", of: child))
        #expect(!passport.isBlocked)
    }
}
