package com.jackwallner.babydocs.ui.screens

import androidx.core.net.toUri
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MailOutline
import androidx.compose.material.icons.rounded.StarOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.jackwallner.babydocs.BuildConfig
import com.jackwallner.babydocs.MainActivity
import com.jackwallner.babydocs.Overlay
import com.jackwallner.babydocs.data.PlanExporter
import com.jackwallner.babydocs.rules.RequirementCatalog
import com.jackwallner.babydocs.rules.StateVitalRecords
import com.jackwallner.babydocs.rules.VitalRecordsOffice
import com.jackwallner.babydocs.model.USState
import com.jackwallner.babydocs.ui.LocalGraph
import com.jackwallner.babydocs.ui.medium
import com.jackwallner.babydocs.ui.theme.AppTheme
import com.jackwallner.babydocs.ui.theme.DialogTags
import com.jackwallner.babydocs.ui.theme.Card
import com.jackwallner.babydocs.ui.theme.Footnote
import com.jackwallner.babydocs.ui.theme.NavRow
import com.jackwallner.babydocs.ui.theme.Page
import com.jackwallner.babydocs.ui.theme.PrimaryButton
import com.jackwallner.babydocs.ui.theme.RowDivider
import com.jackwallner.babydocs.ui.theme.SectionHeader
import com.jackwallner.babydocs.ui.theme.Type
import kotlinx.coroutines.launch

const val FEEDBACK_EMAIL = "jackwallner+babydocs@gmail.com"

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsScreen(activity: MainActivity) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val c = AppTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val subs = graph.subscriptions
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    var reviewEntry by rememberSaveable { mutableStateOf(false) }
    var notificationsOn by remember { mutableStateOf(graph.reminders.hasPermission()) }

    Page("Settings") {
        item {
            SectionHeader("What this app is")
            Card { Text(PlanExporter.DISCLAIMER, style = Type.subheadline, color = c.label) }
        }
        item {
            SectionHeader("Sources")
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Oldest source check", value = RequirementCatalog.reviewedOn.medium()) { nav.push(Overlay.Sources) }
                RowDivider()
                NavRow("Birth certificate offices", value = "${StateVitalRecords.verifiedStateCodes.size} linked", modifier = Modifier.testTag("open-sources")) { nav.push(Overlay.Sources) }
            }
            Footnote("A rule set is only as fresh as its stalest page, so the date above is the oldest of them. Every state and DC links to that state's own vital records office, and the list says which of them somebody has read end to end and which have been checked against the office's own guidance without a full read. The five territories still link to the national directory, which has a picker: we would rather send you somewhere general and correct than somewhere specific and guessed.")
        }
        item {
            SectionHeader("Reminders")
            Card(padding = PaddingValues(0.dp)) {
                if (notificationsOn) {
                    NavRow("Notifications", value = "On") {
                        context.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName))
                    }
                } else {
                    NavRow("Turn on deadline reminders", titleColor = c.accent, modifier = Modifier.testTag("enable-reminders")) {
                        scope.launch {
                            notificationsOn = activity.requestNotificationPermission()
                            if (!notificationsOn) {
                                context.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName))
                            }
                            graph.rescheduleReminders()
                        }
                    }
                }
            }
            Footnote("The two dates that are real doors closing are announced for everybody, free, whatever else is switched off: the job-based health plan and the Marketplace. The rest of the plan is dates Baby Docs suggests, and those stay quiet unless you turn them on in Plus, because a suggestion that fires at 9am unbidden is what teaches someone to switch the whole category off, and then they miss the one that mattered.")
        }
        item {
            SectionHeader("Document vault")
            Card { Text("On this phone", style = Type.body, color = c.label) }
            Footnote("Photographs of your documents live in this app's private storage, behind the phone's own lock, and are excluded from every cloud and device-transfer backup. That is the trade: nothing can leak them, and nothing can restore them to a new phone either. The originals are still the record.")
        }
        item {
            SectionHeader("Plus")
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Status", value = if (subs.isPro) "Active" else "Not active") { if (!subs.isPro) nav.push(Overlay.Paywall("settings")) }
                RowDivider()
                NavRow("Restore purchases", titleColor = c.accent, modifier = Modifier.testTag("settings-restore")) {
                    scope.launch {
                        subs.restorePurchases()
                        restoreMessage = if (subs.isPro) "Plus is active on this device again." else subs.lastError
                        graph.rescheduleReminders()
                    }
                }
                RowDivider()
                NavRow("Manage subscription") {
                    "https://play.google.com/store/account/subscriptions?package=$PACKAGE_NAME".toUri().open(context)
                }
            }
        }
        item {
            SectionHeader("Your data")
            Card {
                Text(
                    "Baby Docs has no account. Everything you enter, and every photograph you add, stays on this phone unless you choose to send it: nothing is uploaded on its own, so there is nothing for us to delete on your behalf and nothing for anyone to breach. Sending a plan to the other parent puts your household answers and the baby's first name in that link, deliberately, and only when you tap it. Photographs never travel at all. If you buy Plus, Google Play and RevenueCat hold the purchase itself; that record carries nothing about your family. The privacy policy sets out exactly what it contains.",
                    style = Type.subheadline, color = c.label,
                )
                TextButton(onClick = { PRIVACY_URL.toUri().open(context) }) { Text("Privacy Policy") }
            }
        }
        item {
            SectionHeader("Support")
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Send feedback", icon = Icons.Rounded.MailOutline, modifier = Modifier.testTag("send-feedback")) { nav.push(Overlay.Feedback) }
                RowDivider()
                NavRow("Rate Baby Docs on Google Play", icon = Icons.Rounded.StarOutline) {
                    "https://play.google.com/store/apps/details?id=$PACKAGE_NAME".toUri().open(context)
                }
            }
            Footnote("A rule that was wrong for your state or a link that went nowhere is worth more to us than a rating. Feedback opens a mail draft and nothing else.")
        }
        item {
            // Long-press for Google Play's reviewer code; nothing else is behind it.
            Text(
                "Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = Type.footnote, color = c.secondary,
                modifier = Modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch).padding(top = 16.dp, start = 4.dp)
                    .combinedClickable(onClick = {}, onLongClick = { reviewEntry = true }).testTag("version"),
            )
        }
    }

    restoreMessage?.let {
        AlertDialog(modifier = DialogTags, onDismissRequest = { restoreMessage = null }, text = { Text(it) }, confirmButton = { TextButton(onClick = { restoreMessage = null }) { Text("OK") } })
    }
    if (reviewEntry) ReviewCodeDialog { reviewEntry = false }
}

