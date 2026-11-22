package com.jackwallner.babydocs

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the guard for iOS `AppNavigator.planWasImported` (`IntakeGateTests`). */
class IntakeImportTest {
    @Test
    fun importingASharedPlanEndsTheFirstRunIntake() {
        val nav = Navigator()
        // A fresh install: the intake owns the screen and the link's confirmation is pushed over it.
        nav.intakeOpen = true
        nav.push(Overlay.ImportPlan("babydocs://plan?d=x"))

        nav.planWasImported()

        // The import wrote the child and built the plan, so the questions have nothing left to ask.
        assertFalse(nav.intakeOpen)
        assertEquals(Tab.PLAN, nav.tab)
        assertTrue(nav.overlays.isEmpty())
    }

    @Test
    fun importingFromAnotherTabLandsOnThePlan() {
        val nav = Navigator()
        nav.tab = Tab.SETTINGS
        nav.push(Overlay.ImportPlan("babydocs://plan?d=x"))
        nav.planWasImported()
        assertEquals(Tab.PLAN, nav.tab)
    }
}
