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
