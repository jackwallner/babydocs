package com.jackwallner.babydocs.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AttachMoney
import androidx.compose.material.icons.rounded.ChildCare
import androidx.compose.material.icons.rounded.Flight
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.TaskAlt
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.Work
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.babydocs.MainActivity
import com.jackwallner.babydocs.data.PlanExporter
import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.MarketplaceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.ParentalLeaveTakers
import com.jackwallner.babydocs.rules.RequirementEngine
import com.jackwallner.babydocs.ui.CountyPickerRow
import com.jackwallner.babydocs.ui.DateRow
import com.jackwallner.babydocs.ui.LocalGraph
import com.jackwallner.babydocs.ui.StatePickerRow
import com.jackwallner.babydocs.ui.theme.AppTheme
import com.jackwallner.babydocs.ui.theme.Card
import com.jackwallner.babydocs.ui.theme.ChoiceRow
import com.jackwallner.babydocs.ui.theme.Footnote
import com.jackwallner.babydocs.ui.theme.Hero
import com.jackwallner.babydocs.ui.theme.PrimaryButton
import com.jackwallner.babydocs.ui.theme.RowDivider
import com.jackwallner.babydocs.ui.theme.SecondaryButton
import com.jackwallner.babydocs.ui.theme.SectionHeader
import com.jackwallner.babydocs.ui.theme.ToggleRow
import com.jackwallner.babydocs.ui.theme.Type
import kotlinx.coroutines.launch
import java.time.LocalDate

private enum class Step { WELCOME, BABY, HOUSEHOLD, COVERAGE, LEAVE, NEWBORN_ACCOUNT, PLAN_529, PASSPORT, DONE, PLUS }

/**
 * The intake (`OnboardingFlow.swift`): every question is the same shape, hero,
 * form and a pinned footer, and "Not sure" is an answer everywhere it is
 * offered. The plan is written by [finish], then the plan-is-ready page and
 * the one notification prompt are actually shown before the tabs appear.
 */
