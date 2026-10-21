package com.jackwallner.babydocs.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.jackwallner.babydocs.BabyDocsApplication
import com.jackwallner.babydocs.MainActivity
import com.jackwallner.babydocs.R
import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.RequirementTask
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters
import java.util.UUID

/**
 * What the app says before a date arrives (`DeadlineReminderScheduler.swift`).
 * The two hard windows warn 7 days and 1 day out at 9am, free forever, and
 * claim the pending budget first. Suggested dates (3 days out), the Sunday
 * digest and the parent's own reminders are Plus and opt-in.
 */
object DeadlineReminderPlanner {
    const val MAX_SCHEDULED = 24
    val LEAD_DAYS = listOf(7, 1)
    val SUGGESTED_LEAD_DAYS = listOf(3)
    const val DIGEST_WEEKS = 4

    data class Plan(
        val identifier: String,
        val title: String,
        val body: String,
        val fireAt: ZonedDateTime,
        val taskID: UUID?,
        val isHardDeadline: Boolean = false,
    )

    data class Options(val suggestedDates: Boolean = false, val weeklyDigest: Boolean = false, val customReminders: Boolean = false) {
        companion object {
            val HARD_DEADLINES_ONLY = Options()
        }
    }

    fun plans(tasks: List<RequirementTask>, now: ZonedDateTime, options: Options = Options.HARD_DEADLINES_ONLY): List<Plan> {
        val live = tasks.filter { it.isOpen && it.deletedAt == null }
        val hard = mutableListOf<Plan>()
        val optional = mutableListOf<Plan>()
        for (task in live) {
            val due = task.dueAt ?: continue
            when {
                task.deadlineKind == DeadlineKind.HARD -> for (lead in LEAD_DAYS) {
                    val fireAt = due.minusDays(lead.toLong()).atTime(MORNING).atZone(now.zone)
                    if (!fireAt.isAfter(now)) continue
                    hard += Plan(
                        "deadline.${task.id.toString().uppercase()}.$lead",
                        if (lead == 1) "Last day tomorrow" else "$lead days left",
                        "A hard enrollment window closes soon. Open Baby Docs for the task and official details.",
                        fireAt, task.id, isHardDeadline = true,
                    )
                }
                task.deadlineKind == DeadlineKind.RECOMMENDED && options.suggestedDates -> for (lead in SUGGESTED_LEAD_DAYS) {
                    val fireAt = due.minusDays(lead.toLong()).atTime(MORNING).atZone(now.zone)
                    if (!fireAt.isAfter(now)) continue
                    optional += Plan(
                        "suggested.${task.id.toString().uppercase()}.$lead",
                        "Suggested this week",
                        "Baby Docs has a suggested task for this week. It is not a legal deadline. Open the app for details.",
                        fireAt, task.id,
                    )
                }
            }
        }
        if (options.customReminders) {
            for (task in live) {
                val asked = task.customReminderAt ?: continue
                val fireAt = Instant.ofEpochMilli(asked).atZone(now.zone).toLocalDate().atTime(MORNING).atZone(now.zone)
                if (!fireAt.isAfter(now)) continue
                optional += Plan(
                    "custom.${task.id.toString().uppercase()}",
                    "You asked to be reminded",
                    "Open Baby Docs to see the task you asked about.",
                    fireAt, task.id,
                )
            }
        }
        if (options.weeklyDigest) optional += digests(live, now)

        val keptHard = hard.sortedBy { it.fireAt }.take(MAX_SCHEDULED)
        val budget = maxOf(0, MAX_SCHEDULED - keptHard.size)
        val keptOptional = optional.sortedBy { it.fireAt }.take(budget)
        return (keptHard + keptOptional).sortedBy { it.fireAt }
    }

    /** One Sunday-morning message per week that holds something, and silence on a week that holds nothing. */
    fun digests(tasks: List<RequirementTask>, now: ZonedDateTime): List<Plan> {
        val plans = mutableListOf<Plan>()
        var cursor = now
        repeat(DIGEST_WEEKS) {
            val sunday = nextSundayMorning(cursor)
            cursor = sunday
            val start = sunday.toLocalDate()
            val end = start.plusDays(7)
            val due = tasks.filter { t -> t.isOpen && t.dueAt?.let { !it.isBefore(start) && it.isBefore(end) } == true }
            if (due.isNotEmpty()) {
                plans += Plan("digest.${sunday.toEpochSecond()}", "This week's paperwork", digestBody(due), sunday, null)
            }
        }
        return plans
    }

