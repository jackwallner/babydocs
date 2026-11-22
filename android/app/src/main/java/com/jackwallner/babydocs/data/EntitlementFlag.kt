package com.jackwallner.babydocs.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Whether the Plus entitlement is active, announcing only a real change
 * (`StoreService.setPro` and `.babyDocsEntitlementChanged` on iOS).
 *
 * The reminder set is built from this answer, so whatever holds the schedule
 * hears about a purchase landing, a lapse or a pending payment being approved
 * the moment it happens, not at the next resume. Hearing the same answer twice
 * is not a change and must not reschedule.
 */
class EntitlementFlag(initial: Boolean, private val onChanged: () -> Unit) {
    var active by mutableStateOf(initial)
        private set

    fun set(value: Boolean) {
        if (value == active) return
        active = value
        onChanged()
    }
}
