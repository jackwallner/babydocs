package com.jackwallner.babydocs.ui.screens

import android.content.Intent
import android.net.Uri
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.HourglassEmpty
import androidx.compose.material.icons.rounded.HelpOutline
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.SubdirectoryArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.jackwallner.babydocs.MainActivity
import com.jackwallner.babydocs.Overlay
import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.Receipt
import com.jackwallner.babydocs.model.ReceiptKind
import com.jackwallner.babydocs.model.RequirementTask
import com.jackwallner.babydocs.model.toLocalDate
import com.jackwallner.babydocs.rules.PlanTimeline
import com.jackwallner.babydocs.rules.RequirementCatalog
import com.jackwallner.babydocs.rules.TaskPlanner
import com.jackwallner.babydocs.ui.DateRow
import com.jackwallner.babydocs.ui.LocalGraph
import com.jackwallner.babydocs.ui.medium
import com.jackwallner.babydocs.ui.theme.AppTheme
import com.jackwallner.babydocs.ui.theme.Card
import com.jackwallner.babydocs.ui.theme.DuePill
import com.jackwallner.babydocs.ui.theme.Footnote
import com.jackwallner.babydocs.ui.theme.NavRow
import com.jackwallner.babydocs.ui.theme.Page
import com.jackwallner.babydocs.ui.theme.RowDivider
import com.jackwallner.babydocs.ui.theme.SectionHeader
import com.jackwallner.babydocs.ui.theme.ToggleRow
import com.jackwallner.babydocs.ui.theme.Type
import com.jackwallner.babydocs.ui.theme.icon
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

fun Uri.open(context: android.content.Context) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, this).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

private fun LocalDate.startMillis() = atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()

