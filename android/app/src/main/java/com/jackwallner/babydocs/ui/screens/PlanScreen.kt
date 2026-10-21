package com.jackwallner.babydocs.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Error
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.jackwallner.babydocs.AppGraph
import com.jackwallner.babydocs.ExportKind
import com.jackwallner.babydocs.Overlay
import com.jackwallner.babydocs.model.RequirementTask
import com.jackwallner.babydocs.rules.TaskPlanner
import com.jackwallner.babydocs.ui.LocalGraph
import com.jackwallner.babydocs.ui.theme.AppTheme
import com.jackwallner.babydocs.ui.theme.Card
import com.jackwallner.babydocs.ui.theme.ChoiceRow
import com.jackwallner.babydocs.ui.theme.DuePill
import com.jackwallner.babydocs.ui.theme.Footnote
import com.jackwallner.babydocs.ui.theme.Page
import com.jackwallner.babydocs.ui.theme.RowDivider
import com.jackwallner.babydocs.ui.theme.SectionHeader
import com.jackwallner.babydocs.ui.theme.Type
import com.jackwallner.babydocs.ui.theme.icon
import java.util.UUID

/** Ticks or unticks a task, records the review moment, and writes. */
fun AppGraph.toggle(task: RequirementTask) {
    val completing = !task.isDone
    store.commit {
        task.setCompleted(completing)
        task.updatedAt = System.currentTimeMillis()
    }
    if (completing) review.recordCompletion(task)
    rescheduleReminders()
}

@Composable
fun PlanScreen() {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val data = graph.store.data
    graph.store.revision
    val children = data.liveChildren
    var selected by rememberSaveable { mutableStateOf<String?>(nav.selectedChildID?.toString()) }
    val selectedChild = children.firstOrNull { it.id.toString() == selected } ?: if (children.size == 1) children.first() else null
    val tasks = if (selectedChild != null) data.liveTasks(selectedChild) else children.flatMap(data::liveTasks)
    val open = tasks.filter { !it.isDismissed }
    val overview = TaskPlanner.overview(tasks)
    val late = open.filter { it.isLate() }
    val buckets = TaskPlanner.buckets(open, completed = TaskPlanner.CompletedPlacement.IN_PLACE)
    val dismissed = tasks.filter { it.isDismissed }
    var menu by remember { mutableStateOf(false) }
    var showDismissed by rememberSaveable { mutableStateOf(false) }

    Page(
        "Plan",
        actions = {
            IconButton(onClick = { menu = true }, modifier = Modifier.testTag("plan-menu")) {
                Icon(Icons.Rounded.MoreVert, contentDescription = "Plan options", tint = AppTheme.colors.accent)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Change household answers") }, onClick = { menu = false; nav.push(Overlay.Household) })
                if (selectedChild != null) {
                    DropdownMenuItem(
                        text = { Text("Send this plan to the other parent") },
                        onClick = { menu = false; nav.push(Overlay.SharePlan(selectedChild.id)) },
                        modifier = Modifier.testTag("menu-share"),
                    )
                    DropdownMenuItem(
                        text = { Text(if (graph.subscriptions.isPro) "Printable summary" else "Printable summary (Plus)") },
                        onClick = {
                            menu = false
                            if (graph.subscriptions.isPro) nav.push(Overlay.Export(selectedChild.id, ExportKind.SUMMARY)) else nav.push(Overlay.Paywall("summary"))
                        },
                    )
                } else {
                    DropdownMenuItem(text = { Text("Choose one child before sharing") }, enabled = false, onClick = {})
                }
                DropdownMenuItem(text = { Text("Rebuild the plan") }, onClick = { menu = false; graph.store.commit() })
            }
        },
    ) {
        item {
            Card(Modifier.clickable { nav.push(Overlay.Household) }.testTag("household-card")) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Tune, contentDescription = null, tint = AppTheme.colors.accent)
                    Spacer(Modifier.width(AppTheme.spacing))
                    Column(Modifier.weight(1f)) {
                        Text("Change household answers", style = Type.body.copy(fontWeight = FontWeight.Medium), color = AppTheme.colors.label)
                        Text("Update the answers that shape every deadline in this plan.", style = Type.footnote, color = AppTheme.colors.secondary)
                    }
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = AppTheme.colors.tertiary)
                }
            }
        }
        item { PlanHeaderCard(overview) { nav.push(Overlay.TaskDetail(it)) } }

        if (late.isNotEmpty()) {
            item { SectionHeader("Sent, and still not here", blurb = "Past the date the office told you to expect it. Nothing else in your life is going to mention this, which is why it is at the top.") }
            taskCard(late, graph, children.size > 1)
        }

        if (children.size > 1) {
            item {
                Card(padding = PaddingValues(0.dp)) {
                    ChoiceRow("Everyone", selectedChild == null) { selected = null; nav.selectedChildID = null }
                    children.forEach { child ->
                        RowDivider()
                        ChoiceRow(child.displayName, selectedChild?.id == child.id) { selected = child.id.toString(); nav.selectedChildID = child.id }
                    }
                }
                if (selectedChild == null) Footnote("Choose one child before sending or exporting a plan.")
            }
        }

        buckets.forEach { (bucket, items) ->
            item(key = "bucket-${bucket.name}") {
                val left = items.count { !it.isDone }
                SectionHeader(if (left > 0) "${bucket.title} · $left" else bucket.title, blurb = bucket.blurb)
            }
            taskCard(items, graph, children.size > 1)
        }

        if (dismissed.isNotEmpty()) {
            item {
                Text(
                    "Does not apply to us (${dismissed.size})",
                    style = Type.subheadline, color = AppTheme.colors.accent,
                    modifier = Modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch).clickable { showDismissed = !showDismissed }.padding(top = 14.dp, start = 4.dp),
                )
            }
            if (showDismissed) taskCard(dismissed, graph, children.size > 1)
        }
    }
}

