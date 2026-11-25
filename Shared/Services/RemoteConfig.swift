import Foundation
@preconcurrency import RevenueCat

/// What RevenueCat can change without a release, read from the current
/// offering's metadata, so a running Experiment's variant is what is read.
/// Every variant ships in the binary, and a missing, non-string or unknown
/// value is the control, which is exactly what 1.1.6 shipped. Keys that a
/// switch reads must be set the same on every offering, or an Experiment arm
/// would flip them as a side effect.
///
/// DEBUG builds can pin any key for captures: `-babydocs.rc.<key> <value>`.
enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string,
    /// or not one of the shipped variants.
    static func value<T: RawRepresentable>(
        _ key: String,
        in metadata: [String: Any]?,
        default fallback: T,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> T where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key, arguments: arguments).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    /// On unless the metadata says "off".
    static func isOn(
        _ remoteSwitch: RemoteSwitch,
        in metadata: [String: Any]?,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue, arguments: arguments) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-babydocs.rc.\(key)"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
    #endif
}

/// The trial button's wording. Every surface here is sentence case.
///
/// The control is what shipped: "Get started" in the intake, where the trial
/// is the way forward, and "Start my free trial" on the sheet and the tab. So
/// on the paywall `my` reads the same as the control; the test that can move
/// is the intake's.
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control, named for the 3-day trial it introduces.
    case threeDay = "three_day"
    case my
    case your

    enum Surface: Sendable {
        /// The last page of the intake.
        case onboarding
        /// The paywall sheet and the Plus tab.
        case paywall
    }

    static func from(metadata: [String: Any]?, arguments: [String] = ProcessInfo.processInfo.arguments) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .threeDay, arguments: arguments)
    }

    /// The purchase button's words for a plan. Only a plan carrying a free
    /// trial this account can take gets trial wording; anything else keeps the
    /// words it always had, so no button promises a trial that is not there
    /// (3.1.2).
    func buttonTitle(for plan: PlanOption, on surface: Surface) -> String {
        if plan.offersFreeTrial { return title(surface) }
        return plan.isLifetime ? "Buy it once" : "Continue"
    }

    func title(_ surface: Surface) -> String {
        switch (self, surface) {
        case (.threeDay, .onboarding): return "Get started"
        case (.threeDay, .paywall): return "Start my free trial"
        case (.my, _): return "Start my free trial"
        case (.your, _): return "Start your free trial"
        }
    }
}

/// Remote off switches, for what is worth pausing without a release.
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// The automatic system rating prompt after a deadline is met.
    case ratingPrompt = "rating_prompt"
}

extension StoreService {
    private var remoteMetadata: [String: Any]? { offerings?.current?.metadata }

    var trialCTAArm: TrialCTA { TrialCTA.from(metadata: remoteMetadata) }

    func isOn(_ remoteSwitch: RemoteSwitch) -> Bool {
        RemoteConfig.isOn(remoteSwitch, in: remoteMetadata)
    }

    /// Tags the customer with the arm they saw, so a wording test can be read
    /// by attribute as well as by Experiment.
    func recordTrialCTAShown() {
        recordRemoteVariant(TrialCTA.metadataKey, trialCTAArm.rawValue)
    }
}
