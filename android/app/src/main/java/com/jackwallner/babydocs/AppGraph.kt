package com.jackwallner.babydocs

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.babydocs.data.BabyStore
import com.jackwallner.babydocs.data.ConversionDiagnostics
import com.jackwallner.babydocs.data.DeadlineReminderPlanner
import com.jackwallner.babydocs.data.DeadlineReminders
import com.jackwallner.babydocs.data.ReminderPreferences
import com.jackwallner.babydocs.data.ReviewPromptTracker
import com.jackwallner.babydocs.data.SharedPreferencesStore
import com.jackwallner.babydocs.data.SubscriptionService
import com.jackwallner.babydocs.data.VaultStore
import java.io.File
import java.util.UUID

class BabyDocsApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }
}

/** Every long-lived object the screens share, built once per process. */
class AppGraph(context: Context) {
    val appContext: Context = context.applicationContext
    val defaults = SharedPreferencesStore(appContext)
    val store = BabyStore(File(appContext.filesDir, "babydocs-store.json"))
    val diagnostics = ConversionDiagnostics(defaults)
    val subscriptions = SubscriptionService(appContext, defaults, diagnostics)
    val review = ReviewPromptTracker(defaults)
    val reminderPreferences = ReminderPreferences(defaults)
    val reminders = DeadlineReminders(appContext, defaults)
    val vault = VaultStore(appContext)
    val navigator = Navigator()

    /** `DeadlineReminderScheduler.Options.current`: hard windows always, the rest with Plus. */
    val reminderOptions: DeadlineReminderPlanner.Options
        get() {
            val plus = subscriptions.isPro
            return DeadlineReminderPlanner.Options(
                suggestedDates = plus && reminderPreferences.suggestedDateReminders,
                weeklyDigest = plus && reminderPreferences.weeklyDigest,
                customReminders = plus,
            )
        }

    fun rescheduleReminders() = reminders.reschedule(store.data.allLiveTasks(), reminderOptions)
}

enum class Tab(val title: String) { PLAN("Plan"), CHILDREN("Children"), DOCUMENTS("Documents"), PLUS("Plus"), SETTINGS("Settings") }

/** What sits over the tabs, top of the stack last: the iOS sheets and pushed screens. */
sealed interface Overlay {
    data class TaskDetail(val taskID: UUID) : Overlay
    data object Household : Overlay
    data class ChildEditor(val childID: UUID?) : Overlay
    data class Paywall(val placement: String) : Overlay
    data object Sources : Overlay
    data object Timeline : Overlay
    data class SharePlan(val childID: UUID) : Overlay
    data class Export(val childID: UUID, val kind: ExportKind) : Overlay
    data class VaultAdd(val childID: UUID) : Overlay
    data class VaultView(val documentID: UUID) : Overlay
    data object Feedback : Overlay
    data class ImportPlan(val payload: String) : Overlay
}

enum class ExportKind { SUMMARY, PACKET }

class Navigator {
    var tab by mutableStateOf(Tab.PLAN)
    var selectedChildID by mutableStateOf<UUID?>(null)
    val overlays = mutableStateListOf<Overlay>()

    /** Unlocked once per foreground session, like the iOS vault. */
    var vaultUnlocked by mutableStateOf(false)

    /** True while the intake is on screen, including its last two pages after the child exists. */
    var intakeOpen by mutableStateOf(false)

    val top: Overlay? get() = overlays.lastOrNull()

    fun push(overlay: Overlay) {
        if (top != overlay) overlays.add(overlay)
    }

    fun pop() {
        if (overlays.isNotEmpty()) overlays.removeAt(overlays.lastIndex)
    }

    fun remove(overlay: Overlay) {
        overlays.remove(overlay)
    }

    fun openTask(id: UUID) {
        overlays.clear()
        push(Overlay.TaskDetail(id))
    }
}
