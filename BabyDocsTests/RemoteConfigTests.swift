import Foundation
import Testing

@testable import BabyDocs

/// The offering-metadata reader and the trial button wording it drives.
struct RemoteConfigTests {
    /// No launch override, so these read only the metadata.
    private let noArgs: [String] = []

    private func arm(_ metadata: [String: Any]?) -> TrialCTA {
        TrialCTA.from(metadata: metadata, arguments: noArgs)
    }

    private let trialPlan = PlanOption(
        id: ProProduct.weekly, title: "Weekly", price: "$4.99", package: nil,
        period: "per week", introOffer: "3 days free"
    )
    private let paidIntroPlan = PlanOption(
        id: ProProduct.weekly, title: "Weekly", price: "$4.99", package: nil,
        period: "per week", introOffer: "$0.99 for the first week"
    )
    private let ineligiblePlan = PlanOption(
        id: ProProduct.weekly, title: "Weekly", price: "$4.99", package: nil,
        period: "per week", introOffer: nil
    )
    private let lifetimePlan = PlanOption(
        id: ProProduct.lifetime, title: "Keep it forever", price: "$59.99", package: nil
    )

    @Test("Missing, non-string and unknown values are the control")
    func fallsBackToControl() {
        #expect(arm(nil) == .threeDay)
        #expect(arm([:]) == .threeDay)
        #expect(arm(["trial_cta": 3]) == .threeDay)
        #expect(arm(["trial_cta": ["my"]]) == .threeDay)
        #expect(arm(["trial_cta": "start_now"]) == .threeDay)
        #expect(arm(["trial_cta": "MY"]) == .threeDay)
    }

    @Test("Each known value is its arm")
    func readsKnownArms() {
        #expect(TrialCTA.metadataKey == "trial_cta")
        #expect(arm(["trial_cta": "three_day"]) == .threeDay)
        #expect(arm(["trial_cta": "my"]) == .my)
        #expect(arm(["trial_cta": "your"]) == .your)
    }

    @Test("A DEBUG launch override pins the arm")
    func launchOverridePins() {
        #if DEBUG
        let pinned = TrialCTA.from(metadata: ["trial_cta": "my"], arguments: ["-babydocs.rc.trial_cta", "your"])
        #expect(pinned == .your)
        #endif
    }

    @Test("The control is the copy that shipped, character for character")
    func controlIsShippedCopy() {
        #expect(TrialCTA.threeDay.buttonTitle(for: trialPlan, on: .onboarding) == "Get started")
        #expect(TrialCTA.threeDay.buttonTitle(for: trialPlan, on: .paywall) == "Start my free trial")
    }

    @Test("Each arm's words on each surface")
    func armTitles() {
        #expect(TrialCTA.my.title(.onboarding) == "Start my free trial")
        #expect(TrialCTA.my.title(.paywall) == "Start my free trial")
        #expect(TrialCTA.your.title(.onboarding) == "Start your free trial")
        #expect(TrialCTA.your.title(.paywall) == "Start your free trial")
    }

    @Test("No arm promises a trial the account cannot take")
    func ineligibleWordingUnchanged() {
        for arm in TrialCTA.allCases {
            for surface in [TrialCTA.Surface.onboarding, .paywall] {
                #expect(arm.buttonTitle(for: ineligiblePlan, on: surface) == "Continue")
                #expect(arm.buttonTitle(for: paidIntroPlan, on: surface) == "Continue")
                #expect(arm.buttonTitle(for: lifetimePlan, on: surface) == "Buy it once")
            }
        }
    }

    @Test("A switch is on by default and off only for \"off\"")
    func switchDefaultsOn() {
        let key = RemoteSwitch.ratingPrompt.rawValue
        #expect(key == "rating_prompt")
        #expect(RemoteConfig.isOn(.ratingPrompt, in: nil, arguments: noArgs))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [:], arguments: noArgs))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [key: "on"], arguments: noArgs))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [key: false], arguments: noArgs))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [key: "OFF"], arguments: noArgs))
        #expect(!RemoteConfig.isOn(.ratingPrompt, in: [key: "off"], arguments: noArgs))
    }
}
