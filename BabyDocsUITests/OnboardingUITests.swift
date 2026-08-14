import XCTest

/// The one path that has to work on a phone with nothing on it: launch, get
/// through the intake, and land on a plan.
///
/// Kept deliberately thin. The rules are unit-tested; what a UI test adds is
/// proof that the app launches at all on a clean store, which nothing else
/// covers and which is the failure a shipped build would show every new user.
final class OnboardingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchesToTheIntakeOnACleanStore() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["The paperwork, in order"].waitForExistence(timeout: 10),
            "A clean install should open on the intake, not on an empty plan"
        )
        XCTAssertTrue(app.buttons["Get started"].exists)
        // There is deliberately no second button here. The welcome screen used
        // to offer "I have an invitation", which named a concept the reader had
        // no way to have met yet and pointed at a feature the build could not
        // deliver. A shared plan now arrives as a link and opens its own sheet,
        // so there is nothing to find on this screen.
    }
}
