import XCTest

/// Drives the app through the screens worth looking at and writes each one to
/// the simulator's `/tmp`, where a script (or a person) can pick it up.
///
/// A UI test rather than `simctl io screenshot` because the screens that matter
/// are two taps in, and because a screenshot is only proof if the state behind
/// it came from a real reconciliation pass rather than a hand-built fixture: if
/// a rule is wrong, the picture has to be wrong too.
@MainActor
final class ScreenshotUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testCaptureTheMainScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))
        capture(name: "01-plan")

        // The detail screen is the product: why it applies, the deadline and its
        // basis, the documents, the official link, the source.
        //
        // Tapped by title, and deliberately not the insurance task: that one is
        // the next hard deadline, so it is shown twice (once in the card at the
        // top, once in its own row) and a label query finds both and refuses to
        // tap either.
        let title = "Order certified copies of the birth certificate"
        let row = app.staticTexts[title]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // The deadline basis is the load-bearing sentence on this screen, so it
        // is what proves the push actually happened rather than the nav bar,
        // which exists either way.
        XCTAssertTrue(
            app.staticTexts["Timing"].waitForExistence(timeout: 5),
            "Tapping a task row did not open its detail screen"
        )
        capture(name: "02-task-detail")

        // The document checklist sits below the fold on the taller tasks.
        app.swipeUp()
        capture(name: "03-task-documents")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Children"].tap()
        XCTAssertTrue(app.navigationBars["Children"].waitForExistence(timeout: 5))
        capture(name: "04-children")

        // The paywall, reached the way a free user actually reaches it. Also the
        // only proof that the price, the billing period and the renewal
        // disclosure all render together: a subscription sold without them is a
        // rejection at review and a refund request afterwards.
        app.buttons["Add another child"].tap()
        XCTAssertTrue(app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 10))
        capture(name: "05-paywall")
        app.buttons["Close"].tap()

        // Where a parent goes when someone is waiting at a counter: what is
        // still to find, gathered across every task, and the copies they keep.
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.navigationBars["Documents"].waitForExistence(timeout: 5))
        capture(name: "06-documents")

        // The other half of the same tab. The two are behind a switch rather
        // than stacked down one list, so both halves have to be looked at: a
        // checklist row and a photograph are different nouns and used to sit in
        // the same column looking like the same thing.
        app.buttons["Photos"].firstMatch.tap()
        capture(name: "06b-documents-photos")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture(name: "07-settings")
    }

    func testCaptureTheIntake() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store"]
        app.launch()

        XCTAssertTrue(app.staticTexts["The paperwork, in order"].waitForExistence(timeout: 15))
        capture(name: "00-welcome")

        // One of the four explained pages, which is the change that matters most
        // in the intake: a toggle that says "We want the Trump Account
        // contribution" asks someone to decide using knowledge nobody gave them.
        // Reached rather than constructed, so the picture is proof the flow
        // actually arrives here.
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.navigationBars["Your baby"].waitForExistence(timeout: 5))
        // Captured before anything is answered, because that is the state the
        // required marks exist for: the first screen a parent sees has to say
        // which answers the plan cannot be built without.
        capture(name: "01-baby")
        choose(state: "California", labelled: "State of birth", in: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Your household"].waitForExistence(timeout: 5))
        capture(name: "02-household")
        choose(state: "California", labelled: "State you live in", in: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Coverage"].waitForExistence(timeout: 5))
        capture(name: "03-coverage")
        app.buttons["Through a job"].firstMatch.tap()
        // The plan questions only exist once the answer is "through a job", and
        // they are what make the hardest task in the app name a plan and a
        // person instead of "the job-based health plan".
        capture(name: "04-coverage-employer")
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Leave"].waitForExistence(timeout: 5))
        capture(name: "05-leave")
        app.buttons["Both parents"].firstMatch.tap()
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Newborn account"].waitForExistence(timeout: 5))
        capture(name: "06-explained-choice")
    }

    /// A `Picker` row in a SwiftUI `Form` is a cell containing the label, not a
    /// tappable static text. Querying the label directly finds an element that
    /// exists and is not hittable, which fails in a way that reads like the
    /// screen is wrong rather than the query.
    private func choose(state: String, labelled label: String, in app: XCUIApplication) {
        let row = app.cells.containing(.staticText, identifier: label).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No picker row labelled \(label)")
        row.tap()

        let option = app.buttons[state].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "\(state) never appeared in the picker")
        option.tap()

        // Pushed picker styles need popping; inline ones do not.
        if app.navigationBars[label].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// Written into the simulator's own `/tmp`, which is a real directory on the
    /// host under the device's data volume. Also attached, so a failing run in
    /// Xcode still shows what was on screen.
    private func capture(name: String) {
        // Let the screen settle first.
        //
        // A capture taken in the same instant as a swipe catches the scroll-edge
        // material mid-animation: the large title half faded into the bar, the
        // row behind it half blurred. At phone size that is a frame of an
        // animation; blown up to 1320 points on a store page it is a smear
        // across the top of the picture, and it cost a set of screenshots once
        // already.
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = URL(fileURLWithPath: "/tmp/babydocs-shots/\(name).png")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? screenshot.pngRepresentation.write(to: url)
    }
}
