package com.jackwallner.babydocs.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Restore
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.babydocs.Overlay
import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.SSNStatus
import com.jackwallner.babydocs.rules.StateVitalRecords
import com.jackwallner.babydocs.rules.TaskPlanner
import com.jackwallner.babydocs.ui.CountyPickerRow
import com.jackwallner.babydocs.ui.DateRow
import com.jackwallner.babydocs.ui.LocalGraph
import com.jackwallner.babydocs.ui.StatePickerRow
import com.jackwallner.babydocs.ui.medium
import com.jackwallner.babydocs.ui.theme.AppTheme
import com.jackwallner.babydocs.ui.theme.DialogTags
import com.jackwallner.babydocs.ui.theme.Avatar
import com.jackwallner.babydocs.ui.theme.Card
import com.jackwallner.babydocs.ui.theme.ChoiceRow
import com.jackwallner.babydocs.ui.theme.Footnote
import com.jackwallner.babydocs.ui.theme.NavRow
import com.jackwallner.babydocs.ui.theme.Page
import com.jackwallner.babydocs.ui.theme.PrimaryButton
import com.jackwallner.babydocs.ui.theme.RowDivider
import com.jackwallner.babydocs.ui.theme.SectionHeader
import com.jackwallner.babydocs.ui.theme.ToggleRow
import com.jackwallner.babydocs.ui.theme.Type
import java.time.LocalDate
import java.util.UUID

@Composable
fun ChildrenScreen() {
    val graph = LocalGraph.current
    graph.store.revision
    val data = graph.store.data
    val nav = graph.navigator
    val archived = data.children.filter { it.deletedAt != null && !it.isEphemeralDraft }

    Page("Children") {
        data.liveChildren.forEach { child ->
            item(key = child.id.toString()) { LocalGraph.current.store.revision; ChildCard(child) }
        }
        item {
            LocalGraph.current.store.revision
            Spacer(Modifier.padding(top = 4.dp))
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Add another child", icon = Icons.Rounded.Add, modifier = Modifier.testTag("add-child")) { nav.push(Overlay.ChildEditor(null)) }
            }
            Footnote("A second baby inherits your household answers, so the questions are not asked twice. Every child is free.")
        }
        item {
            LocalGraph.current.store.revision
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Household answers", icon = Icons.Rounded.Tune) { nav.push(Overlay.Household) }
            }
            Footnote("Where you live, how you are covered, whether you are taking leave. Changing an answer here rebuilds every child's plan.")
        }
        if (archived.isNotEmpty()) {
            item {
                LocalGraph.current.store.revision
                SectionHeader("Archived children")
                Card(padding = PaddingValues(0.dp)) {
                    archived.forEachIndexed { i, child ->
                        if (i > 0) RowDivider()
                        NavRow("Restore ${child.displayName}", icon = Icons.Rounded.Restore) {
                            graph.store.commit { child.deletedAt = null; child.updatedAt = System.currentTimeMillis() }
                        }
                    }
                }
                Footnote("Archived children keep their plan and receipts. Restore one if it was removed by mistake.")
            }
        }
    }
}

@Composable
private fun ChildCard(child: Child) {
    LocalGraph.current.store.revision
    val graph = LocalGraph.current
    val c = AppTheme.colors
    val data = graph.store.data
    val overview = TaskPlanner.overview(data.liveTasks(child))
    Column {
        Card(padding = PaddingValues(0.dp)) {
            Row(Modifier.fillMaxWidth().padding(AppTheme.spacing), verticalAlignment = Alignment.CenterVertically) {
                Avatar(child.initials, AppTheme.childColor(child.colorIndex))
                Spacer(Modifier.width(AppTheme.spacing))
                Column(Modifier.weight(1f)) {
                    Text(child.displayName, style = Type.headline, color = c.label)
                    Text("Born ${child.birthDate.medium()}", style = Type.footnote, color = c.secondary)
                }
                Text("${overview.openCount} left", style = Type.subheadline.copy(fontWeight = FontWeight.Medium), color = c.secondary)
            }
            RowDivider()
            Text("Social Security number", style = Type.footnote, color = c.secondary, modifier = Modifier.padding(start = AppTheme.spacing, top = AppTheme.spacing))
            SSNStatus.entries.forEach { status ->
                ChoiceRow(status.label, child.ssnStatus == status, modifier = Modifier.testTag("ssn-${status.raw}")) {
                    graph.store.commit {
                        child.ssnStatus = status
                        child.ssnReceivedAt = if (status == SSNStatus.CARD_RECEIVED) (child.ssnReceivedAt ?: System.currentTimeMillis()) else null
                        child.updatedAt = System.currentTimeMillis()
                    }
                    graph.rescheduleReminders()
                }
            }
            RowDivider()
            ToggleRow("Certified birth certificate in hand", child.birthCertificateReceivedAt != null, modifier = Modifier.testTag("certificate")) { inHand ->
                graph.store.commit {
                    child.birthCertificateReceivedAt = if (inHand) System.currentTimeMillis() else null
                    if (inHand && child.certifiedCopiesOnHand == 0) child.certifiedCopiesOnHand = 1
                    child.updatedAt = System.currentTimeMillis()
                }
                graph.rescheduleReminders()
            }
            if (child.birthCertificateReceivedAt != null) {
                Row(Modifier.fillMaxWidth().padding(horizontal = AppTheme.spacing), verticalAlignment = Alignment.CenterVertically) {
                    Text("Certified copies on hand: ${child.certifiedCopiesOnHand}", style = Type.body, color = c.label, modifier = Modifier.weight(1f))
                    TextButton(onClick = { graph.store.commit(reconcile = false) { child.certifiedCopiesOnHand = maxOf(0, child.certifiedCopiesOnHand - 1) } }) { Text("−") }
                    TextButton(onClick = { graph.store.commit(reconcile = false) { child.certifiedCopiesOnHand += 1 } }) { Text("+") }
                }
            }
            RowDivider()
            NavRow("Edit details", modifier = Modifier.testTag("edit-child")) { graph.navigator.push(Overlay.ChildEditor(child.id)) }
            RowDivider()
            NavRow("Send or print this plan", icon = Icons.Rounded.Send, subtitle = "The link for the other parent, the printable one-pager and the employer packet.") {
                graph.navigator.push(Overlay.SharePlan(child.id))
            }
        }
        Footnote("These two answers open and close tasks. Marking the certificate in hand unblocks the passport task and adds the check for a misspelled name.")
    }
}