@Composable
fun TaskDetailScreen(taskID: UUID, activity: MainActivity) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    graph.store.revision
    val data = graph.store.data
    val task = data.task(taskID)
    if (task == null || task.deletedAt != null) {
        LaunchedEffect(Unit) { nav.pop() }
        return
    }
    val c = AppTheme.colors
    val context = LocalContext.current
    val isPlus = graph.subscriptions.isPro
    val rule = RequirementCatalog.rule(task.catalogKey)
    var assignee by rememberSaveable(taskID) { mutableStateOf(task.assigneeName) }
    var notes by rememberSaveable(taskID) { mutableStateOf(task.parentNotes) }
    var addingReceipt by remember { mutableStateOf(false) }

    fun saveText() {
        if (assignee.trim() == task.assigneeName && notes == task.parentNotes) return
        graph.store.commit(reconcile = false) {
            task.assigneeName = assignee.trim()
            task.parentNotes = notes
            task.updatedAt = System.currentTimeMillis()
        }
        // A rejected (SSN-shaped) edit rolls back; show what was kept.
        graph.store.data.task(taskID)?.let { assignee = it.assigneeName; notes = it.parentNotes }
    }
    LaunchedEffect(assignee, notes) {
        delay(800)
        saveText()
    }
    DisposableEffect(taskID) { onDispose { saveText() } }

    fun change(block: (RequirementTask) -> Unit) {
        graph.store.commit { block(task); task.updatedAt = System.currentTimeMillis() }
        graph.rescheduleReminders()
    }

    Page(rule?.shortTitle ?: task.title, onBack = { nav.pop() }) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 4.dp, top = 4.dp)) {
                Icon(task.category.icon, contentDescription = null, tint = c.secondary, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(task.category.label.uppercase(), style = Type.sectionHeader, color = c.secondary)
            }
        }
        item {
            Card {
                Text(task.title, style = Type.title3, color = c.label, modifier = Modifier.testTag("detail-title"))
                Spacer(Modifier.height(AppTheme.tightSpacing))
                Text(task.detail, style = Type.body, color = c.label)
            }
        }

        // Deadline
        item {
            SectionHeader(when (task.deadlineKind) { DeadlineKind.HARD -> "Hard deadline"; DeadlineKind.RECOMMENDED -> "Suggested by"; DeadlineKind.NONE -> "Timing" })
            Card {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    DuePill(TaskPlanner.duePhrase(task), AppTheme.urgency(task.deadlineKind, task.daysRemaining()))
                    Spacer(Modifier.weight(1f))
                    task.dueAt?.let { Text(TaskPlanner.deadlineLine(it).substringBefore(" ·"), style = Type.subheadline, color = c.secondary) }
                }
                if (task.deadlineBasis.isNotEmpty()) {
                    Spacer(Modifier.height(AppTheme.tightSpacing))
                    Text(task.deadlineBasis, style = Type.footnote, color = c.secondary)
                }
                val siblings = data.liveTasks(data.child(task.childId) ?: return@Card)
                val step = PlanTimeline.step(task, siblings.filter { it.isDone }.map { it.catalogKey }.toSet(), data.child(task.childId)?.birthDate)
                if (step.reason.isNotEmpty() && !task.isDone) {
                    Spacer(Modifier.height(AppTheme.tightSpacing))
                    Row {
                        Icon(if (step.isBlocked) Icons.Rounded.HourglassEmpty else Icons.Rounded.SubdirectoryArrowRight, contentDescription = null, tint = c.secondary, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(step.reason, style = Type.footnote, color = c.secondary)
                    }
                }
            }
        }

        // Where to do it
        if (task.officialURLString.isNotEmpty()) {
            item {
                SectionHeader("Where to do it")
                Card(padding = PaddingValues(0.dp)) {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch).clickable(role = Role.Button) { Uri.parse(task.officialURLString).open(context) }
                            .padding(AppTheme.spacing).testTag("official-link"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(task.officialLinkLabel.ifEmpty { "Open the official page" }, style = Type.body, color = c.accent, modifier = Modifier.weight(1f))
                        Icon(Icons.AutoMirrored.Rounded.OpenInNew, contentDescription = null, tint = c.accent)
                    }
                }
                Footnote("Baby Docs never submits anything for you. This opens the official site so you file it yourself.")
            }
        }

        // Who has this
        item {
            SectionHeader("Who has this")
            Card {
                OutlinedTextField(assignee, { assignee = it }, placeholder = { Text("Nobody assigned") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("assignee"))
            }
            Footnote("A name, for your own benefit. Both of you keep your own copy of the plan, so this does not appear on their phone.")
        }

        // Your own reminder (Plus)
        item {
            SectionHeader("Your own reminder")
            Card(padding = PaddingValues(0.dp)) {
                if (isPlus) {
                    val reminder = task.customReminderAt
                    if (reminder != null) {
                        DateRow("Remind me on", reminder.toLocalDate(), tag = "reminder-date", notBefore = LocalDate.now().plusDays(1)) { day ->
                            change { it.customReminderAt = day.startMillis() }
                        }
                        RowDivider()
                        NavRow("Remove this reminder", titleColor = c.red) { change { it.customReminderAt = null } }
                    } else {
                        NavRow("Remind me about this one", modifier = Modifier.testTag("add-reminder")) {
                            change { it.customReminderAt = LocalDate.now().plusDays(3).startMillis() }
                        }
                    }
                } else {
                    NavRow("Remind me about this one", value = "Plus", modifier = Modifier.testTag("add-reminder-locked")) { nav.push(Overlay.Paywall("reminder")) }
                }
            }
            Footnote(
                if (task.deadlineKind == DeadlineKind.HARD) "This task already has a warning seven days and one day before it closes, for everybody, free. This is an extra one at a date you pick."
                else "A notification at 9am on the day you pick. Baby Docs never invents a date here: nothing fires unless you set one.",
            )
        }

        // Documents (free)
        val documents = data.liveDocuments(task)
        if (documents.isNotEmpty()) {
            item {
                SectionHeader("Have these ready")
                Card(padding = PaddingValues(0.dp)) {
                    documents.forEachIndexed { i, item ->
                        if (i > 0) RowDivider(inset = true)
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch)
                                .clickable(role = Role.Checkbox) {
                                    graph.store.commit(reconcile = false) {
                                        item.isOnHand = !item.isOnHand
                                        item.markedOnHandAt = if (item.isOnHand) System.currentTimeMillis() else null
                                        item.updatedAt = System.currentTimeMillis()
                                    }
                                }
                                .semantics { stateDescription = if (item.isOnHand) "Gathered" else "Still to find" }
                                .padding(AppTheme.spacing).testTag("doc-${item.catalogKey}"),
                        ) {
                            Icon(if (item.isOnHand) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, contentDescription = null, tint = if (item.isOnHand) c.accent else c.tertiary)
                            Spacer(Modifier.width(AppTheme.spacing))
                            Column {
                                Text(item.title, style = Type.body, color = if (item.isOnHand) c.secondary else c.label, textDecoration = if (item.isOnHand) TextDecoration.LineThrough else null)
                                if (item.detail.isNotEmpty()) Text(item.detail, style = Type.caption, color = c.secondary)
                            }
                        }
                    }
                }
                val outstanding = documents.count { !it.isOnHand }
                Footnote(if (outstanding == 0) "Everything on this list is gathered." else "$outstanding still to find. They are collected with everything else on the Documents tab.")
            }
        }

        // Sent and waiting (Plus)
        if (task.isPostedAway) {
            item {
                SectionHeader("Sent and waiting")
                Card(padding = PaddingValues(0.dp)) {
                    if (!isPlus) {
                        NavRow("Track what comes back", value = "Plus", modifier = Modifier.testTag("followup-locked")) { nav.push(Overlay.Paywall("follow_up")) }
                    } else {
                        ToggleRow("Sent it", task.submittedAt != null, modifier = Modifier.testTag("sent-it")) { sent ->
                            change {
                                it.submittedAt = if (sent) System.currentTimeMillis() else null
                                if (!sent) it.expectedByAt = null
                            }
                        }
                        val sentAt = task.submittedAt
                        if (sentAt != null) {
                            RowDivider()
                            DateRow("Sent on", sentAt.toLocalDate(), tag = "sent-on", notAfter = LocalDate.now()) { day -> change { it.submittedAt = day.startMillis() } }
                            RowDivider()
                            val expected = task.expectedByAt
                            DateRow("They said to expect it by", expected, tag = "expected-by", placeholder = "They gave me a date") { day -> change { it.expectedByAt = day } }
                            if (expected != null) {
                                RowDivider()
                                NavRow("They did not give me a date", titleColor = c.red) { change { it.expectedByAt = null } }
                            }
                            if (task.isLate()) {
                                Text(
                                    "This is past the date you were given. That is usually worth a phone call rather than more waiting.",
                                    style = Type.footnote.copy(fontWeight = FontWeight.Medium), color = c.red, modifier = Modifier.padding(AppTheme.spacing),
                                )
                            } else if (expected == null) {
                                Text("No date given yet. Nothing here will go late until you put one in.", style = Type.footnote, color = c.secondary, modifier = Modifier.padding(AppTheme.spacing))
                            }
                        }
                    }
                }
                Footnote(
                    when {
                        !isPlus -> "Follow-up tracking is part of Baby Docs Plus. Every deadline, official link and document list remains free."
                        task.submittedAt == null -> "Once this is posted or filed, record when it went and what the office told you to expect. The plan will say something when that date passes."
                        else -> "No turnaround is guessed here, not even as a starting value. Whatever the office told you is the only figure worth acting on, because it differs by county and changes constantly."
                    },
                )
            }
        }

        // Confirmations
        item {
            SectionHeader("Confirmations")
            Card(padding = PaddingValues(0.dp)) {
                data.liveReceipts(task).forEach { receipt ->
                    Row(Modifier.fillMaxWidth().padding(AppTheme.spacing), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(receipt.value, style = Type.body, color = c.label)
                            Text("${receipt.kind.label} · ${receipt.recordedAt.toLocalDate().medium()}", style = Type.caption, color = c.secondary)
                        }
                        TextButton(onClick = {
                            graph.store.commit(reconcile = false) { receipt.deletedAt = System.currentTimeMillis(); receipt.updatedAt = System.currentTimeMillis() }
                        }) { Text("Remove", color = c.red) }
                    }
                    RowDivider()
                }
                NavRow("Record what came back", modifier = Modifier.testTag("add-receipt")) { addingReceipt = true }
            }
            Footnote("Confirmation numbers, tracking numbers and short notes about what came back. Everything here is stored as ordinary text on this phone, so do not put the Social Security number in it: nothing in Baby Docs needs the number, only whether the card has arrived.")
        }

        // Notes
        item {
            SectionHeader("Your notes")
            Card {
                OutlinedTextField(notes, { notes = it }, minLines = 3, modifier = Modifier.fillMaxWidth().testTag("notes"))
            }
            Footnote("Plain text, on this phone. Not the place for the Social Security number: nothing in Baby Docs needs it.")
        }

        // Done / dismiss
        item {
            Spacer(Modifier.height(AppTheme.tightSpacing))
            Card(padding = PaddingValues(0.dp)) {
                NavRow(if (task.isDone) "Mark not done" else "Mark done", titleColor = c.accent, modifier = Modifier.testTag("mark-done")) { graph.toggle(task) }
                RowDivider()
                NavRow(if (task.isDismissed) "Put back on the list" else "Does not apply to us", titleColor = if (task.isDismissed) c.accent else c.secondary) {
                    change { it.setDismissed(!it.isDismissed) }
                }
            }
            if (task.catalogKey.isNotEmpty()) Footnote("Dismissing keeps this off your plan even after the plan is rebuilt.")
        }

        // Source
        item { SourceFootnote(task) }
    }

    if (addingReceipt) {
        ReceiptDialog(onDismiss = { addingReceipt = false }) { kind, value ->
            graph.store.commit(reconcile = false) { it.receipts += Receipt(taskId = task.id, kind = kind, value = value) }
            addingReceipt = false
        }
    }
}

