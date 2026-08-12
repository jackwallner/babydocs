import XCTest

/// Drives the app through the screens worth looking at and writes each one to
/// the simulator's `/tmp`, where a script (or a person) can pick it up.
///
/// A UI test rather than `simctl io screenshot` because the screens that matter
/// are two taps in, and because a screenshot is only proof if the state behind
/// it came from a real reconciliation pass rather than a hand-built fixture: if
/// a rule is wrong, the picture has to be wrong too.
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
            app.staticTexts["Suggested by"].waitForExistence(timeout: 5),
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

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture(name: "06-settings")
    }

    func testCaptureTheIntake() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store"]
        app.launch()

        XCTAssertTrue(app.staticTexts["The paperwork, in order"].waitForExistence(timeout: 15))
        capture(name: "00-welcome")
    }

    /// Written into the simulator's own `/tmp`, which is a real directory on the
    /// host under the device's data volume. Also attached, so a failing run in
    /// Xcode still shows what was on screen.
    private func capture(name: String) {
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