@Composable
fun ChildEditorScreen(childID: UUID?) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val data = graph.store.data
    val existing = childID?.let(data::child)
    if (childID != null && existing == null) {
        LaunchedEffect(Unit) { nav.pop() }
        return
    }
    var name by rememberSaveable { mutableStateOf(existing?.name.orEmpty()) }
    var birth by rememberSaveable { mutableStateOf(existing?.birthDate?.toString()) }
    var confirmed by rememberSaveable { mutableStateOf(existing != null) }
    var state by rememberSaveable { mutableStateOf(existing?.birthStateCode ?: data.profile.residenceStateCode) }
    var county by rememberSaveable { mutableStateOf(existing?.birthCounty.orEmpty()) }
    var citizen by rememberSaveable { mutableStateOf(existing?.isUSCitizen) }
    var confirmArchive by rememberSaveable { mutableStateOf(false) }
    val valid = birth != null && confirmed && state.isNotEmpty() && citizen != null

    Page(if (existing == null) "Add a child" else "Edit details", onBack = { nav.pop() }) {
        item {
            LocalGraph.current.store.revision
            SectionHeader("Baby")
            Card(padding = PaddingValues(0.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("First name") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(AppTheme.spacing).testTag("child-name"))
                RowDivider()
                DateRow("Date of birth", birth?.let(LocalDate::parse), tag = "child-birth", notAfter = LocalDate.now()) {
                    if (it.toString() != birth) confirmed = false
                    birth = it.toString()
                }
                RowDivider()
                ToggleRow("I checked this date", confirmed, enabled = birth != null, modifier = Modifier.testTag("child-date-confirmed")) { confirmed = it }
            }
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Where the birth was registered")
            Card(padding = PaddingValues(0.dp)) {
                StatePickerRow("State of birth", state, tag = "child-state") { if (it != state) county = ""; state = it }
                if (state.isNotEmpty()) {
                    RowDivider()
                    CountyPickerRow(state, county) { county = it }
                }
            }
            Footnote("Where this birth was registered, which is not always where you live now. Every date and every office in this child's plan comes from it, so there is no sensible default and Baby Docs will not pick one for you.")
            if (state.isNotEmpty() && !StateVitalRecords.office(state).isVerified) {
                Footnote("We do not yet carry verified detail for this state, so the birth certificate task links to the federal directory, which has a state-by-state picker.")
            }
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Citizenship")
            Card(padding = PaddingValues(0.dp)) {
                ChoiceRow("US citizen", citizen == true) { citizen = true }
                RowDivider()
                ChoiceRow("Not a US citizen", citizen == false) { citizen = false }
            }
        }
        item {
            LocalGraph.current.store.revision
            Spacer(Modifier.padding(top = AppTheme.spacing))
            PrimaryButton(if (existing == null) "Add to the plan" else "Save", enabled = valid, tag = "child-save") {
                val day = LocalDate.parse(birth!!)
                val saved = graph.store.commit { d ->
                    val child = existing ?: Child(colorIndex = d.children.size).also { d.children += it }
                    child.name = name.trim()
                    child.birthDate = day
                    child.birthStateCode = state
                    child.birthCounty = county
                    child.isUSCitizen = citizen!!
                    child.updatedAt = System.currentTimeMillis()
                }
                if (saved) {
                    graph.rescheduleReminders()
                    nav.pop()
                }
            }
            if (existing != null) {
                TextButton(onClick = { confirmArchive = true }, modifier = Modifier.fillMaxWidth()) { Text("Archive this child", color = AppTheme.colors.red) }
            }
        }
    }

    if (confirmArchive && existing != null) {
        AlertDialog(
            modifier = DialogTags,
            onDismissRequest = { confirmArchive = false },
            title = { Text("Archive this child?") },
            text = { Text("The plan, completed work and receipts stay on this phone and can be restored from Children.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmArchive = false
                    graph.store.commit { existing.deletedAt = System.currentTimeMillis(); existing.updatedAt = System.currentTimeMillis() }
                    graph.rescheduleReminders()
                    nav.pop()
                }) { Text("Archive this child", color = AppTheme.colors.red) }
            },
            dismissButton = { TextButton(onClick = { confirmArchive = false }) { Text("Keep this child") } },
        )
    }
}
