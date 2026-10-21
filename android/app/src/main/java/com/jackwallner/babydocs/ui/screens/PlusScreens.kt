package com.jackwallner.babydocs.ui.screens

import androidx.activity.compose.LocalActivity
import androidx.core.net.toUri
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.EventAvailable
import androidx.compose.material.icons.rounded.EventNote
import androidx.compose.material.icons.rounded.FormatListNumbered
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.PendingActions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.jackwallner.babydocs.ExportKind
import com.jackwallner.babydocs.MainActivity
import com.jackwallner.babydocs.Overlay
import com.jackwallner.babydocs.data.CalendarExporter
import com.jackwallner.babydocs.data.Plan
import com.jackwallner.babydocs.data.PlanExporter
import com.jackwallner.babydocs.data.PlanSeed
import com.jackwallner.babydocs.data.PurchaseException
import com.jackwallner.babydocs.data.PurchaseOutcome
import com.jackwallner.babydocs.data.SubscriptionService
import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.MarketplaceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.ParentalLeaveTakers
import com.jackwallner.babydocs.model.USState
import com.jackwallner.babydocs.rules.PlanTimeline
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
import com.jackwallner.babydocs.ui.theme.SecondaryButton
import com.jackwallner.babydocs.ui.theme.SectionHeader
import com.jackwallner.babydocs.ui.theme.ToggleRow
import com.jackwallner.babydocs.ui.theme.Type
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

const val TERMS_URL = "https://jackwallner.com/ios/babydocs/terms.html"
const val PRIVACY_URL = "https://jackwallner.com/ios/babydocs/privacy-policy.html"
const val PACKAGE_NAME = "com.jackwallner.babydocs"

/** "Weekly, $4.99 / week. 3-day free trial, then $4.99 / week." The words iOS prints above the button. */
fun disclosure(plan: Plan, eligible: Boolean): String {
    val trial = plan.introOfferLabel
    return when {
        plan.isLifetime -> "${plan.priceFormatted} once. No renewal."
        trial != null && eligible -> "$trial, then ${plan.priceLabel}, renewing automatically until cancelled."
        else -> "${plan.priceLabel}, renewing automatically until cancelled."
    }
}

/**
 * `PlusPurchaseView`: one view shown in three places (the paywall overlay, the
 * Plus tab, the last page of the intake), so the benefit list cannot drift.
 */
