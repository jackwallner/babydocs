package com.jackwallner.babydocs.rules

import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.RequirementTask
import com.jackwallner.babydocs.model.toLocalDate
import java.text.Collator
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID

/** Bucketing, sorting, the overview and the one place a deadline is phrased (`TaskPlanner.swift`). */
object TaskPlanner {
    enum class Bucket(val title: String, val blurb: String) {
        OVERDUE("Past due", "Check whether the window has actually closed before assuming it has."),
        THIS_WEEK("Next 7 days", "The ones with a clock on them."),
        THIS_MONTH("Next 31 days", "Coming up, not urgent yet."),
        LATER("Later", "Scheduled further out."),
        WHENEVER("No deadline", "Worth doing, no date attached."),
        DONE("Done", ""),
    }

    /** `.inPlace` for the screen, `.ownBucket` for the exporter. */
    enum class CompletedPlacement { OWN_BUCKET, IN_PLACE }

    fun buckets(
        tasks: List<RequirementTask>,
        today: LocalDate = LocalDate.now(),
        completed: CompletedPlacement = CompletedPlacement.OWN_BUCKET,
    ): List<Pair<Bucket, List<RequirementTask>>> {
        val grouped = tasks.filter { it.deletedAt == null }.groupBy { bucket(it, today, completed) }
        return Bucket.entries.mapNotNull { b -> grouped[b]?.takeIf { it.isNotEmpty() }?.let { b to sorted(it) } }
    }

    fun bucket(task: RequirementTask, today: LocalDate = LocalDate.now(), completed: CompletedPlacement = CompletedPlacement.OWN_BUCKET): Bucket {
        if (task.isDismissed) return Bucket.DONE
        if (task.isDone) {
            if (completed != CompletedPlacement.IN_PLACE) return Bucket.DONE
            // Bucketed as of the moment it was ticked, not as of today.
            return bucketOf(task, task.completedAt?.toLocalDate() ?: today)
        }
        return bucketOf(task, today)
    }

    private fun bucketOf(task: RequirementTask, asOf: LocalDate): Bucket {
        val days = task.daysRemaining(asOf) ?: return Bucket.WHENEVER
        return when {
            days < 0 -> Bucket.OVERDUE
            days <= 7 -> Bucket.THIS_WEEK
            days <= 31 -> Bucket.THIS_MONTH
            else -> Bucket.LATER
        }
    }

    private val collator: Collator = Collator.getInstance().apply { strength = Collator.SECONDARY }

    val taskOrder: Comparator<RequirementTask> = Comparator { left, right ->
        val l = left.dueAt
        val r = right.dueAt
        when {
            l != null && r != null && l != r -> l.compareTo(r)
            l == null && r != null -> 1
            l != null && r == null -> -1
            left.sortWeight != right.sortWeight -> left.sortWeight.compareTo(right.sortWeight)
            else -> collator.compare(left.title, right.title)
        }
    }

    fun sorted(tasks: List<RequirementTask>): List<RequirementTask> = tasks.sortedWith(taskOrder)

    data class Overview(
        var openCount: Int = 0,
        var doneCount: Int = 0,
        var overdueCount: Int = 0,
        var hardDeadlineCount: Int = 0,
        var nextHardDeadline: LocalDate? = null,
        var nextHardDeadlineTitle: String? = null,
        var nextHardDeadlineID: UUID? = null,
        var pastHardDeadline: LocalDate? = null,
        var pastHardDeadlineTitle: String? = null,
        var pastHardDeadlineID: UUID? = null,
    ) {
        val hasPastHardDeadline: Boolean get() = pastHardDeadlineID != null
        val totalCount: Int get() = openCount + doneCount
        val progress: Double get() = if (totalCount == 0) 0.0 else doneCount.toDouble() / totalCount
    }

    fun overview(tasks: List<RequirementTask>, today: LocalDate = LocalDate.now()): Overview {
        val overview = Overview()
        var soonest: RequirementTask? = null
        var past: RequirementTask? = null
        for (task in tasks.filter { it.deletedAt == null }) {
            if (task.isDismissed) continue
            if (task.isDone) {
                overview.doneCount += 1
                continue
            }
            overview.openCount += 1
            val days = task.daysRemaining(today)
            if (days != null && days < 0) overview.overdueCount += 1
            val due = task.dueAt
            if (task.deadlineKind != DeadlineKind.HARD || due == null || days == null) continue
            if (days < 0) {
                val current = past?.dueAt
                if (current != null && current <= due) continue
                past = task
            } else {
                overview.hardDeadlineCount += 1
                val current = soonest?.dueAt
                if (current != null && current <= due) continue
                soonest = task
            }
        }
        overview.nextHardDeadline = soonest?.dueAt
        overview.nextHardDeadlineTitle = soonest?.title
        overview.nextHardDeadlineID = soonest?.id
        overview.pastHardDeadline = past?.dueAt
        overview.pastHardDeadlineTitle = past?.title
        overview.pastHardDeadlineID = past?.id
        return overview
    }

