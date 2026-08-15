import Foundation

extension Notification.Name {
    /// Posted when a hard deadline is met before it closed. The host may present
    /// the enjoyment funnel after a short delay, if eligibility also allows it.
    static let babyDocsDeadlineMet = Notification.Name("com.jackwallner.babydocs.deadlineMet")
}

/// How the user last resolved the review / feedback funnel. Set once and never
/// cleared: someone who has already written a review, or already told us what is
/// wrong, has answered the question.
enum ReviewPromptOutcome: String, Sendable {
    case openedWriteReview
    case submittedFeedback
}

/// Eligibility for the review funnel, persisted in `UserDefaults`.
///
/// The gate is deliberately harder here than in most of the fleet, because the
/// window is shorter. A family uses this app intensely for six to thirteen weeks
/// and then genuinely stops, so there is time for roughly one ask. Spending it on
/// a parent who opened the app twice and ticked nothing wastes the only one there
/// is, and asking during the fortnight where a birth certificate has not arrived
/// buys a one-star review.
///
/// The positive moment is therefore narrow: a task with a **hard** deadline,
/// marked done **before** that deadline closed. That is the app doing the thing
/// it claims to do, observed rather than assumed, and it is the only moment where
/// "is this helping?" has an honest answer.
@MainActor
enum ReviewPromptTracker {
    private static var defaults = UserDefaults.standard

    /// Tests point this at a scratch suite. Without it a test run would read and
    /// write the same keys the simulator's own installed app uses, so the gate
    /// would pass or fail depending on what a previous run happened to leave.
    static func useDefaultsForTesting(_ suite: UserDefaults) {
        defaults = suite
    }

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let outcomeKey = "reviewPrompt.outcome"
    private static let positiveMomentCountKey = "reviewPrompt.positiveMomentCount"
    private static let pendingPositiveMomentKey = "reviewPrompt.pendingPositiveMoment"
    private static let softDeferKey = "reviewPrompt.softDefer"

    /// Cold starts before the funnel is considered at all.
    static let minimumLaunchCount = 3
    /// Days since first open. A newborn week is long; three days is not.
    static let minimumDaysSinceFirstOpen = 3
    /// Deadlines beaten. Two, because one could be luck and the app takes no
    /// credit for a task the family had already handled before it appeared.
    static let minimumPositiveMoments = 2
    /// After "Not now". Longer than the app's own useful life on purpose: a no
    /// during the newborn window is a no for the newborn window.
    static let cooldownDays = 120
    /// After "Maybe later" on the pitch itself. `requestReview()` frequently
    /// shows nothing at all, so a full jail would spend an ask that was never
    /// actually made. Shorter than the fleet's 30 because the whole window is 90.
    static let softDeferCooldownDays = 14

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: launchCountKey), 0) }
        set { defaults.set(newValue, forKey: launchCountKey) }
    }

    static var firstAppOpenDate: Date? {
        get { defaults.object(forKey: firstOpenKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: firstOpenKey)
            } else {
                defaults.removeObject(forKey: firstOpenKey)
            }
        }
    }

    static var lastShownDate: Date? {
        get { defaults.object(forKey: lastShownKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: lastShownKey)
            } else {
                defaults.removeObject(forKey: lastShownKey)
            }
        }
    }

    static var outcome: ReviewPromptOutcome? {
        get {
            guard let raw = defaults.string(forKey: outcomeKey) else { return nil }
            return ReviewPromptOutcome(rawValue: raw)
        }
        set {
            if let value = newValue {
                defaults.set(value.rawValue, forKey: outcomeKey)
            } else {
                defaults.removeObject(forKey: outcomeKey)
            }
        }
    }

    static var positiveMomentCount: Int {
        get { max(defaults.integer(forKey: positiveMomentCountKey), 0) }
        set { defaults.set(newValue, forKey: positiveMomentCountKey) }
    }

    /// Set when a positive moment fires, cleared once a prompt consumes it.
    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: pendingPositiveMomentKey) }
        set { defaults.set(newValue, forKey: pendingPositiveMomentKey) }
    }

    /// Screenshot and UI-test runs must never draw the sheet: it would cover the
    /// screen being captured, and a store screenshot of a review prompt is both
    /// useless and against the spirit of the guideline.
    static var isSuppressed: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-uitest-seed") || arguments.contains("-uitest-wipe-store")
    }

    static func recordAppLaunch(now: Date = .now) {
        if firstAppOpenDate == nil {
            firstAppOpenDate = now
        }
        appLaunchCount += 1
    }

    /// A hard deadline met before it closed. See the type comment for why this
    /// and nothing else counts.
    static func recordDeadlineMet() {
        positiveMomentCount += 1
        hasPendingPositiveMoment = true
        NotificationCenter.default.post(name: .babyDocsDeadlineMet, object: nil)
    }

    /// Called from every place a task can be ticked. Filters here rather than at
    /// the call sites so the two of them cannot drift apart on what counts.
    ///
    /// A task with no date, or one ticked after its date had already passed, is
    /// not a win the app can claim, and asking for a review on the back of a
    /// missed window is how an app earns one star.
    static func recordCompletion(of task: RequirementTask, now: Date = .now) {
        guard task.deadlineKind == .hard else { return }
        guard let days = task.daysRemaining(from: now), days >= 0 else { return }
        recordDeadlineMet()
    }

    static func consumePendingPositiveMoment() {
        hasPendingPositiveMoment = false
    }

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome == nil else { return false }
        guard let last = lastShownDate else { return true }
        let days = defaults.bool(forKey: softDeferKey) ? softDeferCooldownDays : cooldownDays
        return now.timeIntervalSince(last) >= TimeInterval(days) * 86_400
    }

    /// Base eligibility, shared by the passive prompt and the Settings entry.
    static func canPresentEnjoymentPrompt(now: Date = .now) -> Bool {
        guard !isSuppressed else { return false }
        guard passivePromptAllowed(now: now) else { return false }
        guard appLaunchCount >= minimumLaunchCount else { return false }
        guard positiveMomentCount >= minimumPositiveMoments else { return false }
        guard let first = firstAppOpenDate else { return false }
        return now.timeIntervalSince(first) >= TimeInterval(minimumDaysSinceFirstOpen) * 86_400
    }

    static func shouldShowAfterPositiveMoment(now: Date = .now) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canPresentEnjoymentPrompt(now: now)
    }

    static func markShown(now: Date = .now) {
        lastShownDate = now
        defaults.set(false, forKey: softDeferKey)
        consumePendingPositiveMoment()
    }

    /// True after "Maybe later" until the next hard `markShown` or outcome. The
    /// host must not call `markShown()` on dismiss while this is set, or the
    /// short cooldown is replaced by the long one.
    static var isSoftDeferred: Bool {
        defaults.bool(forKey: softDeferKey)
    }

    static func markSoftDeferred(now: Date = .now) {
        lastShownDate = now
        defaults.set(true, forKey: softDeferKey)
        consumePendingPositiveMoment()
    }

    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    static func markFeedbackSubmitted() {
        outcome = .submittedFeedback
        markShown()
    }
}

/// The App Store record this app is asking about.
enum AppStoreReviewLinks {
    static let appID = "6799785786"

    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!
    }
}
