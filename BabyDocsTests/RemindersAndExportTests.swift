import Foundation
import SwiftData
import Testing

@testable import BabyDocs

@MainActor
struct RemindersAndExportTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func makeContext() -> ModelContext {
        ModelContext(BabyModelStore.makeInMemoryContainer())
    }

    private func task(
        title: String,
        dueInDays: Int,
        kind: DeadlineKind,
        child: Child? = nil
    ) -> RequirementTask {
        let task = RequirementTask(title: title)
        task.dueAt = Calendar.current.date(byAdding: .day, value: dueInDays, to: now)
        task.deadlineKind = kind
        task.deadlineBasis = "Because the plan says so."
        task.child = child
        return task
    }

    // MARK: - Reminders

    @Test("Only hard deadlines are scheduled")
    func onlyHardDeadlinesFire() {
        // A suggestion that fires at 9am is what teaches someone to switch the
        // whole category off, and then they miss the one that mattered.
        let plans = DeadlineReminderScheduler.plans(
            for: [
                task(title: "Insurance", dueInDays: 30, kind: .hard),
                task(title: "Update the W-4", dueInDays: 30, kind: .recommended),
                task(title: "Childcare", dueInDays: 30, kind: .none)
            ],
            now: now
        )
        #expect(plans.allSatisfy { $0.body.contains("Insurance") })
        #expect(plans.count == DeadlineReminderScheduler.leadDays.count)
    }

    @Test("A completed task schedules nothing")
    func completedTasksAreSilent() {
        let done = task(title: "Insurance", dueInDays: 30, kind: .hard)
        done.completedAt = now
        #expect(DeadlineReminderScheduler.plans(for: [done], now: now).isEmpty)
    }

    @Test("A deadline already past schedules nothing")
    func pastDeadlinesAreSilent() {
        #expect(
            DeadlineReminderScheduler.plans(
                for: [task(title: "Insurance", dueInDays: -1, kind: .hard)],
                now: now
            ).isEmpty
        )
    }

    @Test("Reminders never exceed the platform's pending limit")
    func scheduleIsCapped() {
        // iOS silently drops everything past 64 pending local notifications,
        // and the ones it drops are not the ones you would choose.
        let many = (1...60).map { task(title: "Task \($0)", dueInDays: 20 + $0, kind: .hard) }
        let plans = DeadlineReminderScheduler.plans(for: many, now: now)
        #expect(plans.count == DeadlineReminderScheduler.maxScheduled)
    }

    @Test("The soonest deadlines are the ones that survive the cap")
    func capKeepsTheSoonest() {
        let many = (1...60).map { task(title: "Task \($0)", dueInDays: 20 + $0, kind: .hard) }
        let plans = DeadlineReminderScheduler.plans(for: many, now: now)
        let cutoff = plans.map(\.fireAt).max()!
        let dropped = many
            .filter { $0.dueAt! > cutoff }
            .compactMap { $0.dueAt }
        #expect(dropped.allSatisfy { $0 > cutoff })
    }

    @Test("Reminder identifiers are stable, so rescheduling replaces rather than duplicates")
    func identifiersAreStable() {
        let one = task(title: "Insurance", dueInDays: 30, kind: .hard)
        let first = DeadlineReminderScheduler.plans(for: [one], now: now).map(\.identifier)
        let second = DeadlineReminderScheduler.plans(for: [one], now: now).map(\.identifier)
        #expect(first == second)
        #expect(Set(first).count == first.count)
    }

    // MARK: - Export

    @Test("The one-pager never prints a Social Security number")
    func exportOmitsTheSSN() {
        let context = makeContext()
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = "CA"
        profile.insuranceKind = .employer

        let child = Child(name: "Rosa", birthDate: now, birthStateCode: "CA")
        child.ssnStatus = .cardReceived
        child.ssnReceivedAt = now
        context.insert(child)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let text = PlanExporter.summary(for: child, profile: profile, now: now)
        // The status is useful on a shared page. The number never is, and a
        // plain-text export is the easiest thing in the app to forward.
        #expect(text.contains("Social Security: Card received"))
        #expect(!text.lowercased().contains("ssn:"))
    }

    @Test("Empty sections print as empty rather than vanishing")
    func emptySectionsStillPrint() {
        // A section that simply disappears reads as a negative answer to
        // whoever is holding the page.
        let context = makeContext()
        let profile = FamilyProfileStore.current(in: context)
        let child = Child(name: "Rosa", birthDate: now, birthStateCode: "CA")
        context.insert(child)

        let text = PlanExporter.summary(for: child, profile: profile, now: now)
        #expect(text.contains("DONE"))
        #expect(text.contains("nothing yet"))
        #expect(text.contains("Birth certificate: not received"))
    }

    @Test("The export carries the disclaimer")
    func exportCarriesTheDisclaimer() {
        let context = makeContext()
        let profile = FamilyProfileStore.current(in: context)
        let child = Child(name: "Rosa", birthDate: now)
        context.insert(child)
        let text = PlanExporter.summary(for: child, profile: profile, now: now)
        #expect(text.contains("not legal, tax, medical or insurance"))
        #expect(text.contains("does not file anything"))
    }

    @Test("Hard deadlines are marked in the plain-text export")
    func exportMarksHardDeadlines() {
        let context = makeContext()
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = "CA"
        profile.insuranceKind = .employer
        let child = Child(name: "Rosa", birthDate: now, birthStateCode: "CA")
        context.insert(child)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)

        let text = PlanExporter.summary(for: child, profile: profile, now: now)
        #expect(text.contains("!"))
        #expect(text.contains("NEXT HARD DEADLINE"))
    }
}
