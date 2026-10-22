import XCTest

/// Persona audit: an experienced user repeating the core loop (tick, open,
/// record, gather, edit) and looking for friction. Every test writes what it
/// observed to a text attachment next to the screenshots, because a passing
/// test here means "the flow was walked", not "the flow is good".
@MainActor
final class ExperiencedUserAuditUITests: XCTestCase {

    private var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
        notes = []
    }

    override func tearDown() {
        let text = notes.joined(separator: "\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = "observations-\(name.replacingOccurrences(of: " ", with: "_"))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Flows

    /// Tick, open, mark done from the detail: the loop an experienced user runs
    /// dozens of times in week two.
    func testRepeatCompletionLoop() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"])
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        shot("A01-plan-top")

        // How far down the last task is.
        let lastTitle = "Get on childcare waitlists"
        let swipes = swipesToReach(app.buttons["Mark \(lastTitle) done"], in: app, max: 25)
        note("Swipes from the top of the Plan to the last task row: \(swipes.map(String.init) ?? "not reached in 25")")
        shot("A02-plan-bottom")
        app.statusBars.firstMatch.tap()
        sleep(1)

        // Tick target size and immediate feedback.
        let ssnTick = app.buttons["Mark Get the Social Security number and card done"]
        if ssnTick.waitForExistence(timeout: 5) {
            note("Tick button frame: \(ssnTick.frame.width) x \(ssnTick.frame.height)")
            ssnTick.tap()
            shotNow("A03-after-first-tick-immediate")
            Thread.sleep(forTimeInterval: 1.0)
            shot("A04-after-first-tick-settled")
            note("Tick relabelled to 'not done': \(app.buttons["Mark Get the Social Security number and card not done"].exists)")
        } else {
            note("SSN tick not found at top; plan order differs")
        }

        // Open a task, find 'Mark done'.
        let w4 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Update tax withholding at work")).firstMatch
        let found = swipesToReach(w4, in: app, max: 15)
        note("Swipes to reach the withholding row: \(found.map(String.init) ?? "not reached")")
        if w4.exists {
            w4.tap()
            sleep(1)
            shot("A05-detail-top")
            let done = app.buttons["Mark done"]
            let toDone = swipesToReach(done, in: app, max: 15)
            note("Detail screen: swipes from the top to the 'Mark done' button: \(toDone.map(String.init) ?? "not reached")")
            shot("A06-detail-markdone-region")
            if done.exists && done.isHittable {
                done.tap()
                shotNow("A07-after-mark-done-immediate")
                Thread.sleep(forTimeInterval: 1.0)
                shot("A08-after-mark-done-settled")
                note("After Mark done, still on detail: \(app.buttons["Mark not done"].exists)")
            }
        }
    }

    /// The certificate and the SSN each exist as a task *and* as a switch on the
    /// child. Ticking the task is what an experienced user does.
    func testCertificateTwoBookkeepingPlaces() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"])
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))

        let tick = app.buttons["Mark Order certified copies of the birth certificate done"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5), "order tick missing")
        tick.tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("B01-ticked-order-task")

        let nameCheck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Check the name and details on the certificate")).firstMatch
        note("After ticking 'Order certified copies': 'Check the name and details' task present: \(swipeFind(nameCheck, in: app))")
        app.statusBars.firstMatch.tap()
        sleep(1)

        // The SSN task, same question.
        let ssn = app.buttons["Mark Get the Social Security number and card done"]
        if ssn.exists { ssn.tap() }
        Thread.sleep(forTimeInterval: 1.0)
        let ssnTaskStillSaysWaiting = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Claim the $1,000 newborn account")).firstMatch
        if swipeFind(ssnTaskStillSaysWaiting, in: app) {
            ssnTaskStillSaysWaiting.tap()
            sleep(1)
            shot("B02-newborn-account-after-ssn-ticked")
            let waiting = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "waiting on the SSN card")).firstMatch
            note("Newborn-account detail still says 'waiting on the SSN card' after the SSN task was ticked: \(waiting.exists)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.tabBars.buttons["Children"].tap()
        XCTAssertTrue(app.navigationBars["Children"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rosa")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        sleep(1)
        shot("B03-child-detail")
        let toggle = app.switches["Certified birth certificate in hand"]
        if toggle.waitForExistence(timeout: 5) {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.0)
            shot("B04-certificate-toggled")
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Plan"].tap()
        sleep(1)
        let order = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Order certified copies")).firstMatch
        note("After flipping the certificate switch: 'Order certified copies' (the task just ticked) still on the Plan: \(swipeFind(order, in: app))")
        shot("B05-plan-after-toggle")
    }

    /// Adding the second twin.
    func testAddSecondChildFriction() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"])
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Children"].tap()
        XCTAssertTrue(app.navigationBars["Children"].waitForExistence(timeout: 5))
        shot("C01-children")
        let add = app.buttons["Add another child"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        sleep(1)
        shot("C02-new-child-sheet")
        let addButton = app.buttons["Add"]
        note("Add enabled on open: \(addButton.exists && addButton.isEnabled)")
        note("Fields pre-filled from the first child: state picker value = \(app.cells.containing(.staticText, identifier: "State of birth").firstMatch.label)")
        note("Date of birth confirmation switch value = \(app.switches["I checked this date"].firstMatch.value as? String ?? "?")")
        app.swipeUp()
        shot("C03-new-child-sheet-scrolled")
    }

    /// Changing an answer and seeing what it did.
    func testHouseholdEditFeedback() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"])
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        let cards = app.buttons.matching(identifier: "Change household answers")
        note("Controls labelled 'Change household answers' on the Plan screen: \(cards.count)")
        shot("D01-plan")
        cards.firstMatch.tap()
        sleep(1)
        shot("D02-household-editor")
        let coverage = app.cells.containing(.staticText, identifier: "Coverage").firstMatch
        if coverage.waitForExistence(timeout: 5) {
            coverage.tap()
            sleep(1)
            shot("D03-coverage-options")
            let marketplace = app.buttons["Through the Marketplace"].firstMatch
            if marketplace.waitForExistence(timeout: 3) {
                marketplace.tap()
            } else {
                note("Marketplace option label not matched; options visible: \(app.buttons.allElementsBoundByIndex.map(\.label))")
            }
        }
        let done = app.buttons["Done"]
        if done.exists { done.tap() }
        shotNow("D04-after-done-immediate")
        Thread.sleep(forTimeInterval: 1.0)
        shot("D05-plan-after-edit")
        note("Any banner or alert naming what changed after Done: \(app.alerts.count > 0 || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "added")).count > 0)")
    }

    /// Gathering documents and sending the plan.
    func testDocumentsLoop() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed"])
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.navigationBars["Documents"].waitForExistence(timeout: 5))
        shot("E01-documents")
        let ticks = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mark ")).allElementsBoundByIndex
        note("Visible checklist rows with tick: \(ticks.count)")
        if let first = ticks.first {
            note("First tick frame: \(first.frame.width) x \(first.frame.height); label: \(first.label)")
            first.tap()
            shotNow("E02-after-tick-immediate")
            Thread.sleep(forTimeInterval: 1.0)
            shot("E03-after-tick-settled")
        }
        app.buttons["Photos"].firstMatch.tap()
        sleep(1)
        shot("E04-photos")
        let add = app.buttons["Add a document"].firstMatch
        note("Add a document available on the Photos half: \(add.exists)")
        if add.exists {
            add.tap()
            sleep(2)
            shot("E05-after-add-tap")
        }
    }

    /// Receipts on a task that already has one.
    func testReceiptsAndFollowUp() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed", "-uitest-pro", "-uitest-open-task", "insurance_employer"])
        XCTAssertTrue(app.staticTexts["Why this applies"].exists || app.navigationBars.element(boundBy: 0).waitForExistence(timeout: 20))
        sleep(2)
        shot("F01-insurance-detail")
        let receipt = app.staticTexts["ENR-4471-22"].firstMatch
        let reached = swipesToReach(receipt, in: app, max: 15)
        note("Swipes to reach the saved confirmation number: \(reached.map(String.init) ?? "not reached")")
        shot("F02-receipts")
        if receipt.exists {
            receipt.press(forDuration: 1.2)
            sleep(1)
            shot("F03-long-press-receipt")
            note("Menu with Copy after long-press: \(app.menuItems["Copy"].exists)")
            if app.menuItems.count == 0 { app.tap() }
        }
        let record = app.buttons["Record what came back"]
        if record.exists {
            record.tap()
            sleep(1)
            shot("F04-record-menu")
            let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "number")).firstMatch
            if first.exists { first.tap() } else { note("Receipt kind menu labels: \(app.buttons.allElementsBoundByIndex.map(\.label))") }
            sleep(1)
            shot("F05-receipt-alert")
            let save = app.alerts.buttons["Save"]
            if save.exists {
                save.tap()
                sleep(1)
                note("Empty Save dismissed the alert silently: \(!app.alerts.firstMatch.exists)")
                shot("F06-after-empty-save")
            }
        }
    }

    /// The rebuild control and the Plus tab.
    func testRebuildFeedbackAndPlus() {
        let app = launch(["-uitest-wipe-store", "-uitest-seed", "-uitest-pro"])
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        app.buttons["Plan options"].tap()
        sleep(1)
        shot("G01-plan-menu")
        let rebuild = app.buttons["Rebuild the plan"]
        if rebuild.exists {
            rebuild.tap()
            shotNow("G02-after-rebuild-immediate")
            Thread.sleep(forTimeInterval: 1.0)
            shot("G03-after-rebuild-settled")
        }
        app.tabBars.buttons["Plus"].tap()
        sleep(2)
        shot("G04-plus-owned")
        app.swipeUp()
        shot("G05-plus-owned-scrolled")
        app.tabBars.buttons["Settings"].tap()
        sleep(1)
        shot("G06-settings")
        app.swipeUp()
        shot("G07-settings-scrolled")
    }

    // MARK: - Helpers

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    private func note(_ text: String) {
        notes.append(text)
        print("OBSERVATION: \(text)")
    }

    private func swipesToReach(_ element: XCUIElement, in app: XCUIApplication, max: Int) -> Int? {
        for count in 0...max {
            if element.exists && element.isHittable { return count }
            app.swipeUp()
        }
        return nil
    }

    private func swipeFind(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        swipesToReach(element, in: app, max: 15) != nil
    }

    private func shotNow(_ name: String) {
        attach(name)
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        attach(name)
    }

    private func attach(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
