import Foundation

/// The plan read as an order rather than as a set of dates.
///
/// Two different questions get asked of the same twenty-three tasks. "When does this
/// close" is answered by `TaskPlanner`, and every date in that answer belongs to
/// somebody else: a statute, a plan document, a state office. "What should I do
/// this week" is answered here, and it is the app's own answer, because the app
/// is the only party that can see the dependencies at once. A parent cannot know
/// that the passport is really the birth certificate wearing a hat, or that the
/// $1,000 election is the Social Security card wearing one.
///
/// Everything in this file is a pure function of tasks and a date, so the
/// sequencing is testable without a container, and nothing here can write a
/// `dueAt` or make a suggestion look like a legal window.
enum PlanTimeline {
    enum Phase: String, CaseIterable, Sendable {
        case now
        case soon
        case later
        case blocked
        case done

        var title: String {
            switch self {
            case .now: return "Start this week"
            case .soon: return "The week after"
            case .later: return "When things calm down"
            case .blocked: return "Waiting on something else"
            case .done: return "Handled"
            }
        }

        var blurb: String {
            switch self {
            case .now: return "Everything with a door closing on it, and everything that is only slow because somebody else has to post it back."
            case .soon: return "Nothing here is urgent this minute. It is next, so that the week after the birth is not a blank page."
            case .later: return "Real tasks with no clock on them. Left here on purpose so they are not competing with the ones that close."
            case .blocked: return "There is nothing you can do on these today. They open on their own once the thing they wait for arrives."
            case .done: return "Ticked off."
            }
        }
    }

    /// One task, placed, with the reason it sits where it does.
    struct Step: Identifiable, Sendable {
        var id: UUID
        var taskID: UUID
        var title: String
        var phase: Phase
        /// Said in the parent's words, never as a date the app invented. "Once
        /// the birth certificate arrives" is honest; "start on Sep 14" is a
        /// date with nobody's name on it.
        var reason: String
        var isBlocked: Bool
        var isDone: Bool
        var dueAt: Date?
        var deadlineKind: DeadlineKind
    }

    struct Group: Sendable {
        var phase: Phase
        var steps: [Step]
    }

    /// The whole timeline for one family.
    ///
    /// `now` is threaded through rather than read, for the same reason it is in
    /// `TaskPlanner`: a plan that phrases itself differently on the machine that
    /// tests it is not a plan anybody can assert on.
    static func groups(for tasks: [RequirementTask], now: Date = Date()) -> [Group] {
        let live = tasks.filter { $0.deletedAt == nil && !$0.isDismissed }
        let completedKeys = Set(live.filter { $0.isDone }.map(\.catalogKey))
        var byPhase: [Phase: [Step]] = [:]

        for task in live {
            let step = step(for: task, completedKeys: completedKeys, now: now)
            byPhase[step.phase, default: []].append(step)
        }

        return Phase.allCases.compactMap { phase in
            guard let steps = byPhase[phase], !steps.isEmpty else { return nil }
            return Group(phase: phase, steps: steps.sorted(by: order))
        }
    }

    /// Where one task belongs, and why.
    static func step(
        for task: RequirementTask,
        completedKeys: Set<String>,
        now: Date = Date()
    ) -> Step {
        let advice = RequirementCatalog.rule(key: task.catalogKey)?.start ?? .straightAway
        var phase: Phase = .now
        var reason = ""
        var isBlocked = false

        if task.isDone {
            // The strikethrough already says it. A row that reads "Done." under
            // a struck-through title is the app talking to itself.
            phase = .done
            reason = ""
        } else if task.deadlineKind == .hard {
            // A hard window outranks every sequencing opinion in this file. The
            // app's view of what is convenient does not get to reorder a date
            // somebody else set.
            phase = .now
            reason = "A window closes on this one, so it goes first whatever else is happening."
        } else {
            switch advice {
            case .straightAway:
                // **No reason line, deliberately.** The section it lands in
                // already says why everything in it is there, and three rows
                // repeating "somebody else has to post this back to you" word
                // for word turns the one sentence that carries the feature into
                // wallpaper. The reason is printed where it is particular to
                // the task: a window closing, a wait on the certificate, a
                // month that has to pass first.
                phase = task.isPostedAway ? .now : .soon
                reason = ""
            case .afterDays(let days, let because):
                let ready = openingDate(afterDays: days, from: task.child?.birthDate ?? now)
                let daysAway = wholeDays(from: now, to: ready)
                phase = daysAway <= 0 ? .now : (daysAway <= 7 ? .soon : .later)
                reason = because
            case .after(let key, let because):
                if completedKeys.contains(key) {
                    phase = .now
                    reason = "\(because) That has arrived, so this one is open."
                } else {
                    phase = .blocked
                    isBlocked = true
                    reason = because
                }
            }
        }

        return Step(
            id: task.id,
            taskID: task.id,
            title: task.title,
            phase: phase,
            reason: reason,
            isBlocked: isBlocked,
            isDone: task.isDone,
            dueAt: task.dueAt,
            deadlineKind: task.deadlineKind
        )
    }

    /// How many tasks the family could actually pick up today. The one number
    /// worth putting at the top of the timeline, because "twelve tasks" on a
    /// plan where four are blocked is a number that makes somebody feel worse
    /// without telling them anything.
    static func openNowCount(for tasks: [RequirementTask], now: Date = Date()) -> Int {
        groups(for: tasks, now: now)
            .first { $0.phase == .now }?
            .steps.filter { !$0.isDone }.count ?? 0
    }

    private static func openingDate(afterDays days: Int, from birthDate: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: birthDate) ?? birthDate
    }

    private static func wholeDays(from: Date, to: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: from),
            to: calendar.startOfDay(for: to)
        ).day ?? 0
    }

    /// Inside a phase: the things that close first, then the blocked ones, then
    /// alphabetically so the order is stable between launches.
    private static func order(_ left: Step, _ right: Step) -> Bool {
        if left.isDone != right.isDone { return right.isDone }
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
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
}
