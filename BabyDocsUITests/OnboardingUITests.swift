import XCTest

/// The one path that has to work on a phone with nothing on it: launch, get
/// through the intake, and land on a plan.
///
/// Kept deliberately thin. The rules are unit-tested; what a UI test adds is
/// proof that the app launches at all on a clean store, which nothing else
/// covers and which is the failure a shipped build would show every new user.
@MainActor
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

    /// Leave starts with nothing selected, and says so by not letting you past.
    ///
    /// It used to open with a checkmark already sitting on "Nobody is taking
    /// leave", which is an answer nobody gave, and the one answer that removes
    /// the only newborn task that pays the family. "Nobody" is still a real
    /// answer here: it just has to be chosen.
    func testLeaveStepStartsWithNothingChosen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-wipe-store"]
        app.launch()

        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        app.buttons["Get started"].tap()

        XCTAssertTrue(app.navigationBars["Your baby"].waitForExistence(timeout: 5))
        let dateConfirmation = app.switches["I checked this date"].firstMatch
        XCTAssertTrue(dateConfirmation.waitForExistence(timeout: 5))
        dateConfirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tapScrolling(app.buttons["US citizen"].firstMatch, in: app)
        choose(state: "California", labelled: "State of birth", in: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Your household"].waitForExistence(timeout: 5))
        choose(state: "California", labelled: "State you live in", in: app)
        app.buttons["Prefer not to say"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Continue"].firstMatch.isEnabled,
            "Prefer not to say should be an explicit parentage answer"
        )
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Coverage"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["Continue"].firstMatch.isEnabled,
            "Coverage should require an explicit answer, including Not sure yet"
        )
        app.buttons["Not sure yet"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Continue"].firstMatch.isEnabled,
            "Not sure yet should be an explicit coverage answer"
        )
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Leave"].waitForExistence(timeout: 5))
        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.exists)
        XCTAssertFalse(
            continueButton.isEnabled,
            "The leave step let the parent past without ever answering it"
        )

        app.buttons["Nobody is taking leave"].firstMatch.tap()
        XCTAssertTrue(
            continueButton.isEnabled,
            "\"Nobody\" is a real answer and has to open the way forward"
        )
    }

    /// A `Picker` row in a SwiftUI `Form` is a cell containing the label, not a
    /// tappable static text.
    /// Taps something the intake may have pushed under the pinned footer.
    ///
    /// Scrolled clear of the Continue bar rather than merely hittable: the
    /// footer is a safe-area inset the form scrolls beneath, so a row can sit
    /// visually behind it, report itself hittable, and hand the tap to the bar.
    /// That is what made this whole flow fail silently on the citizenship
    /// question, with a red "choose the citizenship" note nobody read.
    private func tapScrolling(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let footer = app.buttons["Continue"].firstMatch
        for _ in 0..<8 {
            let clear = element.exists && element.isHittable
                && (!footer.exists || element.frame.maxY <= footer.frame.minY)
            if clear { break }
            app.swipeUp()
        }
        element.tap()
    }

    private func choose(state: String, labelled label: String, in app: XCUIApplication) {
        let row = app.cells.containing(.staticText, identifier: label).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No picker row labelled \(label)")
        // Every question opens with the same hero block now, so the longest of
        // them puts its last field under the pinned Continue bar.
        tapScrolling(row, in: app)

        let option = app.buttons[state].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "\(state) never appeared in the picker")
        option.tap()
    }
}