@Composable
private fun ReceiptDialog(onDismiss: () -> Unit, onSave: (ReceiptKind, String) -> Unit) {
    var value by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf(ReceiptKind.CONFIRMATION_NUMBER) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Record a confirmation") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Whatever the office gave you back, so you do not have to find the email again.", style = Type.footnote)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(ReceiptKind.CONFIRMATION_NUMBER, ReceiptKind.TRACKING, ReceiptKind.NOTE).forEach {
                        FilterChip(selected = kind == it, onClick = { kind = it }, label = { Text(it.label.substringBefore(" number")) })
                    }
                }
                OutlinedTextField(value, { value = it }, label = { Text("Number or reference") }, singleLine = true, modifier = Modifier.testTag("receipt-value"))
            }
        },
        confirmButton = { TextButton(onClick = { value.trim().takeIf { it.isNotEmpty() }?.let { onSave(kind, it) } }, modifier = Modifier.testTag("receipt-save")) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** Every rule shows its working: the page, the day it was read, and what it does not say. */
@Composable
fun SourceFootnote(task: RequirementTask) {
    val c = AppTheme.colors
    val context = LocalContext.current
    val rule = if (task.catalogKey.isEmpty()) null else RequirementCatalog.rule(task.catalogKey)
    val source = rule?.source
    Column(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = AppTheme.spacing), verticalArrangement = Arrangement.spacedBy(AppTheme.hairSpacing)) {
        if (task.sourceURLString.isNotEmpty()) {
            Text(
                "Where this comes from", style = Type.caption.copy(fontWeight = FontWeight.SemiBold), color = c.accent,
                modifier = Modifier.heightIn(min = 32.dp).clickable { Uri.parse(task.sourceURLString).open(context) }.testTag("source-link"),
            )
            source?.let { Text(it.title, style = Type.caption, color = c.secondary) }
            task.sourceVerifiedOn?.let { day ->
                val text = when (source?.status) {
                    "awaitingReview" -> "Link added ${day.medium()}. Nobody has read this page end to end yet."
                    "federalFallback" -> "Checked ${day.medium()}. Federal page: your state or plan has the final word."
                    else -> "Checked ${day.medium()}"
                }
                Text(text, style = Type.caption, color = if (source?.status == "awaitingReview") c.orange else c.secondary)
            }
            source?.limitations?.takeIf { it.isNotEmpty() }?.let { Text("What it does not tell you: $it", style = Type.caption, color = c.secondary) }
        } else if (!rule?.noSourceReason.isNullOrEmpty()) {
            Row {
                Icon(Icons.Rounded.HelpOutline, contentDescription = null, tint = c.secondary, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(6.dp))
                Text(rule!!.noSourceReason, style = Type.caption, color = c.secondary)
            }
        }
    }
}
