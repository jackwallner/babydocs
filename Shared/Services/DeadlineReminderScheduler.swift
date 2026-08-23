import Foundation
import OSLog
import SwiftData
import UserNotifications

/// Local notifications for the deadlines that actually close.
///
/// Local, not push, and that is the point: the two dates this app exists for
/// (the 30-day job-based enrollment window and the 60-day Marketplace one) are
/// known the moment the birth date is entered, so they can be scheduled once and
/// then survive a dead server, an expired session and a phone that has been in
/// airplane mode for a fortnight.
///
/// Four rules keep the notifications from becoming noise, which is the failure
/// mode that gets them switched off:
///
/// 1. The two `hard` deadlines are scheduled for everybody, always, free. They
///    are the only two dates in this app where missing it costs a family a year
///    of coverage, and a reminder for those behind a paywall would make the app
///    the cause of the miss.
/// 2. Everything else is opt-in and comes with Plus: the suggested dates, a
///    weekly digest, and a reminder a parent set themselves. None of them fires
///    unless somebody asked for it, because a suggestion that arrives at 9am
///    unbidden is what teaches someone to disable the whole category, and then
///    they miss rule 1.
/// 3. At most `maxScheduled` requests, hard deadlines claimed first. iOS
///    silently drops everything past 64 pending local notifications, and the
///    ones it drops are not the ones you would choose.
/// 4. Rescheduled wholesale on every change. Cancelling and re-adding is the
///    only version of this that cannot leave a reminder behind for a task that
///    was completed or a date that moved.
@MainActor
enum DeadlineReminderScheduler {
    /// Well inside the platform's 64-request limit, with room for anything else
    /// the app might schedule later.
    static let maxScheduled = 24

    /// How many days before a deadline to warn, in the order they fire. Seven
    /// days is enough to act on a form that needs a document you do not have;
    /// one day is the last honest chance.
    static let leadDays = [7, 1]

    /// One warning for a suggested date, not two. These are the app's own
    /// opinions about timing, so they get a quieter voice than a statute.
    static let suggestedLeadDays = [3]

    /// How many Sundays ahead to lay down a digest. Four weeks of a window that
    /// is six to thirteen weeks long, rescheduled on every launch, so it stays
    /// full without ever hoarding requests.
    static let digestWeeks = 4

    /// Every request this app owns starts with one of these, and `cancelAll`
    /// clears exactly them. A notification left behind for a task that was
    /// finished is worse than one that never fired.
    private static let identifierPrefix = "deadline."
    private static let suggestedPrefix = "suggested."
    private static let customPrefix = "custom."
    private static let digestPrefix = "digest."
    private static let ownedPrefixes = [identifierPrefix, suggestedPrefix, customPrefix, digestPrefix]

    private static func isOurs(_ identifier: String) -> Bool {
        ownedPrefixes.contains { identifier.hasPrefix($0) }
    }

    private static let log = Logger(subsystem: "com.jackwallner.babydocs", category: "reminders")
    private static var activeReschedule: Task<Void, Never>?

    /// What to schedule, as a plain value. Keeps the scheduling rule testable
    /// without a notification centre or a SwiftData store.
    struct Plan: Equatable, Sendable {
        var identifier: String
        var title: String
        var body: String
        var fireAt: Date
        /// Carried into the notification payload so a tap opens the task rather
        /// than the app. A reminder that costs a parent the tap and then makes
        /// them find the row themselves has spent the attention it asked for.
        /// Nil on the weekly digest, which is about the week rather than about
        /// one row.
        var taskID: UUID?
        /// Whether this one survives a lapse, an empty wallet and every
        /// preference switch in the app.
        var isHardDeadline = false
    }

    /// What the family is entitled to and has asked for. Passed in rather than
    /// read, so the whole scheduling rule stays a pure function of its inputs.
    struct Options: Equatable, Sendable {
        var suggestedDates = false
        var weeklyDigest = false
        var customReminders = false

        /// Free. The two dates that close, and nothing else.
        static let hardDeadlinesOnly = Options()

