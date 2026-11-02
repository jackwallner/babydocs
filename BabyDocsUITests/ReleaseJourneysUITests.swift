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
        goBack(app)
        page("Plan", checkpoint: "plan-after-task", in: app)

        for (tab, title) in [("Documents", "Documents"), ("Children", "Children"),
                             ("Plus", "Baby Docs Plus"), ("Settings", "Settings")] {
            openTab(tab, in: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            QA.checkpoint(app, tab.lowercased(), paywall: tab == "Plus")
        }
        openTab("Plan", in: app)
        page("Plan", checkpoint: "plan-return", in: app)
        QA.interrupt(app)
        page("Plan", checkpoint: "plan-after-background", in: app)
        app.launchArguments.removeAll { $0 == "-uitest-wipe-store" || $0 == "-uitest-seed" }
        QA.relaunch(app)
        page("Plan", checkpoint: "plan-after-relaunch", in: app)
    }

    /// The core loop: tick a task on the plan, and it is still ticked after a
    /// kill and relaunch.
    func testCoreLoopTickTaskSurvivesRelaunch() {
        let app = XCUIApplication()
        QA.launch(app, arguments: ["-uitest-wipe-store", "-uitest-seed"])
        page("Plan", checkpoint: "core-plan", in: app)

        let open = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH 'Mark ' AND label ENDSWITH ' done' AND NOT label ENDSWITH ' not done'"
        )).firstMatch
        reveal(open, in: app)
        let title = open.label.dropFirst("Mark ".count).dropLast(" done".count)
        open.tap()
        // A done task leaves the open list (it moves under the folded done section).
        let stillOpen = app.buttons["Mark \(title) done"]
        XCTAssertTrue(stillOpen.waitForNonExistence(timeout: 10), "ticked task leaves the open list")
        QA.checkpoint(app, "core-ticked")

        app.launchArguments.removeAll { $0 == "-uitest-wipe-store" || $0 == "-uitest-seed" }
        QA.relaunch(app)
        page("Plan", checkpoint: "core-after-relaunch", in: app)
        XCTAssertFalse(app.buttons["Mark \(title) done"].exists, "the tick survives a relaunch")
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
        for attempt in 0..<32 {
            let top = navigation.exists ? navigation.frame.maxY : app.frame.minY
            var bottom = app.frame.maxY
            if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY) }
            if bar.exists && bar.frame.width > app.frame.width / 2 { bottom = min(bottom, bar.frame.minY) }
            let center = element.exists ? element.frame.midY : bottom
            if element.exists && element.isHittable && center > top && center < bottom {
                return
            }
            // QA.swipe, never a raw drag or swipeUp(): on the unfolded iPhone Duo the
            // inner display is rotated against the device and those land sideways.
            let towardTop = element.exists && center <= top
            let page = scroller(in: app)
            // If the standard swipe does not move the page (a rotated inner display),
            // fall back to XCTest's own, then to a drag along the rotated axis.
            switch attempt % 3 {
            case 0: QA.swipe(page, towardTop ? .down : .up)
            case 1: if towardTop { page.swipeDown() } else { page.swipeUp() }
            default:
                let from = CGVector(dx: towardTop ? 0.2 : 0.8, dy: 0.5)
                let to = CGVector(dx: towardTop ? 0.8 : 0.2, dy: 0.5)
                page.coordinate(withNormalizedOffset: from)
                    .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: to))
            }
        }
        XCTFail("Could not scroll the requested control into view: \(element)")
    }

    /// The tab bar's button, or on the unfolded Duo the pane's own tab buttons.
    /// Documents has no tab there: it already sits beside the Plan.
    private func openTab(_ name: String, in app: XCUIApplication) {
        let bar = app.tabBars.buttons[name]
        if bar.exists { bar.tap(); return }
        let pane = app.buttons[name].firstMatch
        if pane.waitForExistence(timeout: 5) { pane.tap() }
    }

    /// The largest scrolling container, so a small scroller (the Duo's pane tab
    /// capsule) is never mistaken for the page.
    private func scroller(in app: XCUIApplication) -> XCUIElement {
        let all = [app.scrollViews, app.collectionViews, app.tables]
            .flatMap { $0.allElementsBoundByIndex }
            .filter { $0.exists && $0.frame.height > 150 }
        return all.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height } ?? app
    }

    /// Back from a pushed screen: the nav bar's button, or on the Duo, where the
    /// bar is vertical or hidden, a labelled button or an edge swipe.
    private func goBack(_ app: XCUIApplication) {
        let bar = app.navigationBars.buttons.element(boundBy: 0)
        if bar.exists && bar.isHittable { bar.tap(); return }
        let named = app.buttons.matching(NSPredicate(format: "label IN {'Back','Plan'}")).firstMatch
        if named.exists && named.isHittable { named.tap(); return }
        QA.swipe(app, .right)
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
