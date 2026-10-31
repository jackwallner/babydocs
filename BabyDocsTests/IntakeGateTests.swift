import Foundation
import Testing

@testable import BabyDocs

/// Who owns the screen at first run: the intake, or the plan.
///
/// The second parent's whole journey runs through here. They install the app,
/// open the link their partner sent, and the plan is built from it while the
/// intake is still on screen behind the confirmation sheet. The intake only
/// ever ended on its own last page, so an imported plan was built and then
/// hidden behind the questions it had made unnecessary, and finishing them made
/// a second copy of the same baby.
@MainActor
struct IntakeGateTests {
    @Test("A plan imported over the first-run intake ends the intake")
    func importedPlanLeavesTheIntake() {
        let navigator = AppNavigator()
        navigator.selectedTab = .settings
        navigator.intakeDidAppear()
        #expect(navigator.isIntakeOpen(activeChildren: 0, archivedChildren: 0))

        // The import wrote a child. Nothing else tells the screen to move on.
        navigator.planWasImported()

        #expect(
            !navigator.isIntakeOpen(activeChildren: 1, archivedChildren: 0),
            "The plan was imported and the first-run questions are still on screen"
        )
        #expect(navigator.selectedTab == .plan)
    }

    @Test("The intake keeps the screen between making the child and reaching its last page")
    func intakeStaysOpenUntilItsOwnLastPage() {
        let navigator = AppNavigator()
        navigator.intakeDidAppear()

        // finish() has written the child, and the plan-is-ready page and the
        // notification prompt have not been seen yet.
        #expect(navigator.isIntakeOpen(activeChildren: 1, archivedChildren: 0))

        navigator.intakeDidFinish()
        #expect(!navigator.isIntakeOpen(activeChildren: 1, archivedChildren: 0))
    }

    @Test("A launch with a plan already in the store never opens the intake")
    func existingPlanSkipsTheIntake() {
        let navigator = AppNavigator()
        #expect(!navigator.isIntakeOpen(activeChildren: 1, archivedChildren: 0))
    }

    @Test("An empty store opens the intake, and an archive alone does not")
    func emptyStoreOpensTheIntake() {
        let navigator = AppNavigator()
        #expect(navigator.isIntakeOpen(activeChildren: 0, archivedChildren: 0))
        #expect(!navigator.isIntakeOpen(activeChildren: 0, archivedChildren: 1))
    }
}
