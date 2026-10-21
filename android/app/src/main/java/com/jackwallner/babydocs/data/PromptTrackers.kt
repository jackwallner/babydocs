package com.jackwallner.babydocs.data

import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.RequirementTask
import java.time.Instant
import java.time.LocalDate

typealias Clock = () -> Instant

const val DAY_MS = 86_400_000L

/**
 * Chooses the moment for Play's in-app review card (`ReviewPromptTracker.swift`).
 * A positive moment is a task with a hard deadline ticked before that deadline
 * closed; two of them plus three launches and three days, then a 120-day
 * cooldown. Nothing is ever asked first and no button triggers it: Google's
 * guidelines forbid both, and so does this app's own rule.
 */
class ReviewPromptTracker(private val defaults: KeyValueStore, private val clock: Clock = Instant::now) {
    var suppressed = false

    val appLaunchCount: Int get() = maxOf(defaults.getInt(LAUNCHES), 0)
    val positiveMomentCount: Int get() = maxOf(defaults.getInt(POSITIVE), 0)
    val hasPendingPositiveMoment: Boolean get() = defaults.getBoolean(PENDING)

    fun recordAppLaunch() {
        if (!defaults.contains(FIRST_OPEN)) defaults.putLong(FIRST_OPEN, clock().toEpochMilli())
        defaults.putInt(LAUNCHES, appLaunchCount + 1)
    }

    fun recordCompletion(task: RequirementTask, today: LocalDate = LocalDate.now()) {
        if (task.deadlineKind != DeadlineKind.HARD) return
        val days = task.daysRemaining(today) ?: return
        if (days < 0) return
        defaults.putInt(POSITIVE, positiveMomentCount + 1)
        defaults.putBoolean(PENDING, true)
    }

    fun cooldownElapsed(): Boolean {
        if (!defaults.contains(LAST_SHOWN)) return true
        return clock().toEpochMilli() - defaults.getLong(LAST_SHOWN) >= COOLDOWN_DAYS * DAY_MS
    }

    fun canRequestReview(): Boolean {
        if (suppressed || !cooldownElapsed()) return false
        if (appLaunchCount < MIN_LAUNCHES || positiveMomentCount < MIN_POSITIVE) return false
        if (!defaults.contains(FIRST_OPEN)) return false
        return clock().toEpochMilli() - defaults.getLong(FIRST_OPEN) >= MIN_DAYS * DAY_MS
    }

    fun shouldRequestAfterPositiveMoment(): Boolean = hasPendingPositiveMoment && canRequestReview()

    fun markRequested() {
        defaults.putLong(LAST_SHOWN, clock().toEpochMilli())
        defaults.putBoolean(PENDING, false)
    }

    companion object {
        const val MIN_LAUNCHES = 3
        const val MIN_DAYS = 3L
        const val MIN_POSITIVE = 2
        const val COOLDOWN_DAYS = 120L
        private const val LAUNCHES = "reviewPrompt.appLaunchCount"
        private const val FIRST_OPEN = "reviewPrompt.firstAppOpenDate"
        private const val LAST_SHOWN = "reviewPrompt.lastShownDate"
        private const val POSITIVE = "reviewPrompt.positiveMomentCount"
        private const val PENDING = "reviewPrompt.pendingPositiveMoment"
    }
}

/** What else may speak, Plus only (`ReminderPreferences.swift`). Both default on. */
class ReminderPreferences(private val defaults: KeyValueStore) {
    var suggestedDateReminders: Boolean
        get() = defaults.getBoolean(SUGGESTED, true)
        set(value) = defaults.putBoolean(SUGGESTED, value)

    var weeklyDigest: Boolean
        get() = defaults.getBoolean(DIGEST, true)
        set(value) = defaults.putBoolean(DIGEST, value)

    private companion object {
        const val SUGGESTED = "babydocs.reminders.suggested"
        const val DIGEST = "babydocs.reminders.digest"
    }
}