@Composable
fun PlusPurchaseScreen(placement: String, onDone: () -> Unit, onSkip: (() -> Unit)? = null, onBack: (() -> Unit)? = null) {
    val graph = LocalGraph.current
    val subs = graph.subscriptions
    val c = AppTheme.colors
    val context = LocalContext.current
    val hostActivity = LocalActivity.current
    val scope = rememberCoroutineScope()
    var selection by rememberSaveable { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val plans = subs.plans
    val selected = plans.firstOrNull { it.packageId == selection } ?: plans.firstOrNull()

    LaunchedEffect(placement) {
        subs.trackPaywallImpression("babydocs_$placement", oncePerSession = true)
        if (plans.isEmpty()) subs.fetchProducts()
    }

    Page("Baby Docs Plus", onBack = onBack) {
        item {
            LocalGraph.current.store.revision
            Column(Modifier.fillMaxWidth().padding(vertical = AppTheme.tightSpacing), horizontalAlignment = Alignment.Start) {
                Icon(Icons.Rounded.EventAvailable, contentDescription = null, tint = c.accent, modifier = Modifier.size(40.dp))
                Spacer(Modifier.height(AppTheme.spacing))
                Text(
                    if (placement == "onboarding") "Your plan knows the dates. Plus tells you when." else "For the weeks it is actually happening",
                    style = Type.title, color = c.label,
                )
                Spacer(Modifier.height(AppTheme.tightSpacing))
                Text(
                    "The list of what applies to you is free, and so are both dates that legally close. Plus is the part that tells you when to do the rest, in what order, and says something before each one arrives.",
                    style = Type.callout, color = c.secondary,
                )
            }
        }
        item {
            LocalGraph.current.store.revision
            Card {
                Benefit(Icons.Rounded.NotificationsActive, "A reminder for every date, not just the two that close", "Most of your plan is dates Baby Docs suggests rather than dates the law sets. Free warns you about the two legal windows. Plus warns you about the rest, three days out, and lets you set your own on any task.")
                Benefit(Icons.Rounded.FormatListNumbered, "The order to do it in", "The passport is really the birth certificate wearing a hat, and the \$1,000 election is the Social Security card wearing one. Plus shows the plan as a sequence: what to start this week, what is next, and what is simply waiting on something else to arrive.")
                Benefit(Icons.Rounded.EventNote, "This week's paperwork, every Sunday", "One message on a Sunday morning naming what reaches its date that week, and nothing at all on a week that holds nothing.")
                Benefit(Icons.Rounded.CalendarMonth, "The dates in your own calendar", "Export the plan as a calendar file, so the deadlines sit beside the pediatrician appointment they are competing with, where the other parent can see them too.")
                Benefit(Icons.Rounded.PendingActions, "Chase what has not arrived", "Record what you sent and what you were told to expect. The plan speaks up when that date passes, because nothing else will.")
                Benefit(Icons.Rounded.Lock, "The document vault after twelve weeks", "Photographs of the birth certificate, the card and the insurance details, on your phone at the counter. Adding stays free during the first twelve weeks. Never backed up, never uploaded.")
                Benefit(Icons.Rounded.Description, "The printable summary and the employer packet", "A plain-text plan for the folder or the other parent, and the qualifying-life-event page HR asks for with the event, the date and the enclosures already filled in.", last = true)
            }
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Free, and staying free")
            Card {
                Text("Every task that applies to your household, every official link, every document list, reminders for both deadlines that legally close, every child you add, and sending the whole plan to the other parent.", style = Type.subheadline, color = c.label)
            }
        }
        item {
            LocalGraph.current.store.revision
            Spacer(Modifier.height(AppTheme.tightSpacing))
            when {
                plans.isEmpty() && subs.isLoadingProducts -> Row(Modifier.fillMaxWidth().padding(AppTheme.spacing), horizontalArrangement = Arrangement.Center) { CircularProgressIndicator() }
                plans.isEmpty() -> Card {
                    Text("Google Play did not send the prices back.", style = Type.headline, color = c.label)
                    subs.lastError?.let { Text(it, style = Type.footnote, color = c.secondary) }
                    TextButton(onClick = { scope.launch { subs.fetchProducts() } }) { Text("Try again") }
                }
                else -> Column(verticalArrangement = Arrangement.spacedBy(AppTheme.tightSpacing)) {
                    plans.forEach { plan ->
                        PlanCard(plan, selected?.packageId == plan.packageId, subs.isEligibleForIntroOffer(plan)) { selection = plan.packageId }
                    }
                }
            }
        }
        item {
            LocalGraph.current.store.revision
            Spacer(Modifier.height(AppTheme.spacing))
            selected?.let {
                Text(disclosure(it, subs.isEligibleForIntroOffer(it)), style = Type.footnote.copy(fontWeight = FontWeight.Medium), color = c.label, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(bottom = AppTheme.tightSpacing))
            }
            val buyTitle = when {
                subs.isPro -> "You already have Plus"
                selected == null -> "Continue"
                selected.trial != null && subs.isEligibleForIntroOffer(selected) -> if (placement == "onboarding") "Get started" else "Start my free trial"
                selected.isLifetime -> "Buy it once"
                else -> "Continue"
            }
            PrimaryButton(buyTitle, enabled = !busy && !subs.isPro && selected != null, tag = "buy") {
                val plan = selected ?: return@PrimaryButton
                val activity = hostActivity as? MainActivity ?: return@PrimaryButton
                busy = true
                scope.launch {
                    try {
                        when (subs.purchase(activity, plan)) {
                            PurchaseOutcome.PURCHASED -> { graph.rescheduleReminders(); onDone() }
                            PurchaseOutcome.PENDING -> message = SubscriptionService.PENDING_MESSAGE
                            PurchaseOutcome.CANCELLED -> Unit
                        }
                    } catch (e: PurchaseException) {
                        message = e.message
                    } finally {
                        busy = false
                    }
                }
            }
            if (onSkip != null) SecondaryButton("Continue with the free plan", tag = "skip-plus", onClick = onSkip)
            SecondaryButton("Restore purchases", tag = "restore") {
                scope.launch {
                    subs.restorePurchases()
                    if (subs.isPro) { graph.rescheduleReminders(); onDone() } else message = subs.lastError
                }
            }
            Text(
                "Payment is charged to your Google Play account at confirmation. A subscription renews automatically at the end of each period unless cancelled first, and is managed in Google Play, Payments & subscriptions. Buying the one-time purchase does not cancel a subscription; cancel that in Google Play.",
                style = Type.caption, color = c.secondary, modifier = Modifier.padding(top = AppTheme.tightSpacing),
            )
            Text(
                "What you add to the vault stays readable even if a subscription lapses. Lapsing stops you adding new documents; it never takes back the ones you have.",
                style = Type.caption, color = c.secondary, modifier = Modifier.padding(top = AppTheme.tightSpacing),
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                TextButton(onClick = { TERMS_URL.toUri().open(context) }) { Text("Terms of Use", style = Type.footnote) }
                TextButton(onClick = { PRIVACY_URL.toUri().open(context) }) { Text("Privacy Policy", style = Type.footnote) }
            }
        }
    }

    message?.let {
        AlertDialog(modifier = DialogTags, onDismissRequest = { message = null }, title = { Text("Purchases") }, text = { Text(it) }, confirmButton = { TextButton(onClick = { message = null }) { Text("OK") } })
    }
}

@Composable
private fun Benefit(icon: ImageVector, title: String, detail: String, last: Boolean = false) {
    val c = AppTheme.colors
    Row(Modifier.padding(bottom = if (last) 0.dp else AppTheme.spacing)) {
        Icon(icon, contentDescription = null, tint = c.accent, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(AppTheme.spacing))
        Column {
            Text(title, style = Type.headline, color = c.label)
            Text(detail, style = Type.subheadline, color = c.secondary)
        }
    }
}

@Composable
private fun PlanCard(plan: Plan, selected: Boolean, eligible: Boolean, onSelect: () -> Unit) {
    val c = AppTheme.colors
    val shape = RoundedCornerShape(AppTheme.cardRadius)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(c.surface)
            .border(if (selected) 2.dp else 1.dp, if (selected) c.accent else c.separator, shape)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onSelect)
            .padding(AppTheme.spacing).heightIn(min = 56.dp).testTag("plan-${plan.kind.name.lowercase()}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(plan.displayName, style = Type.body.copy(fontWeight = FontWeight.Medium), color = c.label)
            Text(plan.rationale, style = Type.footnote, color = c.secondary)
            if (eligible) plan.introOfferLabel?.let { Text(it, style = Type.footnote.copy(fontWeight = FontWeight.SemiBold), color = c.accent) }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(plan.priceFormatted, style = Type.headline, color = c.label)
            plan.period?.let { Text(if (it.value == 1) "per ${plan.priceLabel.substringAfterLast(' ')}" else plan.priceLabel.substringAfter("/ "), style = Type.caption, color = c.secondary) }
                ?: Text("once", style = Type.caption, color = c.secondary)
        }
    }
}