@Composable
fun OnboardingScreen(activity: MainActivity, onFinished: () -> Unit) {
    val graph = LocalGraph.current
    val scope = rememberCoroutineScope()
    var step by rememberSaveable { mutableStateOf(Step.WELCOME) }
    var name by rememberSaveable { mutableStateOf("") }
    var birthDate by rememberSaveable { mutableStateOf<String?>(null) }
    var birthDateConfirmed by rememberSaveable { mutableStateOf(false) }
    var birthState by rememberSaveable { mutableStateOf("") }
    var birthCounty by rememberSaveable { mutableStateOf("") }
    var citizen by rememberSaveable { mutableStateOf<Boolean?>(null) }
    var residence by rememberSaveable { mutableStateOf("") }
    var parentage by rememberSaveable { mutableStateOf<ParentageSituation?>(null) }
    var secondParentOnRecord by rememberSaveable { mutableStateOf(false) }
    var insurance by rememberSaveable { mutableStateOf<InsuranceKind?>(null) }
    var marketplace by rememberSaveable { mutableStateOf(MarketplaceKind.UNKNOWN) }
    var planName by rememberSaveable { mutableStateOf("") }
    var contact by rememberSaveable { mutableStateOf("") }
    var fsa by rememberSaveable { mutableStateOf(false) }
    var leave by rememberSaveable { mutableStateOf<ParentalLeaveTakers?>(null) }
    var newbornAccount by rememberSaveable { mutableStateOf(true) }
    var wants529 by rememberSaveable { mutableStateOf(false) }
    var passport by rememberSaveable { mutableStateOf(false) }
    var taskCount by rememberSaveable { mutableIntStateOf(0) }
    var askedReminders by rememberSaveable { mutableStateOf(false) }

    fun finish() {
        val isCitizen = citizen ?: return
        val day = birthDate?.let(LocalDate::parse) ?: return
        val child = Child(name = name.trim(), birthDate = day, birthStateCode = birthState, birthCounty = birthCounty, isUSCitizen = isCitizen)
        val saved = graph.store.commit { data ->
            data.profile.apply {
                residenceStateCode = residence
                this.parentage = parentage ?: ParentageSituation.UNKNOWN
                this.secondParentOnRecord = parentage == ParentageSituation.UNMARRIED_BOTH_PARENTS && secondParentOnRecord
                insuranceKind = insurance ?: InsuranceKind.UNKNOWN
                marketplaceKind = if (insurance == InsuranceKind.MARKETPLACE) marketplace else MarketplaceKind.UNKNOWN
                employerPlanName = if (insurance == InsuranceKind.EMPLOYER) planName.trim() else ""
                benefitsContactNote = if (insurance == InsuranceKind.EMPLOYER) contact.trim() else ""
                hasDependentCareFSA = fsa
                wantsPassport = passport
                this.wants529 = wants529
                wantsNewbornAccount = newbornAccount
                parentalLeaveTakers = leave ?: ParentalLeaveTakers.NOBODY
                updatedAt = System.currentTimeMillis()
            }
            data.children += child
        }
        // A failed write leaves the intake open rather than celebrating a plan that is not on disk.
        if (!saved) return
        graph.navigator.selectedChildID = child.id
        taskCount = graph.store.data.liveTasks(child).size
        step = Step.DONE
    }

    val previous: Step? = when (step) {
        Step.WELCOME, Step.DONE, Step.PLUS -> null
        else -> Step.entries[step.ordinal - 1]
    }
    BackHandler(enabled = previous != null) { previous?.let { step = it } }

    val c = AppTheme.colors
    AnimatedContent(step, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "intake") { current ->
        when (current) {
            Step.WELCOME -> StepScaffold(
                onBack = null, footerTitle = "Get started", footerNote = "About a minute. Nothing is submitted anywhere.",
                footerTag = "intake-start", onContinue = { step = Step.BABY },
            ) {
                Spacer(Modifier.height(48.dp))
                Icon(Icons.Rounded.TaskAlt, contentDescription = null, tint = c.accent, modifier = Modifier.size(56.dp))
                Spacer(Modifier.height(AppTheme.looseSpacing))
                Text("The paperwork, in order", style = Type.largeTitle, color = c.label)
                Spacer(Modifier.height(AppTheme.spacing))
                Text(
                    "Answer a few questions about your household and you get the tasks that actually apply to you, the dates that actually close, and a link to the office that actually issues each thing.",
                    style = Type.body, color = c.secondary,
                )
            }

            Step.BABY -> {
                val note = when {
                    birthDate == null || !birthDateConfirmed -> "Check the date of birth to carry on."
                    birthState.isEmpty() -> "Pick the state of birth to carry on."
                    citizen == null -> "Choose the baby's citizenship to carry on."
                    else -> ""
                }
                StepScaffold(
                    onBack = { step = Step.WELCOME }, footerNote = note, enabled = note.isEmpty(), footerTag = "intake-continue",
                    onContinue = { step = Step.HOUSEHOLD },
                ) {
                    Hero(Icons.Rounded.ChildCare, "Who is the plan for?", "Every deadline counts from the date of birth, and the state that registered it issues the certificate.")
                    SectionHeader("Date of birth")
                    Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                        OutlinedTextField(
                            value = name, onValueChange = { name = it }, label = { Text("First name (optional)") }, singleLine = true,
                            modifier = Modifier.fillMaxWidth().padding(AppTheme.spacing).testTag("name"),
                        )
                        RowDivider()
                        DateRow("Date of birth", birthDate?.let(LocalDate::parse), tag = "birth-date", notAfter = LocalDate.now()) {
                            if (it.toString() != birthDate) birthDateConfirmed = false
                            birthDate = it.toString()
                        }
                        RowDivider()
                        ToggleRow("I checked this date", birthDateConfirmed, enabled = birthDate != null, modifier = Modifier.testTag("date-confirmed")) { birthDateConfirmed = it }
                    }
                    Footnote("The one answer worth double-checking, because every other date in the app is derived from it.")
                    SectionHeader("Where the birth was registered")
                    Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                        StatePickerRow("State of birth", birthState, tag = "birth-state") {
                            if (it != birthState) birthCounty = ""
                            birthState = it
                            if (residence.isEmpty()) residence = it
                        }
                        if (birthState.isNotEmpty()) {
                            RowDivider()
                            CountyPickerRow(birthState, birthCounty) { birthCounty = it }
                        }
                    }
                    Footnote(
                        if (birthState.isEmpty()) "The certificate comes from where the birth was registered, not from where you live now."
                        else "The certificate comes from where the birth was registered. The county is asked for because in many states its office is faster than the state one.",
                    )
                    SectionHeader("Citizenship")
                    Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                        ChoiceRow("US citizen", citizen == true, modifier = Modifier.testTag("citizen-yes")) { citizen = true }
                        RowDivider()
                        ChoiceRow("Not a US citizen", citizen == false, modifier = Modifier.testTag("citizen-no")) { citizen = false }
                    }
                    Footnote("Only one rule turns on this: the \$1,000 federal newborn account is for US citizen children.")
                }
            }

            Step.HOUSEHOLD -> {
                val note = when {
                    residence.isEmpty() -> "Pick the state you live in to carry on."
                    parentage == null -> "Choose the parents' situation, including Prefer not to say, to carry on."
                    else -> ""
                }
                StepScaffold(onBack = { step = Step.BABY }, footerNote = note, enabled = note.isEmpty(), footerTag = "intake-continue", onContinue = { step = Step.COVERAGE }) {
                    Hero(
                        Icons.Rounded.Home, "Where do you live, and who is on the record?",
                        "Where you live helps route the agency. Leave rules also depend on the employer and the state where that parent works. Who is on the record decides one legally significant task.",
                    )
                    SectionHeader("Where you live")
                    Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                        StatePickerRow("State you live in", residence, tag = "residence-state") { residence = it }
                    }
                    Footnote("Sets your Medicaid and CHIP agency, and whether there is a state paid-leave programme to file with.")
                    SectionHeader("Parents")
                    Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                        ParentageSituation.entries.forEachIndexed { i, option ->
                            if (i > 0) RowDivider()
                            ChoiceRow(option.label, parentage == option, modifier = Modifier.testTag("parentage-${option.raw}")) { parentage = option }
                        }
                        if (parentage == ParentageSituation.UNMARRIED_BOTH_PARENTS) {
                            RowDivider()
                            ToggleRow("Both parents already on the birth record", secondParentOnRecord) { secondParentOnRecord = it }
                        }
                    }
                    Footnote(
                        when {
                            parentage == ParentageSituation.UNKNOWN -> "A neutral task will remind you to ask the birth registrar whether parentage paperwork applies. Baby Docs will not assume a legal situation or tell you to sign a form."
                            parentage == ParentageSituation.UNMARRIED_BOTH_PARENTS && !secondParentOnRecord -> "In most states marriage puts the second parent on the record automatically and an unmarried second parent has to establish it deliberately. Your plan will carry that task and your state's own form. Baby Docs will not prepare or file it for you."
                            else -> "This decides one task: in most states marriage puts the second parent on the record automatically, and an unmarried second parent has to establish it deliberately."
                        },
                    )
                }
            }

            Step.COVERAGE -> StepScaffold(
                onBack = { step = Step.HOUSEHOLD },
                footerNote = if (insurance == null) "Choose a coverage answer, including Not sure yet, to carry on." else "",
                enabled = insurance != null, footerTag = "intake-continue", onContinue = { step = Step.LEAVE },
            ) {
                Hero(Icons.Rounded.MedicalServices, "How is the family covered?", "This sets the only two dates in the app that legally close.")
                SectionHeader("Where the coverage comes from")
                Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                    listOf(InsuranceKind.EMPLOYER, InsuranceKind.MARKETPLACE, InsuranceKind.MEDICAID_CHIP, InsuranceKind.NONE, InsuranceKind.UNKNOWN).forEachIndexed { i, option ->
                        if (i > 0) RowDivider()
                        ChoiceRow(option.label, insurance == option, modifier = Modifier.testTag("coverage-${option.raw}")) {
                            if (option != InsuranceKind.EMPLOYER) { planName = ""; contact = "" }
                            insurance = option
                        }
                    }
                }
                val base = "A job-based plan must let you add the baby within 30 days of the birth. The Marketplace gives 60. Miss it and you usually wait for open enrollment. Covered both ways? Pick the job plan: it closes first."
                Footnote(if (insurance == InsuranceKind.UNKNOWN) "$base \"Not sure yet\" blocks nothing: you get a task about finding out instead of a date the app guessed." else base)
                if (insurance == InsuranceKind.MARKETPLACE) {
                    SectionHeader("Which marketplace?")
                    Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                        listOf(MarketplaceKind.FEDERAL, MarketplaceKind.STATE, MarketplaceKind.UNKNOWN).forEachIndexed { i, option ->
                            if (i > 0) RowDivider()
                            ChoiceRow(option.label, marketplace == option) { marketplace = option }
                        }
                    }
                    Footnote("The 60 days is the same either way. The site and the sign-in are not: HealthCare.gov will tell a Californian it does not serve them.")
                }
                if (insurance == InsuranceKind.EMPLOYER) {
                    SectionHeader("Which plan? (optional)")
                    Card {
                        OutlinedTextField(planName, { planName = it }, label = { Text("Plan or employer name") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("plan-name"))
                        Spacer(Modifier.height(AppTheme.tightSpacing))
                        OutlinedTextField(contact, { contact = it }, label = { Text("Benefits contact or phone") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    }
                    Footnote("Both go onto the task and into the reminder, so the notification names the plan and who to ring. Neither changes the deadline, and neither leaves this phone.")
                }
                Spacer(Modifier.height(AppTheme.tightSpacing))
                Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                    ToggleRow("We have a dependent care FSA", fsa, modifier = Modifier.testTag("fsa")) { fsa = it }
                }
                Footnote("A separate election from the health plan, with its own window, and the one most often missed. Your employer sets that window rather than the law, so it is shown as a suggestion to confirm.")
            }

            Step.LEAVE -> StepScaffold(
                onBack = { step = Step.COVERAGE },
                footerNote = if (leave == null) "Pick one to carry on. \"Nobody\" is a real answer here." else "",
                enabled = leave != null, footerTag = "intake-continue", onContinue = { step = Step.NEWBORN_ACCOUNT },
            ) {
                Hero(Icons.Rounded.Work, "Who is taking parental leave?", "Paid or unpaid time off after the birth, from an employer, a state programme, or federal job protection.")
                SectionHeader("Parental leave")
                Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                    listOf(ParentalLeaveTakers.ONE_PARENT, ParentalLeaveTakers.BOTH_PARENTS, ParentalLeaveTakers.NOBODY).forEachIndexed { i, option ->
                        if (i > 0) RowDivider()
                        ChoiceRow(option.label, leave == option, modifier = Modifier.testTag("leave-${option.raw}")) { leave = option }
                    }
                }
                Footnote(
                    when (leave) {
                        null -> "Nothing is selected yet. Pick one and this will say what it puts on the plan."
                        ParentalLeaveTakers.NOBODY -> "Nothing about leave goes on your plan. You can change this later without redoing any of this."
                        ParentalLeaveTakers.ONE_PARENT -> "One task, with your state's own programme, the federal rules behind it, and what the employer needs from you."
                        ParentalLeaveTakers.BOTH_PARENTS -> "Two tasks, one for each parent. Each claim goes to a different employer, and the rules for a second parent's bonding leave are often not the rules for the birth parent's."
                    },
                )
                Disclosure(
                    "Why leave is the one that pays you",
                    "The states that run paid family leave mostly require the claim inside a window measured in weeks, and it is the one piece of newborn paperwork that pays you rather than costing you. Federal job protection under FMLA is separate again and has its own notice rules. Nobody hands you this: you file for it, with your own employer.",
                )
            }

            Step.NEWBORN_ACCOUNT -> ToggleStep(
                icon = Icons.Rounded.AttachMoney,
                title = "Claim the \$1,000 newborn account?",
                what = "A one-time \$1,000 federal contribution into an investment account for children born between 2025 and 2028. The IRS calls these Trump Accounts, which is the name you will see on irs.gov and on the form itself.",
                detailLabel = "Why almost nobody claims this",
                detail = "It is a thousand dollars, most US citizen newborns can qualify, and it is claimed by election rather than automatically, so a family that has not heard of it simply does not get it. The election needs the baby's Social Security number first, which is why that task sits at the top of your plan. Baby Docs cannot tell you whether you qualify: there are conditions beyond citizenship and a birth year, and the instructions are the only thing that settles them.",
                value = newbornAccount && citizen != false,
                unavailableNote = if (citizen == false) "This one is for US citizen children only, and you said this baby is not one, so it stays off your plan." else null,
                onValue = { newbornAccount = it },
                onBack = { step = Step.LEAVE },
                onContinue = { step = Step.PLAN_529 },
            )

            Step.PLAN_529 -> ToggleStep(
                icon = Icons.Rounded.School,
                title = "Open a 529?",
                what = "A tax-advantaged savings account for education. Most states run their own, several give residents a state tax deduction for paying into it, and you can use another state's if theirs is better.",
                detailLabel = "Why now rather than in a year",
                detail = "Nothing about a 529 is urgent, and this app will not pretend otherwise: there is no deadline and no penalty for opening one next year. It is here because it is far easier to do in the same fortnight you are already gathering a birth certificate and a Social Security number than it is to come back to in eighteen months. Saying yes adds one unhurried task with your state's own plan and what opening an account asks for.",
                value = wants529,
                onValue = { wants529 = it },
                onBack = { step = Step.NEWBORN_ACCOUNT },
                onContinue = { step = Step.PASSPORT },
            )

            Step.PASSPORT -> ToggleStep(
                icon = Icons.Rounded.Flight,
                title = "Will the baby need a passport?",
                what = "A US passport for a child under 16. Both parents have to appear in person with the child, or the absent one has to send a notarised consent form.",
                detailLabel = "Why this one has to start earliest",
                detail = "The application needs a certified birth certificate, so it cannot start until that has arrived, and the in-person rule is what catches people out. If there is a trip in the first year, this is the task that has to be started earliest and is almost always started last. It stays blocked on your plan until the certificate is in hand, then explains the appointment and who has to be at it.",
                value = passport,
                onValue = { passport = it },
                onBack = { step = Step.PLAN_529 },
                continueTitle = "Build my plan",
                onContinue = { finish() },
            )

            Step.DONE -> {
                val hasHard = graph.store.data.allLiveTasks().any { it.deadlineKind == com.jackwallner.babydocs.model.DeadlineKind.HARD }
                val offerReminders = hasHard && !askedReminders && !graph.reminders.hasPermission()
                Column(Modifier.fillMaxSize().background(c.page).windowInsetsPadding(WindowInsets.statusBars).windowInsetsPadding(WindowInsets.navigationBars)) {
                    Column(
                        Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.margin),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(Icons.Rounded.Verified, contentDescription = null, tint = c.green, modifier = Modifier.size(56.dp))
                        Spacer(Modifier.height(AppTheme.spacing))
                        Text("Your plan is ready", style = Type.title, color = c.label, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(6.dp))
                        Text("$taskCount tasks apply to your family.", style = Type.body, color = c.secondary, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(AppTheme.spacing))
                        Text(PlanExporter.DISCLAIMER, style = Type.caption, color = c.secondary, textAlign = TextAlign.Center)
                    }
                    Column(Modifier.background(c.surface).padding(horizontal = AppTheme.margin, vertical = AppTheme.spacing), verticalArrangement = Arrangement.spacedBy(AppTheme.tightSpacing)) {
                        if (offerReminders) {
                            PrimaryButton("Remind me before deadlines", tag = "remind-me") {
                                askedReminders = true
                                scope.launch {
                                    activity.requestNotificationPermission()
                                    graph.rescheduleReminders()
                                }
                            }
                            Text(
                                "Two dates in your plan legally close. This is how the app tells you before they do, and it is free.",
                                style = Type.footnote, color = c.secondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                            )
                            SecondaryButton("See my plan", tag = "see-plan") { step = Step.PLUS }
                        } else {
                            PrimaryButton("See my plan", tag = "see-plan") { step = Step.PLUS }
                        }
                    }
                }
            }

            Step.PLUS -> {
                if (graph.subscriptions.isPro) {
                    androidx.compose.runtime.LaunchedEffect(Unit) { onFinished() }
                } else {
                    PlusPurchaseScreen(placement = "onboarding", onDone = onFinished, onSkip = onFinished)
                }
            }
        }
    }
}

