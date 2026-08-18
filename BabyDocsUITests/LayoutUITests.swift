import XCTest

/// The layout facts that are cheap to break and expensive to notice.
///
/// The tab bar floats over the scroll content, so "is the last row reachable"
/// is a real question rather than a pedantic one: the last thing on a task
/// detail is the source footnote, and the whole promise of the app is that a
/// parent can check where a date came from.
final class LayoutUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTheLastControlOnATaskDetailClearsTheTabBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store", "-uitest-seed"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 15))

        let row = app.staticTexts["Order certified copies of the birth certificate"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["Suggested by"].waitForExistence(timeout: 5))

        let footnote = app.staticTexts["Where this comes from"]
        for _ in 0..<8 where !footnote.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(footnote.isHittable, "The source footnote never became reachable")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertLessThanOrEqual(
            footnote.frame.maxY,
            tabBar.frame.minY,
            "The last control on the task detail sits under the tab bar"
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
        for _ in 0..<10 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(what) never became reachable", file: file, line: line)

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, file: file, line: line)
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
        assertClearsTabBar(app.buttons["Support"], in: app, "The last link in Settings")
    }

    func testDocumentsLastControlClearsTheTabBar() {
        let app = launchSeeded()
        app.tabBars.buttons["Documents"].tap()
        XCTAssertTrue(app.navigationBars["Documents"].waitForExistence(timeout: 10))
        assertClearsTabBar(
            app.buttons["Add a document"].firstMatch,
            in: app,
            "The last control on Documents"
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
