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

    private init() {}

    func requestUpgrade() {
        isShowingPaywall = true
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
