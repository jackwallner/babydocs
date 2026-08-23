import XCTest

/// Product-evidence capture and interaction regression coverage.
@MainActor
final class VisualCaptureUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testCaptureTheNewSurfaces() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))

        let row = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "File the first parent's leave claim"
            )
        ).firstMatch
        for _ in 0..<8 where !row.exists || !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.isHittable, "never scrolled to the row")
        let before = row.frame.origin.y
        shot("1-plan-before")

        let tick = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Mark File the first parent")
        ).firstMatch
        XCTAssertTrue(tick.exists, "no tick control beside the row")
        tick.tap()
        shot("2-plan-after-tick")

        XCTAssertTrue(row.exists && row.isHittable, "The ticked row left the screen")
        XCTAssertEqual(before, row.frame.origin.y, accuracy: 1, "The ticked row moved")

        app.tabBars.buttons["Plus"].tap()
        XCTAssertTrue(app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 10))
        shot("4-plus-free")
    }

    func testCaptureThePlusTools() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed", "-uitest-pro"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Plus"].tap()
        XCTAssertTrue(app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 10))
        shot("5-plus-tools-top")
        app.swipeUp()
        app.swipeUp()
        shot("6-plus-tools-middle")
        app.swipeUp()
        app.swipeUp()
        shot("7-plus-tools-bottom")
    }

    func testCaptureTheIntakeEnding() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store"]
        app.launch()

        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.navigationBars["Your baby"].waitForExistence(timeout: 5))
        shot("8-intake-baby")

        let dateConfirmation = app.switches["I checked this date"].firstMatch
        XCTAssertTrue(dateConfirmation.waitForExistence(timeout: 5))
        dateConfirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tapScrolling(app.buttons["US citizen"].firstMatch, in: app)
        choose(state: "California", labelled: "State of birth", in: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Your household"].waitForExistence(timeout: 5))
        shot("9-intake-household")
        choose(state: "California", labelled: "State you live in", in: app)
        tapScrolling(app.buttons["Prefer not to say"].firstMatch, in: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Coverage"].waitForExistence(timeout: 5))
        shot("10-intake-coverage")
        tapScrolling(app.buttons["Through a job"].firstMatch, in: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Leave"].waitForExistence(timeout: 5))
        shot("11-intake-leave")
        tapScrolling(app.buttons["Nobody is taking leave"].firstMatch, in: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Newborn account"].waitForExistence(timeout: 5))
        shot("12-intake-explained")
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["529"].waitForExistence(timeout: 5))
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Passport"].waitForExistence(timeout: 5))
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts["Your plan is ready"].waitForExistence(timeout: 10),
            "The plan-is-ready page is still unreachable"
        )
        shot("13-intake-done")
        app.buttons["See my plan"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 10))
        shot("14-intake-plus")
        XCTAssertTrue(app.buttons["Continue with the free plan"].waitForExistence(timeout: 5))
        app.buttons["Continue with the free plan"].tap()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 10))
        shot("15-landed-on-plan")
    }

    private func tapScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let footer = app.buttons["Continue"].firstMatch
        for _ in 0..<8 {
            let clear = element.exists && element.isHittable
                && (!footer.exists || element.frame.maxY <= footer.frame.minY)
            if clear { break }
            app.swipeUp()
        }
        element.tap()
    }

    private func choose(state: String, labelled label: String, in app: XCUIApplication) {
        let row = app.cells.containing(.staticText, identifier: label).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No picker row labelled \(label)")
        tapScrolling(row, in: app)
        let option = app.buttons[state].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "\(state) never appeared")
        option.tap()
        if app.navigationBars[label].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
