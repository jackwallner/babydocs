import XCTest

@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testFirstPlanAndOptionalPlus() {
        let app = XCUIApplication()
        QA.launch(app, arguments: ["-uitest-wipe-store"])
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "welcome")
        app.buttons["Get started"].tap()
        page("Your baby", in: app)

        let date = app.switches["I checked this date"].firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        date.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tapScrolling(app.buttons["US citizen"].firstMatch, in: app)
        chooseCalifornia("State of birth", in: app)
        proceed(app)
        page("Your household", in: app)
        chooseCalifornia("State you live in", in: app)
        tapScrolling(app.buttons["Prefer not to say"].firstMatch, in: app)
        proceed(app)
        page("Coverage", in: app)
        app.buttons["Not sure yet"].firstMatch.tap()
        proceed(app)
        page("Leave", in: app)
        app.buttons["Nobody is taking leave"].firstMatch.tap()
        proceed(app)
        for title in ["Newborn account", "529", "Passport"] {
            page(title, in: app)
            proceed(app)
        }

        XCTAssertTrue(app.buttons["See my plan"].waitForExistence(timeout: 15))
        QA.checkpoint(app, "plan-ready")
        app.buttons["See my plan"].tap()
        XCTAssertTrue(app.buttons["Continue with the free plan"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "onboarding-paywall", paywall: true)
        app.buttons["Continue with the free plan"].tap()
        page("Plan", checkpoint: "plan-after-onboarding", in: app)
    }

    func testPlanDocumentsPlusAndReturn() {
        let app = XCUIApplication()
        QA.launch(app, arguments: ["-uitest-wipe-store", "-uitest-seed"])
        page("Plan", checkpoint: "plan-launch", in: app)
        let task = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Order certified copies of the birth certificate"
        )).firstMatch
        tapScrolling(task, in: app)
        XCTAssertTrue(app.staticTexts["Timing"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "task-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        page("Plan", checkpoint: "plan-after-task", in: app)

        for (tab, title) in [("Documents", "Documents"), ("Children", "Children"),
                             ("Plus", "Baby Docs Plus"), ("Settings", "Settings")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            QA.checkpoint(app, tab.lowercased(), paywall: tab == "Plus")
        }
        app.tabBars.buttons["Plan"].tap()
        page("Plan", checkpoint: "plan-return", in: app)
        QA.interrupt(app)
        page("Plan", checkpoint: "plan-after-background", in: app)
        app.launchArguments.removeAll { $0 == "-uitest-wipe-store" || $0 == "-uitest-seed" }
        QA.relaunch(app)
        page("Plan", checkpoint: "plan-after-relaunch", in: app)
    }

    private func page(_ title: String, checkpoint: String? = nil, in app: XCUIApplication,
                      journey: String = #function) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
        QA.checkpoint(app, checkpoint ?? title.lowercased().replacingOccurrences(of: " ", with: "-"),
                      journey: journey)
    }

    private func proceed(_ app: XCUIApplication) {
        let button = app.buttons["Continue"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
        button.tap()
    }

    private func tapScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let footer = app.buttons["Continue"].firstMatch
        for _ in 0..<12 {
            if element.isHittable && (!footer.exists || element.frame.maxY <= footer.frame.minY) {
                break
            }
            app.swipeUp()
        }
        element.tap()
    }

    private func chooseCalifornia(_ label: String, in app: XCUIApplication) {
        let row = app.cells.containing(.staticText, identifier: label).firstMatch
        tapScrolling(row, in: app)
        let option = app.buttons["California"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        if app.navigationBars[label].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
