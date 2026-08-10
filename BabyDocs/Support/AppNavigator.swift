import Foundation
import SwiftUI

/// Cross-screen navigation intents that arrive from outside the view tree: a
/// deep link, a notification tap, a paywall dismissal.
///
/// One object rather than a pile of `@State` bindings threaded down, because the
/// invitation link can arrive at any point, including while the onboarding
/// wizard is halfway through.
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    enum Tab: Hashable {
        case plan
        case children
        case family
        case settings
    }

    var selectedTab: Tab = .plan

    /// Set by `onOpenURL`. The onboarding flow and the family screen both watch
    /// it, so an invitation opens the right thing whether or not the app has
    /// been set up yet.
    var pendingInviteCode: String?

    /// Set when a gated action was attempted. Presenting the paywall from here
    /// rather than from each call site keeps one sheet, so two taps in quick
    /// succession cannot stack two paywalls.
    var isShowingPaywall = false

    private init() {}

    func requestUpgrade() {
        isShowingPaywall = true
    }
}
