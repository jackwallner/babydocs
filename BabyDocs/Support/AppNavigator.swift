import Foundation
import SwiftUI

/// Cross-screen navigation intents that arrive from outside the view tree: a
/// deep link, a notification tap, a paywall dismissal.
///
/// One object rather than a pile of `@State` bindings threaded down, because a
/// shared plan link can arrive at any point, including while the intake is
/// halfway through.
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    enum Tab: Hashable {
        case plan
        case children
        case documents
        case plus
        case settings
    }

    var selectedTab: Tab = .plan

    /// Set by `onOpenURL` when the other parent's link is tapped. Held rather
    /// than applied, because the answer to "shall I replace what is already
    /// here" belongs to the person holding the phone.
    var pendingSeed: PlanSeed?

    /// Set when a link arrived but could not be read. Distinguished from no link
    /// at all: silence after tapping a link someone sent you reads as a broken
    /// app, and the honest message is that the link itself did not survive.
    var seedFailed = false

    /// Set when a deadline reminder is tapped. Held rather than acted on
    /// immediately: on a cold launch the notification response arrives before
    /// the store has loaded, so the plan screen consumes this once the row
    /// exists. Cleared by whoever navigates, so a tap is never replayed.
    var pendingTaskID: UUID?

    /// Set when a gated action was attempted. Presenting the paywall from here
    /// rather than from each call site keeps one sheet, so two taps in quick
    /// succession cannot stack two paywalls.
    var isShowingPaywall = false

    /// Whether the first-run intake has been left behind. True until the intake
    /// appears, so a launch with a plan already in the store never opens it.
    private(set) var isIntakeFinished = true

    /// Internal rather than private so a test can build a navigator of its own
    /// instead of sharing the app's.
    init() {}

    func intakeDidAppear() {
        isIntakeFinished = false
    }

    func intakeDidFinish() {
        isIntakeFinished = true
    }

    /// Whether the intake owns the screen.
    ///
    /// An empty store opens it, and it stays open until the intake's own last
    /// page says otherwise, even though the child it created is in the store by
    /// then. That gap is where the plan-is-ready page and the notification
    /// prompt live.
    func isIntakeOpen(activeChildren: Int, archivedChildren: Int) -> Bool {
        (activeChildren == 0 && archivedChildren == 0) || !isIntakeFinished
    }

    /// A shared plan was applied. The Plan tab is where it lands.
    func planWasImported() {
        selectedTab = .plan
    }

    /// The sheet, for a gate somebody has just walked into.
    ///
    /// The Plus tab carries the same pitch, unprompted, for anybody who wants
    /// to go and read it. This is the other direction: a locked control was
    /// tapped, and the answer belongs in front of the tap rather than three
    /// screens away.
    func requestUpgrade() {
        isShowingPaywall = true
    }

    /// Sends somebody to the Plus tab rather than putting a sheet over what
    /// they were reading. Used where the mention is an aside rather than a
    /// refusal.
    func showPlusTab() {
        selectedTab = .plus
    }

    func open(_ url: URL) {
        if let seed = PlanSeed.decode(from: url) {
            pendingSeed = seed
            seedFailed = false
        } else {
            seedFailed = true
        }
    }
}
