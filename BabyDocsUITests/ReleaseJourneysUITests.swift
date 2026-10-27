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
        reveal(date, in: app)
        date.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tapScrolling(app.buttons["US citizen"].firstMatch, in: app)
        chooseCalifornia("State of birth", in: app)
        proceed(app)
        page("Your household", in: app)
        chooseCalifornia("State you live in", in: app)
        tapScrolling(app.buttons["Prefer not to say"].firstMatch, in: app)
        proceed(app)
        page("Coverage", in: app)
        tapScrolling(app.buttons["Not sure yet"].firstMatch, in: app)
        proceed(app)
        page("Leave", in: app)
        tapScrolling(app.buttons["Nobody is taking leave"].firstMatch, in: app)
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
        XCTAssertTrue(app.navigationBars["Birth certificate"].waitForExistence(timeout: 10))
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

    func testCoreLoopTickTaskCountsAndSurvivesRelaunch() {
        let app = XCUIApplication()
        QA.launch(app, arguments: ["-uitest-wipe-store", "-uitest-seed"])
        page("Plan", checkpoint: "plan-seeded", in: app)
        let before = doneCount(in: app)

        let open = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH 'Mark Order certified copies' AND label ENDSWITH ' done' AND NOT label ENDSWITH ' not done'"
        )).firstMatch
        reveal(open, in: app)
        let title = open.label
            .replacingOccurrences(of: "Mark ", with: "")
            .replacingOccurrences(of: " done", with: "")
        open.tap()
        let ticked = app.buttons["Mark \(title) not done"]
        XCTAssertTrue(ticked.waitForExistence(timeout: 10), "ticked row did not flip")
        XCTAssertEqual(doneCount(in: app), before + 1)
        QA.checkpoint(app, "task-ticked")

        app.launchArguments.removeAll { $0 == "-uitest-wipe-store" || $0 == "-uitest-seed" }
        QA.relaunch(app)
        page("Plan", checkpoint: "plan-after-relaunch", in: app)
        XCTAssertEqual(doneCount(in: app), before + 1, "done count lost after relaunch")
        XCTAssertTrue(app.buttons["Mark \(title) not done"].waitForExistence(timeout: 10),
                      "ticked task not done after relaunch")
        QA.checkpoint(app, "task-still-ticked")
    }

    private func doneCount(in app: XCUIApplication) -> Int {
        let label = app.staticTexts.matching(NSPredicate(
            format: "label MATCHES %@", "[0-9]+ of [0-9]+ done"
        )).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 15), "no done count on the plan")
        return Int(label.label.split(separator: " ")[0]) ?? -1
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
        reveal(element, in: app)
        element.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let footer = app.buttons["Continue"].firstMatch
        let bar = app.tabBars.firstMatch
        let navigation = app.navigationBars.firstMatch
        for _ in 0..<32 {
            let top = navigation.exists ? navigation.frame.maxY : app.frame.minY
            var bottom = app.frame.maxY
            if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY) }
            if bar.exists && bar.frame.width > app.frame.width / 2 { bottom = min(bottom, bar.frame.minY) }
            let center = element.exists ? element.frame.midY : bottom
            if element.exists && element.isHittable && center > top && center < bottom {
                return
            }
            let down = element.exists && center <= top
            let span = max(bottom - top, 100)
            let start = top + span * (down ? 0.35 : 0.70)
            let end = top + span * (down ? 0.60 : 0.45)
            app.coordinate(withNormalizedOffset: CGVector(
                dx: 0.5, dy: (start - app.frame.minY) / app.frame.height
            )).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(
                dx: 0.5, dy: (end - app.frame.minY) / app.frame.height
            )))
        }
        XCTFail("Could not scroll the requested control into view: \(element)")
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
