package com.jackwallner.babydocs.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.FamilyRestroom
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.google.android.play.core.review.ReviewManagerFactory
import com.jackwallner.babydocs.AppGraph
import com.jackwallner.babydocs.MainActivity
import com.jackwallner.babydocs.Overlay
import com.jackwallner.babydocs.Tab
import com.jackwallner.babydocs.ui.screens.ChildEditorScreen
import com.jackwallner.babydocs.ui.screens.ChildrenScreen
import com.jackwallner.babydocs.ui.screens.DocumentsScreen
import com.jackwallner.babydocs.ui.screens.ExportScreen
import com.jackwallner.babydocs.ui.screens.FeedbackScreen
import com.jackwallner.babydocs.ui.screens.HouseholdScreen
import com.jackwallner.babydocs.ui.screens.ImportPlanScreen
import com.jackwallner.babydocs.ui.screens.OnboardingScreen
import com.jackwallner.babydocs.ui.screens.PaywallScreen
import com.jackwallner.babydocs.ui.screens.PlanScreen
import com.jackwallner.babydocs.ui.screens.PlusTab
import com.jackwallner.babydocs.ui.screens.SettingsScreen
import com.jackwallner.babydocs.ui.screens.SharePlanScreen
import com.jackwallner.babydocs.ui.screens.SourcesScreen
import com.jackwallner.babydocs.ui.screens.TaskDetailScreen
import com.jackwallner.babydocs.ui.screens.TimelineScreen
import com.jackwallner.babydocs.ui.screens.VaultAddScreen
import com.jackwallner.babydocs.ui.screens.VaultViewScreen
import com.jackwallner.babydocs.ui.theme.AppTheme

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("No AppGraph") }

@Composable
fun RootScreen(activity: MainActivity) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    graph.store.revision // Recompose on every committed change.
    val hasChild = graph.store.data.liveChildren.isNotEmpty()

    LaunchedEffect(hasChild) { if (!hasChild) nav.intakeOpen = true }

    if (!hasChild || nav.intakeOpen) {
        OnboardingScreen(activity) {
            nav.intakeOpen = false
            nav.tab = Tab.PLAN
        }
        SaveFailureAlert()
        return
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) {
                when (nav.tab) {
                    Tab.PLAN -> PlanScreen()
                    Tab.CHILDREN -> ChildrenScreen()
                    Tab.DOCUMENTS -> DocumentsScreen()
                    Tab.PLUS -> PlusTab()
                    Tab.SETTINGS -> SettingsScreen(activity)
                }
            }
            TabBar()
        }
        nav.overlays.forEach { overlay ->
            // Each overlay swallows touches so nothing underneath reacts.
            Box(
                Modifier.fillMaxSize().background(AppTheme.colors.page)
                    .clickable(interactionSource = remember(overlay), indication = null) {},
            ) { OverlayContent(overlay, activity) }
        }
    }
    BackHandler(enabled = nav.overlays.isNotEmpty()) { nav.pop() }
    BackHandler(enabled = nav.overlays.isEmpty() && nav.tab != Tab.PLAN) { nav.tab = Tab.PLAN }
    SaveFailureAlert()
    ReviewRequester(activity)
}

@Composable
private fun remember(key: Any): MutableInteractionSource = androidx.compose.runtime.remember(key) { MutableInteractionSource() }

@Composable
private fun OverlayContent(overlay: Overlay, activity: MainActivity) {
    when (overlay) {
        is Overlay.TaskDetail -> TaskDetailScreen(overlay.taskID, activity)
        Overlay.Household -> HouseholdScreen()
        is Overlay.ChildEditor -> ChildEditorScreen(overlay.childID)
        is Overlay.Paywall -> PaywallScreen(overlay.placement)
        Overlay.Sources -> SourcesScreen()
        Overlay.Timeline -> TimelineScreen()
        is Overlay.SharePlan -> SharePlanScreen(overlay.childID)
        is Overlay.Export -> ExportScreen(overlay.childID, overlay.kind)
        is Overlay.VaultAdd -> VaultAddScreen(overlay.childID)
        is Overlay.VaultView -> VaultViewScreen(overlay.documentID)
        Overlay.Feedback -> FeedbackScreen()
        is Overlay.ImportPlan -> ImportPlanScreen(overlay.payload)
    }
}

@Composable
private fun TabBar() {
    val nav = LocalGraph.current.navigator
    val c = AppTheme.colors
    NavigationBar(containerColor = c.surface) {
        Tab.entries.forEach { tab ->
            val icon = when (tab) {
                Tab.PLAN -> Icons.Rounded.Checklist
                Tab.CHILDREN -> Icons.Rounded.FamilyRestroom
                Tab.DOCUMENTS -> Icons.Rounded.Folder
                Tab.PLUS -> Icons.Rounded.AutoAwesome
                Tab.SETTINGS -> Icons.Rounded.Settings
            }
            NavigationBarItem(
                selected = nav.tab == tab,
                onClick = { nav.tab = tab; nav.overlays.clear() },
                icon = { Icon(icon, contentDescription = null) },
                label = { Text(tab.title) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = c.accent, selectedTextColor = c.accent, indicatorColor = c.accent.copy(alpha = 0.12f),
                    unselectedIconColor = c.secondary, unselectedTextColor = c.secondary,
                ),
                modifier = Modifier.testTag("tab-${tab.name.lowercase()}"),
            )
        }
    }
}

/** One alert for a write the disk refused, so a tick never looks saved when it was not. */
@Composable
private fun SaveFailureAlert() {
    val store = LocalGraph.current.store
    val message = store.failureMessage ?: return
    AlertDialog(
        onDismissRequest = { store.failureMessage = null },
        title = { Text("Not saved") },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = { store.failureMessage = null }) { Text("OK") } },
    )
}

/** Play's review card with nothing in front of it; the tracker only decides when. */
@Composable
private fun ReviewRequester(activity: MainActivity) {
    val graph = LocalGraph.current
    val revision = graph.store.revision
    LaunchedEffect(revision) {
        if (!graph.review.shouldRequestAfterPositiveMoment()) return@LaunchedEffect
        graph.review.markRequested()
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnSuccessListener { info -> manager.launchReviewFlow(activity, info) }
    }
}
