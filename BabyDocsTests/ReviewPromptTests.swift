import Foundation
import Testing

@testable import BabyDocs

/// The gate, not a prompt.
///
/// There is no prompt of our own left to test: the app calls the system review
/// API and nothing stands in front of it. What is still worth testing is when
/// iOS gets asked, because every condition here exists to stop the app spending
/// its one ask badly, and every one of them is invisible. Nothing on screen
/// changes when the gate silently lets an ask through a fortnight too early, so
/// a regression here would only ever show up as a one-star review.
@MainActor
struct ReviewPromptTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    /// A fresh suite per test. `ReviewPromptTracker` is an enum over
    /// `UserDefaults`, so without this the tests would share state with each
    /// other and with whatever the simulator's installed app had done.
    private func freshTracker() -> UserDefaults {
        let name = "babydocs.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name) ?? .standard
        ReviewPromptTracker.useDefaultsForTesting(suite)
        return suite
    }

    private func task(kind: DeadlineKind, dueInDays: Int?) -> RequirementTask {
        let task = RequirementTask(title: "Task")
        task.deadlineKind = kind
        task.dueAt = dueInDays.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }
        return task
    }

    /// Sets everything except the positive moments, which is what each test then
    /// varies.
    private func makeOtherwiseEligible() {
        ReviewPromptTracker.firstAppOpenDate = Calendar.current.date(byAdding: .day, value: -10, to: now)
        ReviewPromptTracker.appLaunchCount = 5
    }

    @Test("Only a hard deadline, met before it closed, counts")
    func onlyBeatenHardDeadlinesCount() {
        _ = freshTracker()

        ReviewPromptTracker.recordCompletion(of: task(kind: .recommended, dueInDays: 5), now: now)
        ReviewPromptTracker.recordCompletion(of: task(kind: .none, dueInDays: nil), now: now)
        ReviewPromptTracker.recordCompletion(of: task(kind: .hard, dueInDays: nil), now: now)
        // The window had already shut. Claiming credit for this one is how the
        // app asks for a review on the back of a miss.
        ReviewPromptTracker.recordCompletion(of: task(kind: .hard, dueInDays: -1), now: now)
        #expect(ReviewPromptTracker.positiveMomentCount == 0)

        ReviewPromptTracker.recordCompletion(of: task(kind: .hard, dueInDays: 0), now: now)
        ReviewPromptTracker.recordCompletion(of: task(kind: .hard, dueInDays: 3), now: now)
        #expect(ReviewPromptTracker.positiveMomentCount == 2)
    }

    @Test("Every condition has to hold, not just the interesting one")
    func eligibilityNeedsAllConditions() {
        _ = freshTracker()
        makeOtherwiseEligible()

        // Deadlines beaten, but not enough of them.
        ReviewPromptTracker.recordDeadlineMet()
        #expect(ReviewPromptTracker.canRequestReview(now: now) == false)

        ReviewPromptTracker.recordDeadlineMet()
        #expect(ReviewPromptTracker.canRequestReview(now: now))

        // A family who installed the app this morning has not used it yet,
        // whatever they have already ticked off.
        ReviewPromptTracker.firstAppOpenDate = Calendar.current.date(byAdding: .day, value: -1, to: now)
        #expect(ReviewPromptTracker.canRequestReview(now: now) == false)
        ReviewPromptTracker.firstAppOpenDate = Calendar.current.date(byAdding: .day, value: -10, to: now)

        ReviewPromptTracker.appLaunchCount = 1
        #expect(ReviewPromptTracker.canRequestReview(now: now) == false)
    }

    @Test("An ask needs a moment that has not been spent")
    func askNeedsAPendingMoment() {
        _ = freshTracker()
        makeOtherwiseEligible()
        ReviewPromptTracker.recordDeadlineMet()
        ReviewPromptTracker.recordDeadlineMet()

        #expect(ReviewPromptTracker.shouldRequestAfterPositiveMoment(now: now))
        ReviewPromptTracker.consumePendingPositiveMoment()
        #expect(ReviewPromptTracker.shouldRequestAfterPositiveMoment(now: now) == false)
        // The trigger is what ran out, not the permission. A later deadline met
        // inside the same window is still a moment.
        #expect(ReviewPromptTracker.canRequestReview(now: now))
    }

    @Test("One ask, then a cooldown longer than the newborn window")
    func askingStartsALongCooldown() {
        _ = freshTracker()
        makeOtherwiseEligible()
        ReviewPromptTracker.recordDeadlineMet()
        ReviewPromptTracker.recordDeadlineMet()
        #expect(ReviewPromptTracker.shouldRequestAfterPositiveMoment(now: now))

        ReviewPromptTracker.markRequested(now: now)
        // Spent: both the moment and the permission.
        #expect(ReviewPromptTracker.hasPendingPositiveMoment == false)
        #expect(ReviewPromptTracker.canRequestReview(now: now) == false)

        let inThreeWeeks = Calendar.current.date(byAdding: .day, value: 21, to: now)!
        ReviewPromptTracker.recordDeadlineMet()
        #expect(ReviewPromptTracker.shouldRequestAfterPositiveMoment(now: inThreeWeeks) == false)

        let inFiveMonths = Calendar.current.date(byAdding: .day, value: 150, to: now)!
        #expect(ReviewPromptTracker.shouldRequestAfterPositiveMoment(now: inFiveMonths))
    }

    @Test("Screenshot and UI-test runs never ask")
    func suppressedRunsNeverAsk() {
        _ = freshTracker()
        makeOtherwiseEligible()
        ReviewPromptTracker.recordDeadlineMet()
        ReviewPromptTracker.recordDeadlineMet()

        // The real suppression reads launch arguments, which a unit test cannot
        // set. Asserting the wiring instead: eligibility is the AND of the gate
        // and the absence of suppression, so a suppressed run cannot pass.
        #expect(ReviewPromptTracker.canRequestReview(now: now) == !ReviewPromptTracker.isSuppressed)
    }

    @Test("The feedback draft carries the message and nothing about the family")
    func feedbackMailIsJustTheMessage() throws {
        let url = try #require(FeedbackSheet.feedbackMailURL(body: "The CA link 404s"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "jackwallner+babydocs@gmail.com")
        let body = components.queryItems?.first { $0.name == "body" }?.value
        #expect(body == "The CA link 404s")
    }
}
