import Foundation
import OSLog
import UserNotifications

/// Local notifications for the deadlines that actually close.
///
/// Local, not push, and that is the point: the two dates this app exists for
/// (the 30-day job-based enrollment window and the 60-day Marketplace one) are
/// known the moment the birth date is entered, so they can be scheduled once and
/// then survive a dead server, an expired session and a phone that has been in
/// airplane mode for a fortnight.
///
/// Three rules keep the notifications from becoming noise, which is the failure
/// mode that gets them switched off:
///
/// 1. Only `hard` deadlines are scheduled. A suggestion that fires at 9am is
///    what teaches someone to disable the whole category.
/// 2. At most `maxScheduled` requests, soonest first. iOS silently drops
///    everything past 64 pending local notifications, and the ones it drops are
///    not the ones you would choose.
/// 3. Rescheduled wholesale on every change. Cancelling and re-adding is the
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

    private static let identifierPrefix = "deadline."
    private static let log = Logger(subsystem: "com.jackwallner.babydocs", category: "reminders")

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
        var taskID: UUID
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
    static func plans(
        for tasks: [RequirementTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Plan] {
        var plans: [Plan] = []

        for task in tasks where task.deadlineKind == .hard && task.isOpen && task.deletedAt == nil {
            guard let dueAt = task.dueAt else { continue }
            let childName = task.child?.displayName ?? "your baby"

            for lead in leadDays {
                guard let fireDate = calendar.date(byAdding: .day, value: -lead, to: dueAt),
                      let fireAt = calendar.date(
                        bySettingHour: 9, minute: 0, second: 0, of: fireDate
                      ),
                      fireAt > now
                else { continue }

                plans.append(Plan(
                    identifier: "\(identifierPrefix)\(task.id.uuidString).\(lead)",
                    title: lead == 1 ? "Last day tomorrow" : "\(lead) days left",
                    body: "\(task.title) for \(childName). \(task.deadlineBasis)",
                    fireAt: fireAt,
                    taskID: task.id
                ))
            }
        }

        return Array(plans.sorted { $0.fireAt < $1.fireAt }.prefix(maxScheduled))
    }

    /// The effectful half. Clears every reminder this app owns and lays down the
    /// current set. Leaves other categories of notification alone.
    static func reschedule(for tasks: [RequirementTask], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for plan in plans(for: tasks, now: now) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = [taskRouteKey: plan.taskID.uuidString]

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
                log.error("Could not schedule \(plan.identifier): \(error.localizedDescription)")
            }
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        )
    }
}
