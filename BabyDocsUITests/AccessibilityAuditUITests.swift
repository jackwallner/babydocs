import XCTest

/// Measurements for the large-text, one-handed persona audit.
///
/// These tests observe and record; they do not assert on product behaviour, so a
/// finding never turns the run red and hides the numbers behind it. Everything
/// goes into a `metrics` text attachment plus screenshots. Motion is not
/// measured here (no frame rate is claimed anywhere in these tests).
@MainActor
final class AccessibilityAuditUITests: XCTestCase {

    private static let ax5 = "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
    private static let ax3 = "UICTContentSizeCategoryAccessibilityExtraLarge"
    private static let tabs = ["Plan", "Children", "Documents", "Plus", "Settings"]

    private var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
        notes = []
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
        attachment.name = "metrics"
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = URL(fileURLWithPath: "/tmp/babydocs-a11y/\(name.replacingOccurrences(of: " ", with: "_")).txt")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? notes.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    /// Every button, link, switch and stepper on every tab and on one task
    /// detail, at the default text size, with anything under 44pt either way.
    func testTapTargetsAtDefaultSize() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"], size: nil)
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        for tab in Self.tabs {
            app.tabBars.buttons[tab].tap()
            settle()
            shot("tt-\(tab.lowercased())")
            scanTargets(app, screen: tab)
        }
        app.tabBars.buttons["Plan"].tap()
        settle()
        openCertifiedCopiesTask(app)
        shot("tt-task-detail")
        scanTargets(app, screen: "Task detail (top)")
        app.swipeUp()
        app.swipeUp()
        settle()
        scanTargets(app, screen: "Task detail (after 2 swipes)")
    }

    /// Each tab at accessibility XXXL: top and bottom of the scroll, the tab-bar
    /// clearance, the tick target next to its text, and what the Plus buy bar
    /// takes of the screen.
    func testLargeTextTabs() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"], size: Self.ax5)
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        let screenHeight = app.windows.firstMatch.frame.height
        note("AX5 screen height \(Int(screenHeight))pt, tab bar \(frame(app.tabBars.firstMatch))")

        for tab in Self.tabs {
            app.tabBars.buttons[tab].tap()
            settle()
            shot("ax5-\(tab.lowercased())-top")
            dumpLabels(app, screen: "AX5 \(tab)")
            if tab == "Plan" { measurePlan(app, screenHeight: screenHeight) }
            if tab == "Plus" { measurePlusBar(app, screenHeight: screenHeight) }
            let swipes = scrollToEnd(app, maxSwipes: 30)
            note("AX5 \(tab): \(swipes) swipes to reach the end of the page")
            settle()
            shot("ax5-\(tab.lowercased())-end")
            measureClearance(app, screen: "AX5 \(tab) end")
            if tab == "Plus" { measurePlusBar(app, screenHeight: screenHeight, suffix: " (scrolled to end)") }
        }
    }

    /// Plus offer at the default size, for the same buy-bar measurement.
    func testPlusBarAtDefaultSize() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"], size: nil)
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Plus"].tap()
        XCTAssertTrue(app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 10))
        settle()
        shot("default-plus")
        measurePlusBar(app, screenHeight: app.windows.firstMatch.frame.height)
        dumpLabels(app, screen: "Default Plus")
    }

    /// The intake at accessibility XXXL: how much of the screen the pinned
    /// footer takes, and whether the questions can be answered at all.
    func testLargeTextIntake() {
        let app = launch(["-uitest-wipe-store"], size: Self.ax5)
        XCTAssertTrue(app.staticTexts["The paperwork, in order"].waitForExistence(timeout: 20)
                      || app.buttons["Get started"].waitForExistence(timeout: 5))
        shot("ax5-intake-00-welcome")
        measureIntake(app, name: "welcome")
        app.buttons["Get started"].firstMatch.tap()
        guard app.navigationBars["Your baby"].waitForExistence(timeout: 8) else {
            note("AX5 intake: never reached the baby step")
            return
        }
        settle()
        shot("ax5-intake-01-baby")
        measureIntake(app, name: "baby")
        let toggle = app.switches["I checked this date"].firstMatch
        if scrollTo(toggle, in: app) { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        if scrollTo(app.buttons["US citizen"].firstMatch, in: app) { app.buttons["US citizen"].firstMatch.tap() }
        if choose(state: "California", labelled: "State of birth", in: app) == false { note("AX5 intake: could not pick state of birth") }
        settle()
        shot("ax5-intake-01b-baby-answered")
        measureIntake(app, name: "baby answered")
        app.buttons["Continue"].firstMatch.tap()

        guard app.navigationBars["Your household"].waitForExistence(timeout: 8) else {
            note("AX5 intake: Continue did not reach household (enabled=\(app.buttons["Continue"].firstMatch.isEnabled))")
            return
        }
        settle()
        shot("ax5-intake-02-household")
        measureIntake(app, name: "household")
        _ = choose(state: "California", labelled: "State you live in", in: app)
        if scrollTo(app.buttons["Married to the other parent"].firstMatch, in: app) {
            app.buttons["Married to the other parent"].firstMatch.tap()
        }
        app.buttons["Continue"].firstMatch.tap()

        guard app.navigationBars["Coverage"].waitForExistence(timeout: 8) else {
            note("AX5 intake: did not reach coverage")
            return
        }
        settle()
        shot("ax5-intake-03-coverage")
        measureIntake(app, name: "coverage")
        if scrollTo(app.buttons["Through a job"].firstMatch, in: app) {
            app.buttons["Through a job"].firstMatch.tap()
        }
        settle()
        shot("ax5-intake-04-coverage-employer")
        measureIntake(app, name: "coverage employer")
        app.buttons["Continue"].firstMatch.tap()
        if app.navigationBars["Leave"].waitForExistence(timeout: 8) {
            settle()
            shot("ax5-intake-05-leave")
            measureIntake(app, name: "leave")
        }
    }

    /// Whether the intake can be left by the system edge swipe, and how far the
    /// only Back control sits from a thumb.
    func testIntakeBackNavigation() {
        let app = launch(["-uitest-wipe-store"], size: nil)
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 20))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.navigationBars["Your baby"].waitForExistence(timeout: 8))
        let toggle = app.switches["I checked this date"].firstMatch
        if scrollTo(toggle, in: app) { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        if scrollTo(app.buttons["US citizen"].firstMatch, in: app) { app.buttons["US citizen"].firstMatch.tap() }
        _ = choose(state: "California", labelled: "State of birth", in: app)
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Your household"].waitForExistence(timeout: 8))
        settle()
        let back = app.buttons["Back"].firstMatch
        note("Household step Back button: \(frame(back)); screen \(app.windows.firstMatch.frame)")
        shot("back-before-edge-swipe")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        settle()
        let backOnBaby = app.navigationBars["Your baby"].waitForExistence(timeout: 2)
        let stillHousehold = app.navigationBars["Your household"].exists
        note("After left-edge swipe: onBaby=\(backOnBaby) stillOnHousehold=\(stillHousehold)")
        shot("back-after-edge-swipe")
    }

    /// How far down a task detail the primary action is, at three text sizes.
    func testTaskDetailReach() {
        for (label, size) in [("default", nil), ("AX3", Self.ax3), ("AX5", Self.ax5)] as [(String, String?)] {
            let app = launch(["-uitest-wipe-store", "-uitest-seed"], size: size)
            XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
            openCertifiedCopiesTask(app, scrolling: size != nil)
            settle()
            shot("reach-\(label)-top")
            let markDone = app.buttons["Mark done"].firstMatch
            let swipes = swipesToReach(markDone, in: app, max: 40)
            note("\(label): swipes to Mark done = \(swipes.map(String.init) ?? "not reached in 40")")
            settle()
            shot("reach-\(label)-markdone")
            let footnote = app.links["Where this comes from"].firstMatch
            let more = swipesToReach(footnote, in: app, max: 40)
            note("\(label): further swipes to the source link = \(more.map(String.init) ?? "not reached")")
            app.terminate()
        }
    }

    /// Ticking a document moves rows: record where the neighbours go.
    func testDocumentTickShift() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"], size: nil)
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.navigationBars["Documents"].waitForExistence(timeout: 8))
        settle()
        shot("docs-before-tick")
        let ticks = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark ' AND label ENDSWITH 'as in hand'"))
        let count = ticks.count
        note("Documents: \(count) untick rows on the first screen query")
        guard count >= 3 else { return }
        let before = (0..<3).map { frame(ticks.element(boundBy: $0)) + " " + ticks.element(boundBy: $0).label }
        note("Before tick: \n  " + before.joined(separator: "\n  "))
        ticks.element(boundBy: 0).tap()
        shot("docs-immediately-after-tick")
        usleep(300_000)
        let mid = (0..<3).map { frame(ticks.element(boundBy: $0)) + " " + ticks.element(boundBy: $0).label }
        note("300 ms after tick: \n  " + mid.joined(separator: "\n  "))
        settle()
        shot("docs-settled-after-tick")
        let after = (0..<3).map { frame(ticks.element(boundBy: $0)) + " " + ticks.element(boundBy: $0).label }
        note("Settled: \n  " + after.joined(separator: "\n  "))
    }

    /// The plan with the first task ticked, then the same task in the "done" state:
    /// what the row says to the accessibility layer.
    func testPlanRowAccessibilityDump() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"], size: nil)
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        settle()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark ' AND label ENDSWITH ' done'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        note("Before: tick label = \(first.label)")
        first.tap()
        settle()
        shot("plan-after-first-tick")
        let ticked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark ' AND label ENDSWITH ' not done'")).firstMatch
        note("After tick: found untick control = \(ticked.exists) label = \(ticked.label)")
        dumpLabels(app, screen: "Plan after one tick", limit: 16)
    }

    // MARK: - Measurements

    private func measurePlan(_ app: XCUIApplication, screenHeight: CGFloat) {
        let ticks = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark ' AND (label ENDSWITH ' done' OR label ENDSWITH ' not done')"))
        let firstTick = ticks.firstMatch
        if firstTick.exists {
            note("AX5 Plan: first tick control \(frame(firstTick)), hittable=\(firstTick.isHittable), minY/screen = \(Int(firstTick.frame.minY))/\(Int(screenHeight))")
        } else {
            note("AX5 Plan: no tick control on the first screen")
        }
        let cells = app.cells.allElementsBoundByIndex.filter { $0.isHittable }
        note("AX5 Plan: \(cells.count) rows hittable on the first screen")
    }

    private func measurePlusBar(_ app: XCUIApplication, screenHeight: CGFloat, suffix: String = "") {
        let names = ["Start my free trial", "Get started", "Continue", "Buy it once", "Restore purchases", "Continue with the free plan"]
        var minY = CGFloat.greatestFiniteMagnitude
        for name in names {
            let element = app.buttons[name].firstMatch
            if element.exists {
                note("Plus\(suffix): \(name) \(frame(element)) hittable=\(element.isHittable)")
                minY = min(minY, element.frame.minY)
            }
        }
        let disclosure = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'then' OR label CONTAINS 'free for' OR label CONTAINS 'Renews'")).allElementsBoundByIndex
        for text in disclosure.prefix(4) where text.frame.minY > screenHeight * 0.4 {
            note("Plus\(suffix): disclosure text \(frame(text))")
            minY = min(minY, text.frame.minY)
        }
        if minY < .greatestFiniteMagnitude {
            note("Plus\(suffix): fixed purchase bar top ~\(Int(minY)) of \(Int(screenHeight)): bar takes about \(Int((screenHeight - minY) / screenHeight * 100))% of the screen (approximate, includes disclosure text found above the button)")
        }
    }

    private func measureClearance(_ app: XCUIApplication, screen: String) {
        let bar = app.tabBars.firstMatch
        let visible = app.cells.allElementsBoundByIndex.filter { $0.isHittable }
        guard let lowest = visible.max(by: { $0.frame.maxY < $1.frame.maxY }) else {
            note("\(screen): no hittable cells"); return
        }
        note("\(screen): lowest hittable cell maxY=\(Int(lowest.frame.maxY)), tab bar minY=\(Int(bar.frame.minY)), gap=\(Int(bar.frame.minY - lowest.frame.maxY))")
    }

    private func measureIntake(_ app: XCUIApplication, name: String) {
        let screen = app.windows.firstMatch.frame
        let cont = app.buttons["Continue"].firstMatch.exists ? app.buttons["Continue"].firstMatch : app.buttons["Get started"].firstMatch
        let navMax = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 0
        guard cont.exists else { note("Intake \(name): no Continue/Get started button"); return }
        let footer = screen.maxY - cont.frame.minY
        let form = cont.frame.minY - navMax
        note("Intake \(name): button \(frame(cont)); footer from button top to bottom edge \(Int(footer))pt; form viewport between nav bar and footer \(Int(form))pt of \(Int(screen.height))pt (\(Int(form / screen.height * 100))%)")
    }

    private func scanTargets(_ app: XCUIApplication, screen: String) {
        let bar = app.tabBars.firstMatch.frame
        var small: [String] = []
        var scanned = 0
        let types: [XCUIElement.ElementType] = [.button, .link, .switch, .stepper, .segmentedControl]
        for type in types {
            for element in app.descendants(matching: type).allElementsBoundByIndex.prefix(70) {
                let f = element.frame
                guard element.exists, !f.isEmpty, !f.intersects(bar) || type == .button && f.minY < bar.minY else { continue }
                if f.maxY < 0 || f.minY > app.windows.firstMatch.frame.maxY { continue }
                scanned += 1
                if f.height < 43.5 || f.width < 43.5 {
                    small.append("  \(type) \"\(element.label)\" \(Int(f.width))x\(Int(f.height)) at (\(Int(f.minX)),\(Int(f.minY)))")
                }
            }
        }
        note("\(screen): scanned \(scanned) controls, \(small.count) under 44pt in a dimension")
        small.forEach { note($0) }
    }

    private func dumpLabels(_ app: XCUIApplication, screen: String, limit: Int = 10) {
        let items = app.descendants(matching: .any).matching(NSPredicate(format: "elementType IN %@", [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.staticText.rawValue, XCUIElement.ElementType.link.rawValue, XCUIElement.ElementType.switch.rawValue])).allElementsBoundByIndex
        note("\(screen): accessibility tree (first \(limit) leaf controls/texts)")
        for element in items.prefix(limit) where element.exists {
            let value = (element.value as? String) ?? ""
            note("  [\(element.elementType.rawValue)] label=\"\(element.label)\" value=\"\(value)\" \(frame(element))")
        }
    }

    // MARK: - Plumbing

    private func launch(_ args: [String], size: String?) -> XCUIApplication {
        let app = XCUIApplication()
        var all = args
        if let size { all += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments = all
        app.launch()
        return app
    }

    private func openCertifiedCopiesTask(_ app: XCUIApplication, scrolling: Bool = false) {
        let title = "Order certified copies of the birth certificate"
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 25 {
            if !scrolling && tries > 3 { break }
            app.swipeUp()
            tries += 1
        }
        if row.exists { row.tap() } else { note("Could not find the certified copies row after \(tries) swipes") }
        _ = app.staticTexts["Timing"].waitForExistence(timeout: 5)
    }

    private func scrollToEnd(_ app: XCUIApplication, maxSwipes: Int) -> Int {
        var previous = app.screenshot().pngRepresentation
        for count in 1...maxSwipes {
            app.swipeUp()
            usleep(600_000)
            let current = app.screenshot().pngRepresentation
            if current == previous { return count - 1 }
            previous = current
        }
        return maxSwipes
    }

    private func swipesToReach(_ element: XCUIElement, in app: XCUIApplication, max: Int) -> Int? {
        for count in 0...max {
            if element.exists && element.isHittable { return count }
            app.swipeUp()
        }
        return nil
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        let footer = app.buttons["Continue"].firstMatch
        for _ in 0..<12 {
            if element.exists && element.isHittable && (!footer.exists || element.frame.maxY <= footer.frame.minY) { return true }
            app.swipeUp()
        }
        return element.isHittable
    }

    private func choose(state: String, labelled label: String, in app: XCUIApplication) -> Bool {
        let row = app.cells.containing(.staticText, identifier: label).firstMatch
        guard row.waitForExistence(timeout: 5), scrollTo(row, in: app) else { return false }
        row.tap()
        let option = app.buttons[state].firstMatch
        guard option.waitForExistence(timeout: 5) else { return false }
        option.tap()
        if app.navigationBars[label].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        return true
    }

    private func frame(_ element: XCUIElement) -> String {
        guard element.exists else { return "(missing)" }
        let f = element.frame
        return "\(Int(f.width))x\(Int(f.height)) at (\(Int(f.minX)),\(Int(f.minY)))"
    }

    private func note(_ text: String) { notes.append(text) }

    private func settle() { Thread.sleep(forTimeInterval: 0.8) }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = URL(fileURLWithPath: "/tmp/babydocs-a11y/\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: url)
    }
}
