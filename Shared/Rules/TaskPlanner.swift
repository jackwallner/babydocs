import Foundation

/// Pure bucketing and sorting for the plan. No SwiftData, no views, no dates
/// read from `Date()` unless a caller passes one, so every rule in here is a
/// one-line test.
enum TaskPlanner {
    enum Bucket: String, CaseIterable, Sendable {
        case overdue
        case thisWeek
        case thisMonth
        case later
        case whenever
        case done

        var title: String {
            switch self {
            case .overdue: return "Past due"
            case .thisWeek: return "Next 7 days"
            // Not "This month". The window is 31 rolling days from today, so on
            // the 20th it reaches well into the next calendar month, and a
            // parent who reads it as "before the end of the month" has been
            // told something the app did not mean.
            case .thisMonth: return "Next 31 days"
            case .later: return "Later"
            case .whenever: return "No deadline"
            case .done: return "Done"
            }
        }

        var blurb: String {
            switch self {
            case .overdue: return "Check whether the window has actually closed before assuming it has."
            case .thisWeek: return "The ones with a clock on them."
            case .thisMonth: return "Coming up, not urgent yet."
            case .later: return "Scheduled further out."
            case .whenever: return "Worth doing, no date attached."
            case .done: return ""
            }
        }
    }

    /// Groups open tasks into buckets, each already sorted.
    ///
    /// Completed and dismissed tasks are separated out rather than sorted to
    /// the bottom: a plan whose top section is a wall of ticked boxes stops
    /// answering the only question it is asked, which is what is left.
    static func buckets(
        for tasks: [RequirementTask],
        now: Date = Date()
    ) -> [(bucket: Bucket, tasks: [RequirementTask])] {
        var grouped: [Bucket: [RequirementTask]] = [:]

        for task in tasks where task.deletedAt == nil {
            grouped[bucket(for: task, now: now), default: []].append(task)
        }

        return Bucket.allCases.compactMap { bucket in
            guard let items = grouped[bucket], !items.isEmpty else { return nil }
            return (bucket, sorted(items, now: now))
        }
    }

    static func bucket(for task: RequirementTask, now: Date = Date()) -> Bucket {
        if task.isDone || task.isDismissed { return .done }
        guard let days = task.daysRemaining(from: now) else { return .whenever }
        if days < 0 { return .overdue }
        if days <= 7 { return .thisWeek }
        if days <= 31 { return .thisMonth }
        return .later
    }

    /// Soonest deadline first, then the catalog's own weight, then title. The
    /// weight tiebreak is what keeps the two insurance windows above the
    /// nice-to-haves when several tasks land on the same day.
    static func sorted(_ tasks: [RequirementTask], now: Date = Date()) -> [RequirementTask] {
        tasks.sorted { left, right in
            switch (left.dueAt, right.dueAt) {
            case let (l?, r?) where l != r:
                return l < r
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                break
            }
            if left.sortWeight != right.sortWeight { return left.sortWeight < right.sortWeight }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    // MARK: - Overview

    /// The numbers the home screen leads with.
    struct Overview: Equatable, Sendable {
        var openCount = 0
        var doneCount = 0
        var overdueCount = 0
        /// Open tasks with a hard deadline still ahead of them. The one number
        /// worth putting in front of a parent who has thirty seconds.
        var hardDeadlineCount = 0
        var nextHardDeadline: Date?
        var nextHardDeadlineTitle: String?
        /// So the card at the top of the plan can be the task rather than a
        /// description of it. A parent who reads "closes Thursday" wants to open
        /// the thing, and having to find the same title again in the list below
        /// is the app making them do its work twice.
        var nextHardDeadlineID: UUID?

        var totalCount: Int { openCount + doneCount }

        var progress: Double {
            totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount)
        }
    }

    static func overview(for tasks: [RequirementTask], now: Date = Date()) -> Overview {
        var overview = Overview()
        var soonest: RequirementTask?

        for task in tasks where task.deletedAt == nil {
            if task.isDone || task.isDismissed {
                overview.doneCount += 1
                continue
            }
            overview.openCount += 1
            if let days = task.daysRemaining(from: now), days < 0 { overview.overdueCount += 1 }
            guard task.deadlineKind == .hard, let due = task.dueAt, due >= now else { continue }
            overview.hardDeadlineCount += 1
            if let current = soonest, let currentDue = current.dueAt, currentDue <= due { continue }
            soonest = task
        }

        overview.nextHardDeadline = soonest?.dueAt
        overview.nextHardDeadlineTitle = soonest?.title
        overview.nextHardDeadlineID = soonest?.id
        return overview
    }

    // MARK: - Phrasing

    /// How a deadline is said out loud. Kept here rather than in a view so the
    /// list, the detail screen and the notification cannot phrase the same date
    /// three different ways.
    static func duePhrase(for task: RequirementTask, now: Date = Date()) -> String {
        guard let days = task.daysRemaining(from: now) else {
            return task.deadlineKind == .none ? "No deadline" : "Date depends on your plan"
        }
        let phrase: String
        switch days {
        case ..<(-1): phrase = "\(-days) days past due"
        case -1: phrase = "1 day past due"
        case 0: phrase = "Due today"
        case 1: phrase = "Due tomorrow"
        case 2...13: phrase = "\(days) days left"
        default:
            phrase = "Due \(task.dueAt.map { Self.dayPhrase(for: $0, now: now) } ?? "")"
        }
        // **The word, not just the colour.**
        //
        // "10 days left" said the same thing for a legal window and for a
        // suggestion the app made up, and the only difference was an orange pill
        // instead of a red one with an exclamation mark in it. The Plan screen
        // is where a tired parent triages, colour is the first thing to go for
        // anyone who cannot see it or is scanning at 3am, and the detail screen
        // that finally says "Suggested by" is one tap too late.
        return task.deadlineKind == .recommended ? "Suggested \u{00B7} \(phrase)" : phrase
    }

    /// A day, said the same way everywhere.
    ///
    /// The year is dropped inside the current one. The plan showed "Thursday,
    /// Sep 17" in the header card and "Due Sep 17, 2026" in the row underneath
    /// it, for the same task, six points apart: two formats and a year nobody
    /// needed, which is most of why that screen read as assembled rather than
    /// designed. One function now, and both callers go through it.
    static func dayPhrase(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return date.formatted(
            sameYear
                ? .dateTime.month(.abbreviated).day()
                : .dateTime.month(.abbreviated).day().year()
        )
    }

    /// The header card's one line about the next hard deadline: the day it
    /// closes, and how long that is. Same day string as the pill on the row
    /// below, plus the weekday, because a weekday is what a parent checks a
    /// deadline against when they are deciding whether it can wait.
    static func deadlineLine(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let weekday = date.formatted(.dateTime.weekday(.wide))
        let day = dayPhrase(for: date, now: now, calendar: calendar)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        let remaining: String
        switch days {
        case ..<(-1): remaining = "\(-days) days past due"
        case -1: remaining = "1 day past due"
        case 0: remaining = "today"
        case 1: remaining = "tomorrow"
        default: remaining = "\(days) days left"
        }
        return "\(weekday), \(day) \u{00B7} \(remaining)"
    }
}
