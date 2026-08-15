import Foundation
import Testing

@testable import BabyDocs

/// The gate, not the sheet.
///
/// Worth testing because every condition in it is there to stop the app spending
/// its one ask badly, and every one of them is invisible: nothing on screen
/// changes when the gate silently lets a prompt through a fortnight too early, so
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
        #expect(ReviewPromptTracker.canPresentEnjoymentPrompt(now: now) == false)

        ReviewPromptTracker.recordDeadlineMet()
        #expect(ReviewPromptTracker.canPresentEnjoymentPrompt(now: now))

        // A family who installed the app this morning has not used it yet,
        // whatever they have already ticked off.
        ReviewPromptTracker.firstAppOpenDate = Calendar.current.date(byAdding: .day, value: -1, to: now)
        #expect(ReviewPromptTracker.canPresentEnjoymentPrompt(now: now) == false)
        ReviewPromptTracker.firstAppOpenDate = Calendar.current.date(byAdding: .day, value: -10, to: now)

        ReviewPromptTracker.appLaunchCount = 1
        #expect(ReviewPromptTracker.canPresentEnjoymentPrompt(now: now) == false)
    }

    @Test("A passive prompt needs a moment that has not been spent")
    func passivePromptNeedsAPendingMoment() {
        _ = freshTracker()
        makeOtherwiseEligible()
        ReviewPromptTracker.recordDeadlineMet()
        ReviewPromptTracker.recordDeadlineMet()

        #expect(ReviewPromptTracker.shouldShowAfterPositiveMoment(now: now))
        ReviewPromptTracker.consumePendingPositiveMoment()
        #expect(ReviewPromptTracker.shouldShowAfterPositiveMoment(now: now) == false)
        // Still eligible, so Settings can still open it. The passive trigger is
        // what has run out, not the permission.
        #expect(ReviewPromptTracker.canPresentEnjoymentPrompt(now: now))
    }

    @Test("Maybe later comes back in a fortnight, Not now does not come back")
    func cooldownsDifferByAnswer() {
        _ = freshTracker()
        makeOtherwiseEligible()
        ReviewPromptTracker.recordDeadlineMet()
        ReviewPromptTracker.recordDeadlineMet()

        ReviewPromptTracker.markSoftDeferred(now: now)
        let inAWeek = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        let inThreeWeeks = Calendar.current.date(byAdding: .day, value: 21, to: now)!
        #expect(ReviewPromptTracker.passivePromptAllowed(now: inAWeek) == false)
        #expect(ReviewPromptTracker.passivePromptAllowed(now: inThreeWeeks))

        ReviewPromptTracker.markShown(now: now)
        #expect(ReviewPromptTracker.isSoftDeferred == false)
        #expect(ReviewPromptTracker.passivePromptAllowed(now: inThreeWeeks) == false)
        let inFiveMonths = Calendar.current.date(byAdding: .day, value: 150, to: now)!
        #expect(ReviewPromptTracker.passivePromptAllowed(now: inFiveMonths))
    }

    @Test("Answering the question closes it for good")
    func anOutcomeEndsTheFunnel() {
        _ = freshTracker()
        makeOtherwiseEligible()
        ReviewPromptTracker.recordDeadlineMet()
        ReviewPromptTracker.recordDeadlineMet()

        ReviewPromptTracker.markOpenedWriteReview()
        let inTwoYears = Calendar.current.date(byAdding: .day, value: 730, to: now)!
        #expect(ReviewPromptTracker.passivePromptAllowed(now: inTwoYears) == false)
        #expect(ReviewPromptTracker.canPresentEnjoymentPrompt(now: inTwoYears) == false)
    }

    @Test("The feedback draft carries the message and nothing about the family")
    func feedbackMailIsJustTheMessage() throws {
        let url = try #require(ReviewPromptSheet.feedbackMailURL(body: "The CA link 404s"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "jackwallner+babydocs@gmail.com")
        let body = components.queryItems?.first { $0.name == "body" }?.value
        #expect(body == "The CA link 404s")
    }
}
