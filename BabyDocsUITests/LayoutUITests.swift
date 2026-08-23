import XCTest

/// The layout facts that are cheap to break and expensive to notice.
///
/// The tab bar floats over the scroll content, so "is the last row reachable"
/// is a real question rather than a pedantic one: the last thing on a task
/// detail is the source footnote, and the whole promise of the app is that a
/// parent can check where a date came from.
@MainActor
final class LayoutUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTheLastControlOnATaskDetailClearsTheTabBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))

        let row = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "Order certified copies of the birth certificate"
            )
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["Timing"].waitForExistence(timeout: 5))

        let footnote = app.staticTexts["Where this comes from"]
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<12 {
            guard footnote.exists else {
                app.swipeUp()
                continue
            }
            guard footnote.frame.maxY > tabBar.frame.minY else { break }
            app.swipeUp()
        }

        XCTAssertTrue(footnote.isHittable, "The source footnote never became reachable")

        XCTAssertTrue(tabBar.exists)
        XCTAssertLessThanOrEqual(
            footnote.frame.maxY,
            tabBar.frame.minY,
            "The last control on the task detail sits under the tab bar"
        )
    }

    /// The same question as the test above, at the largest text size there is.
    ///
    /// It opens the task by launch argument rather than by scrolling to it. The
    /// scroll hunt was not incidental: at accessibility XXXL the plan is many
    /// screens long, so finding one row took twenty swipes on a good run and ran
    /// out of budget on a bad one, and a test that fails because it could not
    /// find a row reports a layout failure that is not one. It failed that way
    /// on this branch and on `main` alike, for nine minutes at a time, which is
    /// how long it takes for a red suite to stop being read.
    ///
    /// What this test is *for* is the last element on the task detail: the
    /// source footnote, the one thing carrying the app's claim to be checkable,
    /// and whether it clears the floating tab bar when every glyph on screen is
    /// three times its usual size.
    func testAccessibilityTextKeepsTaskSourceReachable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-wipe-store",
            "-uitest-seed",
            "-uitest-open-task",
            "birth_certificate",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Birth certificate"].waitForExistence(timeout: 20),
            "The task detail never opened from the launch argument"
        )
        assertSourceClearsTabBar(app)
    }

    private func assertSourceClearsTabBar(_ app: XCUIApplication) {
        let footnote = app.staticTexts["Where this comes from"]
        let sourceEnd = app.staticTexts["source-limitations"]
        let tabBar = app.tabBars.firstMatch
        // Twelve swipes was the budget, and at accessibility XXXL the task
        // detail is far longer than twelve swipes: the assertion was failing on
        // a screen where the footnote was reachable, just further down than the
        // loop was willing to go. A budget for the *largest* text size is what
        // this test needs, because that is the size it exists to check.
        for _ in 0..<30 {
            guard sourceEnd.exists else {
                app.swipeUp()
                continue
            }
            guard sourceEnd.frame.maxY > tabBar.frame.minY else { break }
            app.swipeUp()
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "accessibility-bottom-of-task"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(footnote.exists, "The source footnote never became reachable at large text")
        XCTAssertTrue(sourceEnd.exists, "The source limitations never became reachable at large text")
        XCTAssertLessThanOrEqual(
            sourceEnd.frame.maxY,
            tabBar.frame.minY,
            "The end of the source footnote sits under the floating tab bar at large text"
        )
    }
}

// MARK: - The rest of the app