    fun digestBody(due: List<RequirementTask>): String {
        val hardCount = due.count { it.deadlineKind == DeadlineKind.HARD }
        if (due.size == 1) {
            return if (hardCount > 0) {
                "One real enrollment window closes this week. Open Baby Docs for details."
            } else {
                "One suggested task reaches its date this week. It is not a legal deadline. Open Baby Docs for details."
            }
        }
        if (hardCount == 0) return "${due.size} things reach their date this week. None of them is a legal deadline."
        val verb = if (hardCount == 1) "is a real window" else "are real windows"
        return "${due.size} things reach their date this week. $hardCount of them $verb closing."
    }

    private fun nextSundayMorning(after: ZonedDateTime): ZonedDateTime {
        val sameDay = after.toLocalDate().atTime(MORNING).atZone(after.zone)
        if (after.dayOfWeek == DayOfWeek.SUNDAY && sameDay.isAfter(after)) return sameDay
        return after.toLocalDate().with(TemporalAdjusters.next(DayOfWeek.SUNDAY)).atTime(MORNING).atZone(after.zone)
    }

    private val MORNING: LocalTime = LocalTime.of(9, 0)
}

/** Schedules the planner's output with inexact alarms; no exact-alarm permission needed. */
class DeadlineReminders(private val context: Context, private val defaults: KeyValueStore) {
    fun hasPermission(): Boolean = Companion.hasPermission(context)

    fun reschedule(tasks: List<RequirementTask>, options: DeadlineReminderPlanner.Options) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        defaults.getStringSet(SCHEDULED).forEach { alarms.cancel(pendingIntent(context, it, null)) }
        if (!hasPermission()) {
            defaults.putStringSet(SCHEDULED, emptySet())
            return
        }
        val plans = DeadlineReminderPlanner.plans(tasks, ZonedDateTime.now(ZoneId.systemDefault()), options)
        plans.forEach { plan ->
            alarms.setWindow(AlarmManager.RTC_WAKEUP, plan.fireAt.toInstant().toEpochMilli(), WINDOW_MS, pendingIntent(context, plan.identifier, plan))
        }
        defaults.putStringSet(SCHEDULED, plans.map { it.identifier }.toSet())
    }

    companion object {
        const val CHANNEL_ID = "deadlines"
        const val EXTRA_TASK = "babydocs.taskID"
        private const val SCHEDULED = "babydocs.reminders.scheduled"
        private const val WINDOW_MS = 15 * 60_000L

        fun hasPermission(context: Context): Boolean = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

        private fun pendingIntent(context: Context, identifier: String, plan: DeadlineReminderPlanner.Plan?): PendingIntent {
            val intent = Intent(context, DeadlineReminderReceiver::class.java).setAction("babydocs.reminder.$identifier")
            if (plan != null) {
                intent.putExtra("id", plan.identifier).putExtra("title", plan.title).putExtra("body", plan.body)
                plan.taskID?.let { intent.putExtra(EXTRA_TASK, it.toString()) }
            }
            return PendingIntent.getBroadcast(context, identifier.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun post(context: Context, identifier: String, title: String, body: String, taskID: String?) {
            if (!hasPermission(context)) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, context.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_DEFAULT),
            )
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            taskID?.let { open.putExtra(EXTRA_TASK, it) }
            val content = PendingIntent.getActivity(context, identifier.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(content)
                .setAutoCancel(true)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(identifier.hashCode(), notification)
            } catch (_: SecurityException) {
                // Permission revoked between the check and the post.
            }
        }
    }
}

class DeadlineReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        DeadlineReminders.post(
            context, id,
            intent.getStringExtra("title").orEmpty(),
            intent.getStringExtra("body").orEmpty(),
            intent.getStringExtra(DeadlineReminders.EXTRA_TASK),
        )
    }
}

class DeadlineReminderRescheduler : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in RESCHEDULE_ACTIONS) return
        (context.applicationContext as BabyDocsApplication).graph.rescheduleReminders()
    }
}

private val RESCHEDULE_ACTIONS = setOf(
    Intent.ACTION_BOOT_COMPLETED,
    Intent.ACTION_MY_PACKAGE_REPLACED,
    Intent.ACTION_TIMEZONE_CHANGED,
    Intent.ACTION_TIME_CHANGED,
)
