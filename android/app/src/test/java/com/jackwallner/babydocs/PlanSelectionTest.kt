package com.jackwallner.babydocs

import com.jackwallner.babydocs.rules.PlanSelection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.UUID

/** Port of `TaskPlannerTests.newChildIsNotHiddenByTheFilter`. */
class PlanSelectionTest {
    private val first = UUID.randomUUID()
    private val second = UUID.randomUUID()
    private val third = UUID.randomUUID()

    @Test
    fun aChildArrivingWidensThePlanToEveryoneInsteadOfHidingBehindTheFilter() {
        // One child: selected, so sharing has a target.
        assertEquals(first, PlanSelection.selection(null, emptyList(), listOf(first)))

        // A second child is added, imported or restored.
        assertNull(PlanSelection.selection(first, listOf(first), listOf(first, second)))

        // A choice the parent made survives anything that is not an arrival.
        assertEquals(second, PlanSelection.selection(second, listOf(first, second), listOf(first, second)))
        // A filtered child that is archived leaves the filter.
        assertNull(PlanSelection.selection(third, listOf(first, second, third), listOf(first, second)))
        assertEquals(first, PlanSelection.selection(second, listOf(first, second), listOf(first)))
    }

    @Test
    fun aThirdChildWidensAFilterTheParentChose() {
        assertNull(PlanSelection.selection(second, listOf(first, second), listOf(first, second, third)))
    }

    @Test
    fun theNavigatorFollowsTheChildrenTheStoreHolds() {
        val nav = Navigator()
        nav.liveChildrenChanged(listOf(first))
        assertEquals(first, nav.selectedChildID)

        // The intake sets the selection itself, then the second child arrives.
        nav.liveChildrenChanged(listOf(first, second))
        assertNull(nav.selectedChildID)

        // The parent filters to the second child; nothing arriving means nothing changes.
        nav.selectedChildID = second
        nav.liveChildrenChanged(listOf(first, second))
        assertEquals(second, nav.selectedChildID)

        // A restored or imported child shows up beside the filter.
        nav.liveChildrenChanged(listOf(first, second, third))
        assertNull(nav.selectedChildID)
    }
}
