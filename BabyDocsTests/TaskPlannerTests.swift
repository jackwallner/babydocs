import Foundation
import SwiftData
import Testing

@testable import BabyDocs

@MainActor
struct TaskPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func task(
        title: String = "Task",
        dueInDays: Int?,
        kind: DeadlineKind = .recommended,
        weight: Int = 100,
        done: Bool = false
    ) -> RequirementTask {
        let task = RequirementTask(title: title)
        task.dueAt = dueInDays.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }
        task.deadlineKind = kind
        task.sortWeight = weight
        if done { task.completedAt = now }
        return task
    }

    @Test("Tasks land in the right bucket")
    func bucketing() {
        #expect(TaskPlanner.bucket(for: task(dueInDays: -3), now: now) == .overdue)
        #expect(TaskPlanner.bucket(for: task(dueInDays: 0), now: now) == .thisWeek)
        #expect(TaskPlanner.bucket(for: task(dueInDays: 7), now: now) == .thisWeek)
        #expect(TaskPlanner.bucket(for: task(dueInDays: 8), now: now) == .thisMonth)
        #expect(TaskPlanner.bucket(for: task(dueInDays: 40), now: now) == .later)
        #expect(TaskPlanner.bucket(for: task(dueInDays: nil), now: now) == .whenever)
        #expect(TaskPlanner.bucket(for: task(dueInDays: 2, done: true), now: now) == .done)
    }

    @Test("A dismissed task leaves the open list")
    func dismissedIsDone() {
        let dismissed = task(dueInDays: 2)
        dismissed.dismissedAt = now
        #expect(TaskPlanner.bucket(for: dismissed, now: now) == .done)
    }

    @Test("Dated tasks sort before undated ones")
    func datedFirst() {
        let undated = task(title: "Someday", dueInDays: nil)
        let dated = task(title: "Soon", dueInDays: 3)
        let sorted = TaskPlanner.sorted([undated, dated], now: now)
        #expect(sorted.first?.title == "Soon")
    }

    @Test("Same-day ties break on the catalog's weight")
    func weightBreaksTies() {
        let light = task(title: "Childcare", dueInDays: 30, weight: 110)
        let heavy = task(title: "Insurance", dueInDays: 30, weight: 1)
        let sorted = TaskPlanner.sorted([light, heavy], now: now)
        #expect(sorted.first?.title == "Insurance")
    }

    @Test("The overview counts what is left and what is past due")
    func overviewCounts() {
        let tasks = [
            task(title: "A", dueInDays: -2, kind: .hard),
            task(title: "B", dueInDays: 5, kind: .hard),
            task(title: "C", dueInDays: 20, kind: .hard),
            task(title: "D", dueInDays: nil),
            task(title: "E", dueInDays: 3, done: true)
        ]
        let overview = TaskPlanner.overview(for: tasks, now: now)
        #expect(overview.openCount == 4)
        #expect(overview.doneCount == 1)
        #expect(overview.overdueCount == 1)
        // The overdue one is behind us, so it is not the *next* deadline.
        #expect(overview.hardDeadlineCount == 2)
        #expect(overview.nextHardDeadlineTitle == "B")
    }

    @Test("A finished plan reports no next hard deadline")
    func noDeadlineWhenDone() {
        let overview = TaskPlanner.overview(
            for: [task(dueInDays: 5, kind: .hard, done: true)],
            now: now
        )
        #expect(overview.nextHardDeadline == nil)
        #expect(overview.progress == 1)
    }

    @Test("Due phrasing reads the way a person would say it")
    func phrasing() {
        #expect(TaskPlanner.duePhrase(for: task(dueInDays: 0, kind: .hard), now: now) == "Due today")
        #expect(TaskPlanner.duePhrase(for: task(dueInDays: 1, kind: .hard), now: now) == "Due tomorrow")
        #expect(TaskPlanner.duePhrase(for: task(dueInDays: 5, kind: .hard), now: now) == "5 days left")
        #expect(TaskPlanner.duePhrase(for: task(dueInDays: -1, kind: .hard), now: now) == "1 day past due")
        #expect(TaskPlanner.duePhrase(for: task(dueInDays: -4, kind: .hard), now: now) == "4 days past due")
    }

    /// The failure this guards against is a screenshot, not a crash: a
    /// suggestion and a legal window both saying "10 days left" in a list a
    /// parent triages in four seconds, separated only by a colour.
    @Test("A suggested date says so in words, not only in colour")
    func suggestionsSayTheyAreSuggestions() {
        let suggested = TaskPlanner.duePhrase(for: task(dueInDays: 10, kind: .recommended), now: now)
        #expect(suggested == "Suggested \u{00B7} 10 days left")
        #expect(TaskPlanner.duePhrase(for: task(dueInDays: 10, kind: .hard), now: now) == "10 days left")
    }

    @Test("An undated hard deadline says the date depends on the plan")
    func undatedHardDeadlineIsHonest() {
        // The newborn account is the real case: the rule applies and there is a
        // date somewhere, but it is not one this app is willing to assert.
        let phrase = TaskPlanner.duePhrase(for: task(dueInDays: nil, kind: .recommended), now: now)
        #expect(phrase == "Date depends on your plan")
    }
}
