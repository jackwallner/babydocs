package com.jackwallner.babydocs

import com.jackwallner.babydocs.data.EntitlementFlag
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `PlusTierTests.entitlementChangeAnnouncesItself`. */
class EntitlementFlagTest {
    @Test
    fun buyingOrLosingPlusTellsTheReminderScheduleToRebuild() {
        var announced = 0
        val flag = EntitlementFlag(initial = false) { announced += 1 }

        flag.set(true)
        assertTrue(flag.active)
        assertEquals(1, announced)

        // The same answer twice is not a change, and must not reschedule.
        flag.set(true)
        assertEquals(1, announced)

        flag.set(false)
        assertFalse(flag.active)
        assertEquals(2, announced)
    }

    @Test
    fun theCachedAnswerAtLaunchIsNotAnAnnouncement() {
        var announced = 0
        val flag = EntitlementFlag(initial = true) { announced += 1 }
        assertTrue(flag.active)
        // The store confirming what the cache said changes nothing.
        flag.set(true)
        assertEquals(0, announced)
    }
}
