package com.jackwallner.babydocs.rules

import java.util.UUID

/** Which child the Plan tab is filtered to (`PlanView.selection` on iOS). */
object PlanSelection {
    /**
     * Which child the plan is filtered to after the set of children changes.
     *
     * A lone child is selected so sharing has a target. A child arriving
     * (added, imported or restored) widens the view to everyone: the filter
     * was the app's choice while there was one child, and keeping it hid the
     * newcomer's whole plan, hard deadlines included, behind a picker.
     */
    fun selection(current: UUID?, old: List<UUID>, new: List<UUID>): UUID? {
        if (new.size == 1) return new.first()
        if (new.size > old.size) return null
        if (current == null || current !in new) return null
        return current
    }
}
