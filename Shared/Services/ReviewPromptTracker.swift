import Foundation

extension Notification.Name {
    /// Posted when a hard deadline is met before it closed. The host may call the
    /// system review API after a short delay, if eligibility also allows it.
    static let babyDocsDeadlineMet = Notification.Name("com.jackwallner.babydocs.deadlineMet")
}

/// Eligibility for the system review request, persisted in `UserDefaults`.
///
/// There is no custom prompt in front of this, and there must never be one
/// again. App Review requires the system API and disallows an in-app question
/// that decides who is allowed to reach it: filtering by "is this helping?"
/// sends only happy people to the store, which is exactly what the rule exists
/// to stop. So the only thing this type decides is *when* iOS is asked, never
/// *who* gets asked.
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
/// it claims to do, observed rather than assumed.
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
    private static let positiveMomentCountKey = "reviewPrompt.positiveMomentCount"
    private static let pendingPositiveMomentKey = "reviewPrompt.pendingPositiveMoment"

    /// Cold starts before the request is considered at all.
    static let minimumLaunchCount = 3
    /// Days since first open. A newborn week is long; three days is not.
    static let minimumDaysSinceFirstOpen = 3
    /// Deadlines beaten. Two, because one could be luck and the app takes no
    /// credit for a task the family had already handled before it appeared.
    static let minimumPositiveMoments = 2
    /// After an ask. Longer than the app's own useful life on purpose: iOS
    /// throttles `requestReview()` to three a year and shows nothing at all much
    /// of the time, and a second ask inside the newborn window would land during
    /// the fortnight a birth certificate has not arrived.
    static let cooldownDays = 120

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

    static var lastRequestedDate: Date? {
        get { defaults.object(forKey: lastShownKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: lastShownKey)
            } else {
                defaults.removeObject(forKey: lastShownKey)
            }
        }
    }

    static var positiveMomentCount: Int {
        get { max(defaults.integer(forKey: positiveMomentCountKey), 0) }
        set { defaults.set(newValue, forKey: positiveMomentCountKey) }
    }

    /// Set when a positive moment fires, cleared once an ask consumes it.
    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: pendingPositiveMomentKey) }
        set { defaults.set(newValue, forKey: pendingPositiveMomentKey) }
    }

    /// Screenshot and UI-test runs must never ask: the system sheet would cover
    /// the screen being captured, and a store screenshot of a rating prompt is
    /// both useless and against the spirit of the guideline.
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

    static func cooldownElapsed(now: Date = .now) -> Bool {
        guard let last = lastRequestedDate else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(cooldownDays) * 86_400
    }

    /// Everything except the pending moment, so the reason a launch is not
    /// eligible stays separable from the reason a tick is not.
    static func canRequestReview(now: Date = .now) -> Bool {
        guard !isSuppressed else { return false }
        guard cooldownElapsed(now: now) else { return false }
        guard appLaunchCount >= minimumLaunchCount else { return false }
        guard positiveMomentCount >= minimumPositiveMoments else { return false }
        guard let first = firstAppOpenDate else { return false }
        return now.timeIntervalSince(first) >= TimeInterval(minimumDaysSinceFirstOpen) * 86_400
    }

    static func shouldRequestAfterPositiveMoment(now: Date = .now) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canRequestReview(now: now)
    }

    /// Called immediately before `requestReview()`. iOS may well show nothing,
    /// and there is no callback that says which happened, so the ask is counted
    /// as spent either way rather than retried until something appears.
    static func markRequested(now: Date = .now) {
        lastRequestedDate = now
        consumePendingPositiveMoment()
    }
}