        @MainActor
        static var current: Options {
            let isPro = StoreService.shared.isPro
            let prefs = ReminderPreferences.shared
            return Options(
                suggestedDates: isPro && prefs.suggestedDateReminders,
                weeklyDigest: isPro && prefs.weeklyDigest,
                customReminders: isPro
            )
        }
    }

    /// Key in `UNNotificationContent.userInfo`.
    nonisolated static let taskRouteKey = "babydocs.taskID"

    /// The route a tapped notification asks for, or nil if it is not one of
    /// ours. Nonisolated because the notification delegate callback is.
    nonisolated static func taskID(fromUserInfo userInfo: [AnyHashable: Any]) -> UUID? {
        guard let raw = userInfo[taskRouteKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    /// The pure half. Given the open tasks, decide exactly what should be
    /// pending.
    ///
    /// The budget is spent hard deadlines first. Sorting everything by date and
    /// taking the first two dozen looks fair and is not: a fortnight of
    /// suggestions and digests can push the 60-day Marketplace warning off the
    /// end of the queue, and the parent finds out in March.
    static func plans(
        for tasks: [RequirementTask],
        now: Date = Date(),
        options: Options = .hardDeadlinesOnly,
        calendar: Calendar = .current
    ) -> [Plan] {
        let live = tasks.filter { $0.isOpen && $0.deletedAt == nil }
        var hard: [Plan] = []
        var optional: [Plan] = []

        for task in live {
            guard let dueAt = task.dueAt else { continue }

            switch task.deadlineKind {
            case .hard:
                for lead in leadDays {
                    guard let fireAt = morning(daysBefore: lead, of: dueAt, calendar: calendar),
                          fireAt > now
                    else { continue }
                    hard.append(Plan(
                        identifier: "\(identifierPrefix)\(task.id.uuidString).\(lead)",
                        title: lead == 1 ? "Last day tomorrow" : "\(lead) days left",
                        body: "A hard enrollment window closes soon. Open Baby Docs for the task and official details.",
                        fireAt: fireAt,
                        taskID: task.id,
                        isHardDeadline: true
                    ))
                }
            case .recommended where options.suggestedDates:
                for lead in suggestedLeadDays {
                    guard let fireAt = morning(daysBefore: lead, of: dueAt, calendar: calendar),
                          fireAt > now
                    else { continue }
                    optional.append(Plan(
                        identifier: "\(suggestedPrefix)\(task.id.uuidString).\(lead)",
                        // Named as a suggestion in the notification itself. The
                        // whole point of keeping these separate from the two
                        // real windows is lost if they arrive looking the same.
                        title: "Suggested this week",
                        body: "Baby Docs has a suggested task for this week. It is not a legal deadline. Open the app for details.",
                        fireAt: fireAt,
                        taskID: task.id
                    ))
                }
            default:
                break
            }
        }

        if options.customReminders {
            for task in live {
                guard let asked = task.customReminderAt,
                      let fireAt = morning(of: asked, calendar: calendar),
                      fireAt > now
                else { continue }
                optional.append(Plan(
                    identifier: "\(customPrefix)\(task.id.uuidString)",
                    title: "You asked to be reminded",
                    body: "Open Baby Docs to see the task you asked about.",
                    fireAt: fireAt,
                    taskID: task.id
                ))
            }
        }

        if options.weeklyDigest {
            optional.append(contentsOf: digests(for: live, now: now, calendar: calendar))
        }

        // Hard deadlines take what they need, soonest first, and whatever is
        // left is offered to the rest. The platform limit still binds: it is
        // the platform's, and it drops the overflow silently.
        let keptHard = hard.sorted { $0.fireAt < $1.fireAt }.prefix(maxScheduled)
        let budget = max(0, maxScheduled - keptHard.count)
        let keptOptional = optional.sorted { $0.fireAt < $1.fireAt }.prefix(budget)
        return (keptHard + keptOptional).sorted { $0.fireAt < $1.fireAt }
    }

    /// One message on a Sunday morning, and none at all on a quiet week.
    ///
    /// A digest that fires every Sunday to say "nothing this week" is the purest
    /// form of the noise this app refuses: it costs attention and returns
    /// nothing, every week, until it is switched off along with everything else.
    static func digests(
        for tasks: [RequirementTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Plan] {
        var plans: [Plan] = []
        var cursor = now

        for _ in 0..<digestWeeks {
            guard let sunday = nextSundayMorning(after: cursor, calendar: calendar) else { break }
            cursor = sunday
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: sunday) else { break }

            let due = tasks.filter { task in
                guard task.isOpen, let dueAt = task.dueAt else { return false }
                return dueAt >= sunday && dueAt < weekEnd
            }
            guard !due.isEmpty else { continue }

            plans.append(Plan(
                identifier: "\(digestPrefix)\(Int(sunday.timeIntervalSince1970))",
                title: "This week's paperwork",
                body: digestBody(for: due),
                fireAt: sunday,
                taskID: nil
            ))
        }

        return plans
    }

    /// The date-only picker cannot express that today's 9am has already gone.
    /// Keep the invalid choice out of the UI rather than saving a reminder that
    /// the scheduler must silently discard.
    static func minimumCustomReminderDate(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let todayMorning = morning(of: today, calendar: calendar), todayMorning <= now else {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// What one Sunday message says.
    ///
    /// It says how much is waiting and whether any of it is a real window. It
    /// deliberately does not repeat task titles, names or household text on a
    /// lock screen.
    static func digestBody(for due: [RequirementTask]) -> String {
        let hardCount = due.filter { $0.deadlineKind == .hard }.count

        if due.count == 1 {
            return hardCount > 0
                ? "One real enrollment window closes this week. Open Baby Docs for details."
                : "One suggested task reaches its date this week. It is not a legal deadline. Open Baby Docs for details."
        }

        if hardCount == 0 {
            return "\(due.count) things reach their date this week. None of them is a legal deadline."
        }
        let verb = hardCount == 1 ? "is a real window" : "are real windows"
        return "\(due.count) things reach their date this week. \(hardCount) of them \(verb) closing."
    }

    private static func morning(
        daysBefore lead: Int,
        of date: Date,
        calendar: Calendar
    ) -> Date? {
        guard let shifted = calendar.date(byAdding: .day, value: -lead, to: date) else { return nil }
        return morning(of: shifted, calendar: calendar)
    }

    private static func morning(of date: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
    }

    private static func nextSundayMorning(after date: Date, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.weekday = 1
        components.hour = 9
        components.minute = 0
        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime
        )
    }

    /// The effectful half. Clears every reminder this app owns and lays down the
    /// current set. Leaves other categories of notification alone.
    static func reschedule(for tasks: [RequirementTask], now: Date = Date()) async {
        activeReschedule?.cancel()
        await activeReschedule?.value
        let work = Task { @MainActor in
            await performReschedule(for: tasks, now: now)
        }
        activeReschedule = work
        await work.value
    }

    private static func performReschedule(for tasks: [RequirementTask], now: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            await cancelAll()
            return
        }

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter(isOurs)
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for plan in plans(for: tasks, now: now, options: Options.current) {
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            if let taskID = plan.taskID {
                content.userInfo = [taskRouteKey: taskID.uuidString]
            }

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: plan.fireAt
            )
            let request = UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                log.error("Could not schedule reminder: \(error.localizedDescription, privacy: .private(mask: .hash))")
            }
        }
    }

    /// Rebuilds reminders from the live children in one store pass. Keeping
    /// this here gives every write path the same source of truth.
    static func reschedule(in context: ModelContext, now: Date = Date()) async {
        do {
            let children = try context.fetch(FetchDescriptor<Child>())
                .filter { $0.deletedAt == nil }
            await reschedule(for: children.flatMap(\.liveTasks), now: now)
        } catch {
            log.error("Could not read children while rescheduling: \(error.localizedDescription, privacy: .private(mask: .hash))")
            await cancelAll()
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter(isOurs)
        )
    }
}
