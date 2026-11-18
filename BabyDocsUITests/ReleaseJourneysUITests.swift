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
        for dx in [0.92, 0.85, 0.96] where (date.value as? String) != "1" {
            date.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            _ = date.waitForExistence(timeout: 1)
        }
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
        // A tall row: tap its upper part, clear of the home indicator below it.
        reveal(task, in: app)
        task.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25)).tap()
        XCTAssertTrue(app.navigationBars["Birth certificate"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "task-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        page("Plan", checkpoint: "plan-after-task", in: app)

        for (tab, title) in [("Documents", "Documents"), ("Children", "Children"),
                             ("Plus", "Baby Docs Plus"), ("Settings", "Settings")] {
            // Unfolded, Documents sits beside the Plan instead of in the bar.
            if tab == "Documents" && !app.tabBars.buttons[tab].exists {
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
                QA.checkpoint(app, tab.lowercased())
                continue
            }
            QA.openTab(app, tab)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            QA.checkpoint(app, tab.lowercased(), paywall: tab == "Plus")
        }
        QA.openTab(app, "Plan")
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
        XCTAssertTrue(waitForDoneCount(before + 1, in: app), "done count did not go up after the tick")
        reveal(tickedButton(title, in: app), in: app)
        QA.checkpoint(app, "task-ticked")

        app.launchArguments.removeAll { $0 == "-uitest-wipe-store" || $0 == "-uitest-seed" }
        QA.relaunch(app)
        page("Plan", checkpoint: "plan-after-relaunch", in: app)
        XCTAssertEqual(doneCount(in: app), before + 1, "done count lost after relaunch")
        reveal(tickedButton(title, in: app), in: app)
        QA.checkpoint(app, "task-still-ticked")
    }

    private func tickedButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", "Mark \(title) not done")).firstMatch
    }

    private func doneLabel(matching format: String, _ argument: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: format, argument)).firstMatch
    }

    /// The count sits in the plan's header card, which a list at an accessibility
    /// text size unloads once it scrolls away, so look for it from the top.
    private func scrollToCount(_ label: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 where !label.exists {
            QA.swipe(scroller(for: label, in: app), .down)
        }
    }

    private func waitForDoneCount(_ expected: Int, in app: XCUIApplication) -> Bool {
        let label = doneLabel(matching: "label BEGINSWITH %@ AND label ENDSWITH ' done'", "\(expected) of ", in: app)
        scrollToCount(label, in: app)
        return label.waitForExistence(timeout: 10)
    }

    private func doneCount(in app: XCUIApplication) -> Int {
        let label = doneLabel(matching: "label MATCHES %@", "[0-9]+ of [0-9]+ done", in: app)
        XCTAssertTrue(label.waitForExistence(timeout: 15), "no done count on the plan")
        scrollToCount(label, in: app)
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
        let enabled = NSPredicate(format: "isEnabled == true")
        let wait = XCTNSPredicateExpectation(predicate: enabled, object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 10), .completed, "Continue stayed disabled")
        button.tap()
    }

    /// A tab by its label: the system bar on iPhone, or the pane's own bar beside
    /// Documents on the unfolded Duo and a regular-width iPad.
    private func tabButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        QA.tab(app, label)
    }

    private func tapScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let footer = app.buttons["Continue"].firstMatch
        let bar = app.tabBars.firstMatch
        for _ in 0..<32 {
            let pane = scroller(for: element, in: app)
            // The bar above this pane: on a split layout each pane has its own,
            // and firstMatch may be its neighbour's or one the pane never reaches.
            let top = app.navigationBars.allElementsBoundByIndex
                .filter { $0.exists && $0.frame.midX >= pane.frame.minX && $0.frame.midX <= pane.frame.maxX
                    && $0.frame.maxY < pane.frame.midY }
                .map { $0.frame.maxY }.max() ?? max(app.frame.minY, pane.frame.minY)
            var bottom = pane.frame.maxY
            if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY) }
            // The floating bar over this pane, judged by the pane's own frame: on
            // the unfolded Duo the app's frame is turned against its contents.
            if bar.exists && bar.frame.minY > pane.frame.midY
                && bar.frame.midX >= pane.frame.minX && bar.frame.midX <= pane.frame.maxX {
                bottom = min(bottom, bar.frame.minY)
            }
            let center = element.exists ? element.frame.midY : bottom
            if element.exists && element.isHittable && center > top && center < bottom {
                return
            }
            let down = element.exists && center <= top
            drag(pane, down: down, between: top, and: bottom, in: app)
        }
        XCTFail("Could not scroll the requested control into view: \(element)")
    }

    /// The drag is laid out in the scroller's own coordinates, as QA.swipe does,
    /// because on the unfolded Duo the app's frame and its coordinate space are
    /// turned against each other. It stays inside the band the footer and the
    /// floating tab bar leave visible, which QA.swipe's 80% start does not.
    private func drag(_ scroller: XCUIElement, down: Bool, between top: CGFloat, and bottom: CGFloat,
                      in app: XCUIApplication) {
        let frame = scroller.frame
        guard frame.height > 0 else { return }
        let low = max(top, frame.minY), high = min(bottom, frame.maxY)
        let band = max(high - low, 100)
        func fraction(_ y: CGFloat) -> CGFloat { min(max((y - frame.minY) / frame.height, 0.02), 0.98) }
        let near = fraction(low + band * 0.75), far = fraction(low + band * 0.25)
        scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? far : near))
            .press(forDuration: 0.05,
                   thenDragTo: scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? near : far)),
                   withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// The scroll container to drag: the one under the element when it is known,
    /// so the unfolded Duo scrolls the pane that holds it rather than the hinge.
    private func scroller(for element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let containers = [XCUIElement.ElementType.scrollView, .table, .collectionView]
            .flatMap { app.descendants(matching: $0).allElementsBoundByIndex }
            .filter { $0.exists && $0.frame.height > 200 }
        if element.exists, !element.label.isEmpty,
           let owner = containers.first(where: {
               $0.descendants(matching: .any).matching(NSPredicate(format: "label == %@", element.label))
                   .firstMatch.exists
           }) { return owner }
        if element.exists, let owner = containers.first(where: {
            $0.frame.minX <= element.frame.midX && element.frame.midX <= $0.frame.maxX
        }) { return owner }
        // A control not on screen yet: on the split layouts the plan's pane is the
        // one that holds the task ticks, so scroll that one, not its neighbour.
        let planBar = app.navigationBars["Plan"]
        if planBar.exists, let plan = containers.first(where: {
            $0.frame.minX <= planBar.frame.midX && planBar.frame.midX <= $0.frame.maxX
        }) { return plan }
        let tick = NSPredicate(format: "label MATCHES 'Mark .* (done|not done)' AND NOT label ENDSWITH 'in hand'")
        if let plan = containers.first(where: {
            $0.descendants(matching: .button).matching(tick).firstMatch.exists
        }) { return plan }
        return containers.first ?? app
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