@Composable
fun PaywallScreen(placement: String) {
    val nav = LocalGraph.current.navigator
    PlusPurchaseScreen(placement, onDone = { nav.pop() }, onBack = { nav.pop() })
}

/** The offer before purchase and the tools after it. */
@Composable
fun PlusTab() {
    val graph = LocalGraph.current
    if (!graph.subscriptions.isPro) {
        PlusPurchaseScreen("tab", onDone = {})
        return
    }
    val nav = graph.navigator
    val c = AppTheme.colors
    val context = LocalContext.current
    val hostActivity = LocalActivity.current
    val scope = rememberCoroutineScope()
    graph.store.revision
    var suggested by remember { mutableStateOf(graph.reminderPreferences.suggestedDateReminders) }
    var digest by remember { mutableStateOf(graph.reminderPreferences.weeklyDigest) }
    var message by remember { mutableStateOf<String?>(null) }
    val children = graph.store.data.liveChildren

    Page("Baby Docs Plus") {
        item {
            LocalGraph.current.store.revision
            SectionHeader("The order to do it in")
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Timeline", subtitle = "What to start this week, what is next, and what is waiting on something else.", icon = Icons.Rounded.FormatListNumbered, modifier = Modifier.testTag("open-timeline")) { nav.push(Overlay.Timeline) }
            }
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("What gets said out loud")
            Card(padding = PaddingValues(0.dp)) {
                ToggleRow("Suggested dates", suggested, modifier = Modifier.testTag("toggle-suggested")) {
                    suggested = it; graph.reminderPreferences.suggestedDateReminders = it; graph.rescheduleReminders()
                }
                RowDivider()
                ToggleRow("This week's paperwork, on Sundays", digest, modifier = Modifier.testTag("toggle-digest")) {
                    digest = it; graph.reminderPreferences.weeklyDigest = it; graph.rescheduleReminders()
                }
                if (!graph.reminders.hasPermission()) {
                    RowDivider()
                    NavRow("Turn on notifications", titleColor = c.accent) {
                        val activity = hostActivity as? MainActivity
                        scope.launch {
                            if (activity?.requestNotificationPermission() != true) {
                                context.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName))
                            }
                            graph.rescheduleReminders()
                        }
                    }
                }
            }
            Footnote("The two windows that legally close are always announced, for everybody, whatever is switched off here. These are the rest: the dates Baby Docs suggests, three days out, and one Sunday message about the week ahead that stays silent on a week with nothing in it. Any single task can also carry a reminder you set yourself.")
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Pages that leave the phone")
            Card(padding = PaddingValues(0.dp)) {
                children.forEachIndexed { i, child ->
                    if (i > 0) RowDivider()
                    NavRow(
                        if (children.size > 1) "Put ${child.displayName}'s dates in a calendar" else "Put the dates in a calendar",
                        icon = Icons.Rounded.CalendarMonth, modifier = Modifier.testTag("export-calendar"),
                    ) {
                        val ics = CalendarExporter.ics(child, graph.store.data)
                        if (!ics.contains("BEGIN:VEVENT")) message = "Nothing on the plan yet." else if (!shareFile(context, "${child.displayName}-deadlines.ics", ics, "text/calendar")) {
                            message = "The calendar file could not be written. Try again after freeing some space."
                        }
                    }
                }
            }
            Footnote("The calendar file carries the dates, why each one exists and the official link, and nothing else: no notes, no confirmation numbers, and nothing at all from the document vault. Import it and the deadlines sit beside the appointments they are competing with, where the other parent can see them too.")
        }
        item {
            LocalGraph.current.store.revision
            SecondaryButton("Restore purchases") { scope.launch { graph.subscriptions.restorePurchases() } }
            Footnote("Anything already in the document vault stays readable if a subscription lapses. Lapsing stops you adding more; it never takes back what is there.")
            if (graph.subscriptions.hasReviewAccess) Footnote("Plus is unlocked with the Google Play review code on this device.")
        }
    }
    message?.let { AlertDialog(modifier = DialogTags, onDismissRequest = { message = null }, text = { Text(it) }, confirmButton = { TextButton(onClick = { message = null }) { Text("OK") } }) }
}