    /** The word, not just the colour: a suggestion says it is one. */
    fun duePhrase(task: RequirementTask, today: LocalDate = LocalDate.now()): String {
        val days = task.daysRemaining(today)
            ?: return if (task.deadlineKind == DeadlineKind.NONE) "No deadline" else "Date depends on your plan"
        val phrase = when {
            days < -1 -> "${-days} days past due"
            days == -1 -> "1 day past due"
            days == 0 -> "Due today"
            days == 1 -> "Due tomorrow"
            days in 2..13 -> "$days days left"
            else -> "Due ${task.dueAt?.let { dayPhrase(it, today) }.orEmpty()}"
        }
        return if (task.deadlineKind == DeadlineKind.RECOMMENDED) "Suggested · $phrase" else phrase
    }

    fun dayPhrase(date: LocalDate, today: LocalDate = LocalDate.now(), locale: Locale = Locale.getDefault()): String {
        val pattern = if (date.year == today.year) "MMM d" else "MMM d, yyyy"
        return date.format(DateTimeFormatter.ofPattern(pattern, locale))
    }

    fun deadlineLine(date: LocalDate, today: LocalDate = LocalDate.now(), locale: Locale = Locale.getDefault()): String {
        val weekday = date.dayOfWeek.getDisplayName(TextStyle.FULL, locale)
        val days = ChronoUnit.DAYS.between(today, date).toInt()
        val remaining = when {
            days < -1 -> "${-days} days past due"
            days == -1 -> "1 day past due"
            days == 0 -> "today"
            days == 1 -> "tomorrow"
            else -> "$days days left"
        }
        return "$weekday, ${dayPhrase(date, today, locale)} · $remaining"
    }
}

/** The same tasks read as an order rather than as dates. The app's own opinion (`PlanTimeline.swift`). */
object PlanTimeline {
    enum class Phase(val title: String, val blurb: String) {
        NOW("Start this week", "Everything with a door closing on it, and everything that is only slow because somebody else has to post it back."),
        SOON("The week after", "Nothing here is urgent this minute. It is next, so that the week after the birth is not a blank page."),
        LATER("When things calm down", "Real tasks with no clock on them. Left here on purpose so they are not competing with the ones that close."),
        BLOCKED("Waiting on something else", "There is nothing you can do on these today. They open on their own once the thing they wait for arrives."),
        DONE("Handled", "Ticked off."),
    }

    data class Step(
        val taskID: UUID,
        val title: String,
        val phase: Phase,
        val reason: String,
        val isBlocked: Boolean,
        val isDone: Boolean,
        val dueAt: LocalDate?,
        val deadlineKind: DeadlineKind,
    )

    data class Group(val phase: Phase, val steps: List<Step>)

    fun groups(tasks: List<RequirementTask>, birthDateOf: (RequirementTask) -> LocalDate?, today: LocalDate = LocalDate.now()): List<Group> {
        val live = tasks.filter { it.deletedAt == null && !it.isDismissed }
        val completedKeys = live.filter { it.isDone }.map { it.catalogKey }.toSet()
        val byPhase = live.map { step(it, completedKeys, birthDateOf(it), today) }.groupBy { it.phase }
        return Phase.entries.mapNotNull { phase ->
            byPhase[phase]?.takeIf { it.isNotEmpty() }?.let { Group(phase, it.sortedWith(order)) }
        }
    }

    fun step(task: RequirementTask, completedKeys: Set<String>, birthDate: LocalDate?, today: LocalDate = LocalDate.now()): Step {
        val advice = RequirementCatalog.rule(task.catalogKey)?.start ?: StartAdvice.StraightAway
        var phase = Phase.NOW
        var reason = ""
        var isBlocked = false
        when {
            task.isDone -> phase = Phase.DONE
            task.deadlineKind == DeadlineKind.HARD -> {
                phase = Phase.NOW
                reason = "A window closes on this one, so it goes first whatever else is happening."
            }
            else -> when (advice) {
                StartAdvice.StraightAway -> phase = if (task.isPostedAway) Phase.NOW else Phase.SOON
                is StartAdvice.AfterDays -> {
                    val ready = (birthDate ?: today).plusDays(advice.days.toLong())
                    val daysAway = ChronoUnit.DAYS.between(today, ready)
                    phase = if (daysAway <= 0) Phase.NOW else if (daysAway <= 7) Phase.SOON else Phase.LATER
                    reason = advice.because
                }
                is StartAdvice.After -> if (advice.key in completedKeys) {
                    phase = Phase.NOW
                    reason = "${advice.because} That has arrived, so this one is open."
                } else {
                    phase = Phase.BLOCKED
                    isBlocked = true
                    reason = advice.because
                }
            }
        }
        return Step(task.id, task.title, phase, reason, isBlocked, task.isDone, task.dueAt, task.deadlineKind)
    }

    fun openNowCount(tasks: List<RequirementTask>, birthDateOf: (RequirementTask) -> LocalDate?, today: LocalDate = LocalDate.now()): Int =
        groups(tasks, birthDateOf, today).firstOrNull { it.phase == Phase.NOW }?.steps?.count { !it.isDone } ?: 0

    private val collator: Collator = Collator.getInstance().apply { strength = Collator.SECONDARY }

    private val order = Comparator<Step> { left, right ->
        val l = left.dueAt
        val r = right.dueAt
        when {
            left.isDone != right.isDone -> if (right.isDone) -1 else 1
            l != null && r != null && l != r -> l.compareTo(r)
            l == null && r != null -> 1
            l != null && r == null -> -1
            else -> collator.compare(left.title, right.title)
        }
    }
}