fun LazyListScope.taskCard(tasks: List<RequirementTask>, graph: AppGraph, showChildName: Boolean) {
    item(key = "card-" + tasks.joinToString("") { it.id.toString().take(8) }) {
        Card(padding = PaddingValues(0.dp)) {
            tasks.forEachIndexed { i, task ->
                if (i > 0) RowDivider(inset = true)
                TaskRow(task, graph, showChildName)
            }
        }
    }
}

@Composable
fun TaskRow(task: RequirementTask, graph: AppGraph, showChildName: Boolean) {
    val c = AppTheme.colors
    val haptics = LocalHapticFeedback.current
    val data = graph.store.data
    val outstanding = data.liveDocuments(task).count { !it.isOnHand }
    val secondary = buildList {
        add(task.category.label)
        if (showChildName) data.child(task.childId)?.let { add(it.displayName) }
        add(task.assigneeName.ifEmpty { "Assign someone" })
        if (outstanding > 0 && !task.isDone) add("$outstanding to gather")
    }.joinToString(" · ")
    val due = TaskPlanner.duePhrase(task)
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.Top) {
        // The tick is its own 48dp target beside the link, never around it.
        IconButton(
            onClick = {
                haptics.performHapticFeedback(if (task.isDone) HapticFeedbackType.TextHandleMove else HapticFeedbackType.LongPress)
                graph.toggle(task)
            },
            modifier = Modifier.padding(start = 2.dp, top = 4.dp).semantics {
                contentDescription = "Done: ${task.title}"
                stateDescription = if (task.isDone) "Ticked" else "Not ticked"
            }.testTag("tick-${task.catalogKey.ifEmpty { task.id.toString() }}"),
        ) {
            Icon(
                if (task.isDone) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked,
                contentDescription = null,
                tint = if (task.isDone) c.green else c.tertiary,
            )
        }
        Column(
            Modifier.weight(1f).clickable(role = Role.Button) { graph.navigator.push(Overlay.TaskDetail(task.id)) }
                .padding(top = 12.dp, bottom = 12.dp, end = AppTheme.spacing).testTag("task-${task.catalogKey}"),
        ) {
            Text(
                task.title, style = Type.body, color = if (task.isDone) c.secondary else c.label,
                textDecoration = if (task.isDone) TextDecoration.LineThrough else null,
            )
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (!task.isDone) DuePill(due, AppTheme.urgency(task.deadlineKind, task.daysRemaining()))
                if (task.isLate()) DuePill("Not arrived", c.red)
            }
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(task.category.icon, contentDescription = null, tint = c.secondary, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(4.dp))
                Text(secondary, style = Type.footnote, color = c.secondary)
            }
        }
    }
}

@Composable
fun PlanHeaderCard(overview: TaskPlanner.Overview, onOpen: (UUID) -> Unit) {
    val c = AppTheme.colors
    val targetID = overview.pastHardDeadlineID ?: overview.nextHardDeadlineID
    val closing = overview.hasPastHardDeadline || overview.nextHardDeadline != null
    Card(Modifier.then(if (targetID != null) Modifier.clickable { onOpen(targetID) } else Modifier).testTag("header-card")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(if (closing) Icons.Rounded.Error else Icons.Rounded.CheckCircle, contentDescription = null, tint = if (closing) c.red else c.green, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(
                when {
                    overview.hasPastHardDeadline -> "HARD DEADLINE PASSED"
                    overview.nextHardDeadline != null -> "NEXT HARD DEADLINE"
                    else -> "NOTHING CLOSING"
                },
                style = Type.caption.copy(fontWeight = FontWeight.SemiBold), color = if (closing) c.red else c.green,
            )
        }
        Spacer(Modifier.height(AppTheme.tightSpacing))
        val date = overview.pastHardDeadline ?: overview.nextHardDeadline
        val title = overview.pastHardDeadlineTitle ?: overview.nextHardDeadlineTitle
        if (date != null && title != null) {
            Text(title, style = Type.headline, color = c.label)
            Text(TaskPlanner.deadlineLine(date), style = Type.subheadline.copy(fontWeight = FontWeight.Medium), color = c.red)
        } else {
            Text("Every closing window is behind you. What is left has no date attached to it.", style = Type.subheadline, color = c.secondary)
        }
        Spacer(Modifier.height(AppTheme.spacing))
        RowDivider()
        Spacer(Modifier.height(AppTheme.spacing))
        Row {
            Text("${overview.doneCount} of ${overview.totalCount} done", style = Type.subheadline.copy(fontWeight = FontWeight.Medium), color = c.label, modifier = Modifier.weight(1f))
            if (overview.overdueCount > 0) Text("${overview.overdueCount} past due", style = Type.subheadline, color = c.red)
        }
        Spacer(Modifier.height(6.dp))
        LinearProgressIndicator(
            progress = { overview.progress.toFloat() },
            modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
            color = c.green, trackColor = c.raised, drawStopIndicator = {},
        )
    }
}