/// The same question as `LayoutUITests`, asked on every root tab.
///
/// One screen was covered and six were not, and all six were broken: the audit
/// that found this saw the last interactive control clipped on Plan, Documents,
/// Settings, the task detail and the child detail at once, because they all
/// share one inset constant and the constant was the height of the tab bar's
/// glyph rather than of the bar. A single-screen assertion cannot catch a
/// mistake in a shared constant, because it passes the moment one screen
/// happens to be short enough.
@MainActor
final class TabBarClearanceUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))
        return app
    }

    /// Scrolls until the element is on screen, then asserts it clears the bar.
    private func assertClearsTabBar(
        _ element: XCUIElement,
        in app: XCUIApplication,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, file: file, line: line)
        // Scrolled until it clears the bar, not until it is merely hittable.
        // A row can report itself hittable while its last few points sit under
        // the glass, so stopping at the first `isHittable` made this assertion
        // depend on how long the page above it happened to be, and it failed
        // the day a paragraph in Settings got two lines longer.
        for _ in 0..<12 {
            // A row far down a long list does not exist as an element until it
            // has been scrolled near, so "does not exist yet" has to keep the
            // loop going rather than end it.
            guard element.exists else {
                app.swipeUp()
                continue
            }
            let frame = element.frame
            let reachable = element.isHittable
                && frame.height > 0
                && frame.maxY <= tabBar.frame.minY
            if reachable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(what) never became reachable", file: file, line: line)
        XCTAssertLessThanOrEqual(
            element.frame.maxY,
            tabBar.frame.minY,
            "\(what) sits under the floating tab bar",
            file: file,
            line: line
        )
    }

    func testSettingsLastLinkClearsTheTabBar() {
        let app = launchSeeded()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let support = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Support"))
            .firstMatch
        assertClearsTabBar(support, in: app, "The last link in Settings")
    }

    func testDocumentsLastControlClearsTheTabBar() {
        let app = launchSeeded()
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.navigationBars["Documents"].waitForExistence(timeout: 10))
        // The tab is two screens behind a switch now: a checklist of what to
        // take to each errand, and the photographs. "Add a document" is the last
        // control of the second one.
        app.buttons["Photos"].firstMatch.tap()
        assertClearsTabBar(
            app.buttons["Add a document"].firstMatch,
            in: app,
            "The last control on Documents"
        )
    }

    func testDocumentsChecklistLastItemClearsTheTabBar() {
        let app = launchSeeded()
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.navigationBars["Documents"].waitForExistence(timeout: 10))
        assertClearsTabBar(
            app.staticTexts["The per-copy fee"].firstMatch,
            in: app,
            "The last checklist item on Documents"
        )
    }

    func testPlanShowsHouseholdAnswersOutsideTheOptionsMenu() {
        let app = launchSeeded()
        XCTAssertTrue(app.buttons["Change household answers"].waitForExistence(timeout: 10))
    }

    /// Adding a second baby is free, and this is the assertion that keeps it
    /// that way. Twins are one birth and one household: charging for the second
    /// child billed the family that had the harder delivery.
    func testAddingASecondChildIsNotPaywalled() {
        let app = launchSeeded()
        app.tabBars.buttons["Children"].tap()
        XCTAssertTrue(app.navigationBars["Children"].waitForExistence(timeout: 10))
        app.buttons["Add another child"].tap()

        XCTAssertFalse(
            app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 3),
            "Adding a further child must never open the paywall"
        )
    }

    func testPlusTabPurchaseButtonClearsTheTabBar() {
        let app = launchSeeded()
        app.tabBars.buttons["Plus"].tap()
        XCTAssertTrue(app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 10))

        let restore = app.buttons["Restore purchases"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        let tabBar = app.tabBars.firstMatch
        XCTAssertLessThanOrEqual(
            restore.frame.maxY,
            tabBar.frame.minY,
            "The purchase bar on the Plus tab sits under the floating tab bar"
        )
    }

    /// The other half of the Plus tab: what a customer who has paid sees there.
    /// The offer and the tools share one slot in the bar, so both halves have to
    /// be looked at, and the timeline is the part that carries the pitch.
    func testPlusToolsShowTheTimelineAndClearTheTabBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed", "-uitest-pro"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))

        app.tabBars.buttons["Plus"].tap()
        XCTAssertTrue(app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["Start this week"].waitForExistence(timeout: 10),
            "The timeline never rendered for a customer who has Plus"
        )
        XCTAssertFalse(
            app.buttons["Start my free trial"].exists,
            "A customer who has paid is still being sold to"
        )
        assertClearsTabBar(
            app.buttons["Restore purchases"].firstMatch,
            in: app,
            "The last control on the Plus tools"
        )
    }

    func testChildDetailShareFooterClearsTheTabBar() {
        let app = launchSeeded()
        app.tabBars.buttons["Children"].tap()
        XCTAssertTrue(app.navigationBars["Children"].waitForExistence(timeout: 10))
        let childRow = app.staticTexts["Rosa"]
        XCTAssertTrue(childRow.waitForExistence(timeout: 10))
        childRow.tap()
        XCTAssertTrue(app.navigationBars["Rosa"].waitForExistence(timeout: 10))
        assertClearsTabBar(
            app.buttons["Send or print this plan"],
            in: app,
            "The share footer on the child detail"
        )
    }
}

@MainActor
final class ArchiveRecoveryUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testArchivingTheOnlyChildOffersRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Children"].tap()
        XCTAssertTrue(app.navigationBars["Children"].waitForExistence(timeout: 10))

        app.staticTexts["Rosa"].tap()
        XCTAssertTrue(app.navigationBars["Rosa"].waitForExistence(timeout: 10))
        app.buttons["Edit details"].tap()
        XCTAssertTrue(app.buttons["Archive this child"].waitForExistence(timeout: 10))
        app.buttons["Archive this child"].tap()
        let confirmation = app.sheets.buttons["Archive this child"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()

        XCTAssertTrue(app.staticTexts["This child is archived"].waitForExistence(timeout: 10))
        app.buttons["Restore Rosa"].tap()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 10))
    }
}

@MainActor
final class PaywallLayoutUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testBenefitsNeverHideBehindPurchaseBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))
        // The pitch is a tab of its own now rather than only a locked door, so
        // this is the route somebody takes when they are choosing to read it.
        app.tabBars.buttons["Plus"].tap()
        XCTAssertTrue(app.navigationBars["Baby Docs Plus"].waitForExistence(timeout: 10))

        let lastBenefit = app.staticTexts["Free, and staying free"]
        let purchaseButton = app.buttons["Start my free trial"]
        XCTAssertTrue(lastBenefit.waitForExistence(timeout: 10))
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 10))

        for _ in 0..<10 where !lastBenefit.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(lastBenefit.isHittable, "The last Plus benefit is not reachable")
        XCTAssertLessThanOrEqual(
            lastBenefit.frame.maxY,
            purchaseButton.frame.minY,
            "The last Plus benefit is hidden behind the purchase bar"
        )
    }
}
