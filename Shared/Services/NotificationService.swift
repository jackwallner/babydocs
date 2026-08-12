import Foundation
import OSLog
import UIKit
import UserNotifications

/// Notification permission, the APNs token, and nothing else.
///
/// The token is stored on `profiles.apns_token` and read only by server-side
/// functions running as the service role. No client can read another member's
/// token.
@MainActor
@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Set when APNs refuses to issue a token. Observable rather than only an
    /// OSLog line, because the failure is otherwise perfectly silent: a parent
    /// turns on deadline reminders, is told nothing, and simply never hears
    /// about the 30-day insurance window. The commonest cause is a build with
    /// no `aps-environment` entitlement, where this fails every single time.
    private(set) var remoteRegistrationFailed = false

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
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted
        } catch {
            log.error("Authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    func registerIfAuthorized() async {
        guard await isAuthorized() else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func noteRemoteRegistrationFailed() { remoteRegistrationFailed = true }

    func store(deviceToken: Data) async {
        remoteRegistrationFailed = false
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard SupabaseConfig.isConfigured, let userID = AuthService.shared.userID else { return }
        do {
            try await AuthService.shared.client
                .from("profiles")
                .update(["apns_token": token])
                .eq("id", value: userID)
                .execute()
            log.info("APNs token stored")
        } catch {
            // Not fatal and not worth a user-visible error: the next launch
            // registers again.
            log.notice("Could not store the APNs token: \(error.localizedDescription)")
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

/// APNs hands the device token to the app delegate and nowhere else, so SwiftUI
/// apps still need one.
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

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await NotificationService.shared.store(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger(subsystem: "com.jackwallner.babydocs", category: "push")
            .notice("Remote notification registration failed: \(error.localizedDescription)")
        Task { @MainActor in NotificationService.shared.noteRemoteRegistrationFailed() }
    }
}
