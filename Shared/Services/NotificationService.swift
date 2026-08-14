import Foundation
import OSLog
import UIKit
import UserNotifications

/// Notification permission, and nothing else.
///
/// There is no remote push here and there will not be one: every reminder this
/// app sends is scheduled locally by `DeadlineReminderScheduler` from a date it
/// already knows, so there is no server, no device token and no `aps-environment`
/// entitlement to get wrong. That also means reminders keep working on a phone
/// in airplane mode in a records office basement, which is exactly where this
/// app expects to be.
@MainActor
@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let log = Logger(subsystem: "com.jackwallner.babydocs", category: "push")

    private override init() {
        super.init()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus
    }

    func isAuthorized() async -> Bool {
        await refreshStatus()
        return authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// Asked for at the moment it means something (the end of the intake, once
    /// there is a real deadline to be reminded about), never on first launch
    /// where it reads as noise and gets refused permanently.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            return granted
        } catch {
            log.error("Authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Deadline reminders are worth showing while the app is open. There is no
    /// in-app banner that would duplicate them.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A tapped reminder routes to the task it is about.
    ///
    /// The id is only recorded here. Navigation is the plan screen's job,
    /// because on a cold launch this runs before the store has been read and
    /// there is nothing yet to navigate to.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let taskID = DeadlineReminderScheduler.taskID(fromUserInfo: userInfo) else { return }
        await MainActor.run {
            AppNavigator.shared.pendingTaskID = taskID
            AppNavigator.shared.selectedTab = .plan
        }
    }
}

/// Still needed with no push at all: the notification delegate has to be set
/// before launch finishes, and SwiftUI's `.task` runs too late for that.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The notification delegate has to be in place before launch finishes, or
    /// the tap that launched the app is delivered to nobody and the reminder
    /// opens the plan list instead of the task.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            UNUserNotificationCenter.current().delegate = NotificationService.shared
        }
        return true
    }
}
