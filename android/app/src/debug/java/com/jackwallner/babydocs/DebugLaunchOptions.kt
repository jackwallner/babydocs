package com.jackwallner.babydocs

import android.content.Intent
import com.jackwallner.babydocs.data.BabyData
import com.jackwallner.babydocs.data.PackageKind
import com.jackwallner.babydocs.data.PeriodUnit
import com.jackwallner.babydocs.data.Plan
import com.jackwallner.babydocs.data.PlanPeriod
import com.jackwallner.babydocs.data.SampleData

/**
 * Debug-only launch extras, the Android side of the iOS `-uitest-*` launch
 * arguments. None of this is compiled into a release or QA build.
 *
 *     adb shell am start -n com.jackwallner.babydocs/.MainActivity \
 *         --ez resetAll true --ez seed true --ez demoPro true --es tab documents
 *
 * `screen`: paywall, household, sources, timeline, task-<catalogKey>.
 */
object DebugLaunchOptions {
    fun apply(graph: AppGraph, intent: Intent?) {
        val extras = intent?.extras ?: return
        if (extras.getBoolean("uiTest")) graph.review.suppressed = true
        if (extras.getBoolean("resetAll")) {
            graph.defaults.keys().forEach(graph.defaults::remove)
            graph.store.replaceAll(BabyData())
        }
        if (extras.getBoolean("seed")) graph.store.commit { SampleData.seed(it) }
        if (extras.getBoolean("demoPro")) graph.subscriptions.setLocalOverride(true)
        if (extras.getBoolean("previewStore")) graph.subscriptions.loadPreviewPlans(previewPlans(), extras.getBoolean("previewTrialUsed"))
        Tab.entries.firstOrNull { it.name.equals(extras.getString("tab"), ignoreCase = true) }?.let { graph.navigator.tab = it }
        val screen = extras.getString("screen") ?: return
        val nav = graph.navigator
        when {
            screen == "paywall" -> nav.push(Overlay.Paywall("settings"))
            screen == "household" -> nav.push(Overlay.Household)
            screen == "sources" -> nav.push(Overlay.Sources)
            screen == "timeline" -> nav.push(Overlay.Timeline)
            screen.startsWith("task-") -> graph.store.data.allLiveTasks()
                .firstOrNull { it.catalogKey == screen.removePrefix("task-") }
                ?.let { nav.push(Overlay.TaskDetail(it.id)) }
        }
    }

    /** iOS `placeholderPlans` in shape: weekly with a 3-day trial, yearly, lifetime. Local only, no store. */
    private fun previewPlans() = listOf(
        Plan("\$rc_weekly", "com.jackwallner.babydocs.pro.weekly", PackageKind.WEEKLY, 4_990_000, "\$4.99", "USD", PlanPeriod(1, PeriodUnit.WEEK), PlanPeriod(3, PeriodUnit.DAY)),
        Plan("\$rc_annual", "com.jackwallner.babydocs.pro.yearly", PackageKind.YEARLY, 29_990_000, "\$29.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), null),
        Plan("\$rc_lifetime", "com.jackwallner.babydocs.pro.lifetime", PackageKind.LIFETIME, 59_990_000, "\$59.99", "USD", null, null),
    )
}