/** Writes an export to the cache's exports folder and opens the share sheet. Never touches the vault. */
fun shareFile(context: android.content.Context, name: String, text: String, mime: String): Boolean = runCatching {
    val safe = name.split(Regex("[^A-Za-z0-9.]+")).filter { it.isNotEmpty() }.joinToString("-").ifEmpty { "baby-docs" }
    val dir = File(context.cacheDir, "exports").apply { mkdirs() }
    val file = File(dir, safe).apply { writeText(text) }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val send = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    true
}.getOrDefault(false)

fun shareText(context: android.content.Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    runCatching { context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** The plan as an order rather than as dates: the app's own opinion, labelled as one. Plus. */
@Composable
fun TimelineScreen() {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val c = AppTheme.colors
    graph.store.revision
    if (!graph.subscriptions.isPro) {
        LaunchedEffect(Unit) { nav.pop(); nav.push(Overlay.Paywall("timeline")) }
        return
    }
    val data = graph.store.data
    Page("Timeline", onBack = { nav.pop() }) {
        item { LocalGraph.current.store.revision; Footnote("Every date on your plan is somebody else's. The order is Baby Docs' own opinion, and a closing window always goes first.") }
        data.liveChildren.forEach { child ->
            val groups = PlanTimeline.groups(data.liveTasks(child), { data.child(it.childId)?.birthDate })
            if (data.liveChildren.size > 1) item { SectionHeader(child.displayName) }
            groups.forEach { group ->
                item(key = "${child.id}-${group.phase}") {
                    SectionHeader(group.phase.title, blurb = group.phase.blurb)
                    Card(padding = PaddingValues(0.dp)) {
                        group.steps.forEachIndexed { i, step ->
                            if (i > 0) RowDivider()
                            Column(Modifier.fillMaxWidth().padding(AppTheme.spacing)) {
                                Text(step.title, style = Type.body, color = if (step.isDone) c.secondary else c.label, textDecoration = if (step.isDone) TextDecoration.LineThrough else null)
                                if (step.reason.isNotEmpty()) Text(step.reason, style = Type.footnote, color = c.secondary)
                                step.dueAt?.let { if (!step.isDone) Text(it.medium(), style = Type.caption, color = AppTheme.urgency(step.deadlineKind, null)) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ExportScreen(childID: UUID, kind: ExportKind) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val context = LocalContext.current
    val data = graph.store.data
    val child = data.child(childID)
    if (child == null || !graph.subscriptions.isPro) {
        LaunchedEffect(Unit) { nav.pop() }
        return
    }
    val text = remember(childID, kind) {
        if (kind == ExportKind.SUMMARY) PlanExporter.summary(child, data.profile, data) else PlanExporter.employerPacket(child, data.profile, data)
    }
    Page(if (kind == ExportKind.SUMMARY) "Printable summary" else "Employer packet", onBack = { nav.pop() }) {
        item { LocalGraph.current.store.revision; PrimaryButton("Share or print", tag = "export-share") { shareText(context, text) } }
        item { LocalGraph.current.store.revision; Card { Text(text, style = Type.footnote.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace), color = AppTheme.colors.label) } }
    }
}

/** Sending the plan is free: the link, the summary and the packet for this child. */
@Composable
fun SharePlanScreen(childID: UUID) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val c = AppTheme.colors
    val context = LocalContext.current
    val data = graph.store.data
    val child = data.child(childID) ?: run { LaunchedEffect(Unit) { nav.pop() }; return }
    val plus = graph.subscriptions.isPro
    Page("Send the plan", onBack = { nav.pop() }) {
        item {
            LocalGraph.current.store.revision
            SectionHeader("The other parent")
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Send the plan", icon = Icons.Rounded.EventAvailable, modifier = Modifier.testTag("send-link")) {
                    shareText(context, PlanSeed.make(child, data.profile).shareURL())
                }
            }
            Footnote(
                "They tap the link and their phone builds the same plan: the same tasks, the same dates, their own reminders. Their copy starts blank on who has done what.\n\n" +
                    "The link carries the answers that build a plan: ${child.displayName}'s first name and date of birth, where the birth was registered, where you live, your household answers, and, for a job-based plan, the plan name and benefits contact if you entered them. No completed tasks, no notes, no confirmation numbers and no photographs. Anyone the link is forwarded to can read it, so send it the way you would send a page of a form.",
            )
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Printable")
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Printable summary", value = if (plus) "" else "Plus", icon = Icons.Rounded.Description) {
                    if (plus) nav.push(Overlay.Export(childID, ExportKind.SUMMARY)) else nav.push(Overlay.Paywall("summary"))
                }
            }
            Footnote("Plain text you can print, paste into a message or hand to whoever is driving to the appointment. It never includes the Social Security number.")
        }
        if (data.profile.insuranceKind == InsuranceKind.EMPLOYER) {
            item {
                LocalGraph.current.store.revision
                SectionHeader("For work")
                Card(padding = PaddingValues(0.dp)) {
                    NavRow("Employer packet", value = if (plus) "" else "Plus", icon = Icons.Rounded.Description) {
                        if (plus) nav.push(Overlay.Export(childID, ExportKind.PACKET)) else nav.push(Overlay.Paywall("packet"))
                    }
                }
                Footnote("The qualifying-life-event page HR asks for: the event, the date, what you are enclosing and where the enrollment window comes from. The 30-day window is the hardest deadline in this app, and it is missed more often by sending something incomplete than by forgetting.")
            }
        }
        item { LocalGraph.current.store.revision; Text("The link carries your answers between two phones. Baby Docs has no server to keep a copy on, and the payload rides in the part of the address a browser never sends anywhere.", style = Type.caption, color = c.secondary, modifier = Modifier.padding(4.dp)) }
    }
}

/** A plan link opened on this phone: confirm, then rebuild from the answers. Work already done is kept. */
@Composable
fun ImportPlanScreen(payload: String) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val c = AppTheme.colors
    val seed = remember(payload) { PlanSeed.decodeURL(payload) }
    if (seed == null) {
        AlertDialog(
            modifier = DialogTags,
            onDismissRequest = { nav.pop() },
            text = { Text("This link does not hold a plan Baby Docs can read.") },
            confirmButton = { TextButton(onClick = { nav.pop() }) { Text("OK") } },
        )
        return
    }
    val data = graph.store.data
    val match = data.children.firstOrNull { it.id == seed.childID && !it.isEphemeralDraft }
    Page("A plan was shared with you", onBack = { nav.pop() }) {
        item {
            LocalGraph.current.store.revision
            SectionHeader("What was sent")
            Card {
                Text("${seed.name.ifBlank { "A baby" }}, born ${seed.birthDate.medium()} in ${USState.displayName(seed.birthStateCode)}", style = Type.headline, color = c.label)
                Text("Living in ${USState.displayName(seed.residenceStateCode)}. Coverage: ${InsuranceKind.of(seed.insuranceKind).label}.", style = Type.subheadline, color = c.secondary)
            }
            Footnote("These answers, and nothing else. No completed tasks, no documents and no photographs travel in a link.")
        }
        item {
            LocalGraph.current.store.revision
            Footnote(
                if (match == null) "Nothing on this phone obviously matches, so this will be added as another child. Twins share a birth date and a birth state, so Baby Docs will not guess between them."
                else "The household answers above replace the ones on this phone, and update ${match.displayName}. What you have already done is kept: completed tasks, notes, confirmations and your documents are untouched.",
            )
            Spacer(Modifier.height(AppTheme.spacing))
            PrimaryButton(if (match == null) "Replace my answers and add this child" else "Replace my answers and update ${match.displayName}", tag = "import-confirm") {
                graph.store.commit { d ->
                    d.profile.apply {
                        residenceStateCode = seed.residenceStateCode
                        parentage = ParentageSituation.of(seed.parentage)
                        secondParentOnRecord = seed.secondParentOnRecord
                        insuranceKind = InsuranceKind.of(seed.insuranceKind)
                        marketplaceKind = MarketplaceKind.of(seed.marketplaceKind)
                        employerPlanName = seed.employerPlanName.orEmpty()
                        benefitsContactNote = seed.benefitsContactNote.orEmpty()
                        hasDependentCareFSA = seed.hasDependentCareFSA
                        wantsPassport = seed.wantsPassport
                        wants529 = seed.wants529
                        wantsNewbornAccount = seed.wantsNewbornAccount
                        parentalLeaveTakers = ParentalLeaveTakers.parse(seed.parentalLeaveTakers)
                            ?: if (seed.takingParentalLeave) ParentalLeaveTakers.ONE_PARENT else ParentalLeaveTakers.NOBODY
                        updatedAt = System.currentTimeMillis()
                    }
                    val child = match ?: Child(id = seed.childID ?: UUID.randomUUID(), colorIndex = d.children.size).also { d.children += it }
                    child.name = seed.name
                    child.birthDate = seed.birthDate
                    child.birthStateCode = seed.birthStateCode
                    child.birthCounty = seed.birthCounty
                    child.isUSCitizen = seed.isUSCitizen
                    child.deletedAt = null
                    child.updatedAt = System.currentTimeMillis()
                }
                graph.rescheduleReminders()
                nav.overlays.clear()
            }
            SecondaryButton("Not now") { nav.pop() }
            Footnote("Your phone will run the same rules and produce the same deadlines.")
        }
    }
}