@Composable
private fun ReviewCodeDialog(onDismiss: () -> Unit) {
    val graph = LocalGraph.current
    var code by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(
        modifier = DialogTags,
        onDismissRequest = onDismiss,
        title = { Text("Reviewer access") },
        text = {
            Column {
                Text("For Google Play app review. Enter the code from the review notes.", style = Type.footnote)
                OutlinedTextField(
                    code, { code = it; failed = false }, singleLine = true, isError = failed,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.padding(top = 8.dp).testTag("review-code"),
                )
                if (failed) Text("That code did not match.", style = Type.footnote, color = AppTheme.colors.red)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (graph.subscriptions.activateReviewAccess(code)) {
                    graph.rescheduleReminders()
                    onDismiss()
                } else {
                    failed = true
                }
            }, modifier = Modifier.testTag("review-code-submit")) { Text("Unlock") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
fun SourcesScreen() {
    val nav = LocalGraph.current.navigator
    val c = AppTheme.colors
    val context = LocalContext.current
    Page("Sources", onBack = { nav.pop() }) {
        item { SectionHeader("State offices") }
        item {
            Card(padding = PaddingValues(0.dp)) {
                StateVitalRecords.allOffices.forEachIndexed { i, office ->
                    if (i > 0) RowDivider()
                    val day = office.verifiedOn?.medium().orEmpty()
                    NavRow(
                        USState.displayName(office.stateCode),
                        subtitle = office.officeName + "\n" + if (office.check == VitalRecordsOffice.Check.PAGEREAD) "Page read end to end $day" else "Address and detail checked $day. Not read end to end.",
                    ) { office.urlString.toUri().open(context) }
                }
            }
            Footnote("The five territories are not in this list. Nobody has researched them, so the birth certificate task there links to the national directory and says so rather than sending you to an office we picked.")
        }
        item { SectionHeader("Pages the rules cite") }
        item {
            Card(padding = PaddingValues(0.dp)) {
                com.jackwallner.babydocs.rules.SourceManifest.all.forEachIndexed { i, entry ->
                    if (i > 0) RowDivider()
                    NavRow(entry.title, subtitle = "${entry.agency} · checked ${entry.reviewedOn.medium()}" + if (entry.limitations.isNotEmpty()) "\nWhat it does not tell you: ${entry.limitations}" else "") {
                        entry.urlString.toUri().open(context)
                    }
                }
            }
        }
        item {
            SectionHeader("Cites nothing, on purpose")
            Card {
                Text("These tasks are on the list because they matter, not because a government page says to do them. Rather than link a plausible-looking page that does not support the advice, they say where the answer actually comes from.", style = Type.subheadline, color = c.label)
                RequirementCatalog.all.filter { it.source == null }.forEach {
                    Text(it.shortTitle, style = Type.headline, color = c.label, modifier = Modifier.padding(top = AppTheme.spacing))
                    Text(it.noSourceReason, style = Type.footnote, color = c.secondary)
                }
            }
        }
    }
}

@Composable
fun FeedbackScreen() {
    val nav = LocalGraph.current.navigator
    val context = LocalContext.current
    var body by rememberSaveable { mutableStateOf("") }
    Page("Tell us what is missing", onBack = { nav.pop() }) {
        item { Footnote("A rule that was wrong for your state, a deadline we do not have, a link that went nowhere. Whatever it is, it goes straight to the person who writes the rules.") }
        item {
            Card {
                OutlinedTextField(body, { body = it }, placeholder = { Text("Describe what is missing or incorrect") }, minLines = 5, modifier = Modifier.fillMaxWidth().testTag("feedback-body"))
            }
        }
        item {
            PrimaryButton("Send feedback", enabled = body.isNotBlank()) {
                val uri = Uri.parse("mailto:$FEEDBACK_EMAIL?subject=" + Uri.encode("Baby Docs feedback") + "&body=" + Uri.encode(body))
                runCatching { context.startActivity(Intent(Intent.ACTION_SENDTO, uri)) }
                nav.pop()
            }
            Footnote("This opens your mail app with a draft. Nothing is sent from inside Baby Docs, and nothing about your household goes with it.")
        }
    }
}