@Composable
private fun StepScaffold(
    onBack: (() -> Unit)?,
    footerTitle: String = "Continue",
    footerNote: String = "",
    enabled: Boolean = true,
    footerTag: String,
    onContinue: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val c = AppTheme.colors
    Column(Modifier.fillMaxSize().background(c.page).windowInsetsPadding(WindowInsets.statusBars).windowInsetsPadding(WindowInsets.navigationBars).imePadding()) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) {
                IconButton(onClick = onBack, modifier = Modifier.testTag("back")) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back", tint = c.accent)
                }
            }
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AppTheme.margin, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            content = content,
        )
        // Pinned, with two footnote lines held open so Continue never moves within a screen.
        Column(Modifier.fillMaxWidth().background(c.surface).padding(horizontal = AppTheme.margin, vertical = AppTheme.spacing)) {
            PrimaryButton(footerTitle, enabled = enabled, tag = footerTag, onClick = onContinue)
            Text(
                footerNote.ifEmpty { " \n " }, style = Type.footnote, color = c.secondary, minLines = 2, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
            )
        }
    }
}

@Composable
private fun ToggleStep(
    icon: ImageVector,
    title: String,
    what: String,
    detailLabel: String,
    detail: String,
    value: Boolean,
    onValue: (Boolean) -> Unit,
    onBack: () -> Unit,
    onContinue: () -> Unit,
    continueTitle: String = "Continue",
    unavailableNote: String? = null,
) {
    StepScaffold(onBack = onBack, footerTitle = continueTitle, footerTag = "intake-continue", onContinue = onContinue) {
        Hero(icon, title, what)
        SectionHeader("Your answer")
        Card(padding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
            ToggleRow("Add this to my plan", value, enabled = unavailableNote == null, modifier = Modifier.testTag("add-to-plan"), onChange = onValue)
        }
        Footnote(unavailableNote ?: "You can change this later in the household answers without redoing any of this.")
        Disclosure(detailLabel, detail)
    }
}

/** `OnboardingDisclosure`: the explanation is collapsed, not cut. */
@Composable
fun Disclosure(label: String, text: String) {
    var open by rememberSaveable { mutableStateOf(false) }
    val c = AppTheme.colors
    Column(Modifier.fillMaxWidth().padding(top = AppTheme.tightSpacing)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch).clickable { open = !open }.padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = Type.subheadline, color = c.accent, modifier = Modifier.weight(1f))
            Icon(if (open) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown, contentDescription = null, tint = c.accent)
        }
        if (open) Text(text, style = Type.subheadline, color = c.secondary, modifier = Modifier.padding(horizontal = 4.dp))
    }
}
