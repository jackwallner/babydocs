package com.jackwallner.babydocs.ui.screens

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.MarketplaceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.ParentalLeaveTakers
import com.jackwallner.babydocs.ui.LocalGraph
import com.jackwallner.babydocs.ui.StatePickerRow
import com.jackwallner.babydocs.ui.theme.AppTheme
import com.jackwallner.babydocs.ui.theme.Card
import com.jackwallner.babydocs.ui.theme.ChoiceRow
import com.jackwallner.babydocs.ui.theme.Footnote
import com.jackwallner.babydocs.ui.theme.Page
import com.jackwallner.babydocs.ui.theme.PrimaryButton
import com.jackwallner.babydocs.ui.theme.RowDivider
import com.jackwallner.babydocs.ui.theme.SectionHeader
import com.jackwallner.babydocs.ui.theme.ToggleRow

/** `HouseholdEditorView`: the answers every child's plan is built from. Saving rebuilds every plan. */
@Composable
fun HouseholdScreen() {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val p = graph.store.data.profile
    var residence by rememberSaveable { mutableStateOf(p.residenceStateCode) }
    var parentage by rememberSaveable { mutableStateOf(p.parentage) }
    var onRecord by rememberSaveable { mutableStateOf(p.secondParentOnRecord) }
    var insurance by rememberSaveable { mutableStateOf(p.insuranceKind) }
    var marketplace by rememberSaveable { mutableStateOf(p.marketplaceKind) }
    var planName by rememberSaveable { mutableStateOf(p.employerPlanName) }
    var contact by rememberSaveable { mutableStateOf(p.benefitsContactNote) }
    var fsa by rememberSaveable { mutableStateOf(p.hasDependentCareFSA) }
    var leave by rememberSaveable { mutableStateOf(p.parentalLeaveTakers) }
    var newborn by rememberSaveable { mutableStateOf(p.wantsNewbornAccount) }
    var plan529 by rememberSaveable { mutableStateOf(p.wants529) }
    var passport by rememberSaveable { mutableStateOf(p.wantsPassport) }

    Page("Household", onBack = { nav.pop() }) {
        item {
            LocalGraph.current.store.revision
            SectionHeader("Where you live")
            Card(padding = PaddingValues(AppTheme.spacing * 0)) {
                StatePickerRow("State you live in", residence, tag = "household-state") { residence = it }
            }
            Footnote("Decides the Medicaid and CHIP agency, and whether there is a state paid-leave programme to file with.")
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Parents")
            Card(padding = PaddingValues(AppTheme.spacing * 0)) {
                ParentageSituation.entries.forEachIndexed { i, option ->
                    if (i > 0) RowDivider()
                    ChoiceRow(option.label, parentage == option) { parentage = option }
                }
                if (parentage == ParentageSituation.UNMARRIED_BOTH_PARENTS) {
                    RowDivider()
                    ToggleRow("Both parents on the birth record", onRecord) { onRecord = it }
                }
            }
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Health coverage")
            Card(padding = PaddingValues(AppTheme.spacing * 0)) {
                listOf(InsuranceKind.EMPLOYER, InsuranceKind.MARKETPLACE, InsuranceKind.MEDICAID_CHIP, InsuranceKind.NONE, InsuranceKind.UNKNOWN).forEachIndexed { i, option ->
                    if (i > 0) RowDivider()
                    ChoiceRow(option.label, insurance == option, modifier = Modifier.testTag("household-coverage-${option.raw}")) { insurance = option }
                }
                if (insurance == InsuranceKind.MARKETPLACE) {
                    RowDivider()
                    listOf(MarketplaceKind.FEDERAL, MarketplaceKind.STATE, MarketplaceKind.UNKNOWN).forEach { option ->
                        ChoiceRow(option.label, marketplace == option) { marketplace = option }
                    }
                }
                if (insurance == InsuranceKind.EMPLOYER) {
                    RowDivider()
                    OutlinedTextField(planName, { planName = it }, label = { Text("Plan or employer name") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(AppTheme.spacing))
                    OutlinedTextField(contact, { contact = it }, label = { Text("Benefits contact or phone") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(horizontal = AppTheme.spacing).padding(bottom = AppTheme.spacing))
                }
                RowDivider()
                ToggleRow("Dependent care FSA", fsa) { fsa = it }
            }
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Parental leave")
            Card(padding = PaddingValues(AppTheme.spacing * 0)) {
                listOf(ParentalLeaveTakers.ONE_PARENT, ParentalLeaveTakers.BOTH_PARENTS, ParentalLeaveTakers.NOBODY).forEachIndexed { i, option ->
                    if (i > 0) RowDivider()
                    ChoiceRow(option.label, leave == option) { leave = option }
                }
            }
            Footnote("Both parents taking leave means two claims, with two employers and two windows, so it puts two tasks on the plan rather than one.")
        }
        item {
            LocalGraph.current.store.revision
            SectionHeader("Optional tasks")
            Card(padding = PaddingValues(AppTheme.spacing * 0)) {
                ToggleRow("\$1,000 newborn account", newborn) { newborn = it }
                RowDivider()
                ToggleRow("529 college savings", plan529) { plan529 = it }
                RowDivider()
                ToggleRow("Passport", passport) { passport = it }
            }
        }
        item {
            LocalGraph.current.store.revision
            Spacer(Modifier.height(AppTheme.spacing))
            PrimaryButton("Done", enabled = residence.isNotEmpty(), tag = "household-done") {
                val saved = graph.store.commit { d ->
                    d.profile.apply {
                        residenceStateCode = residence
                        this.parentage = parentage
                        secondParentOnRecord = parentage == ParentageSituation.UNMARRIED_BOTH_PARENTS && onRecord
                        insuranceKind = insurance
                        marketplaceKind = if (insurance == InsuranceKind.MARKETPLACE) marketplace else MarketplaceKind.UNKNOWN
                        employerPlanName = if (insurance == InsuranceKind.EMPLOYER) planName.trim() else ""
                        benefitsContactNote = if (insurance == InsuranceKind.EMPLOYER) contact.trim() else ""
                        hasDependentCareFSA = fsa
                        parentalLeaveTakers = leave
                        wantsNewbornAccount = newborn
                        wants529 = plan529
                        wantsPassport = passport
                        updatedAt = System.currentTimeMillis()
                    }
                }
                if (saved) {
                    graph.rescheduleReminders()
                    nav.pop()
                }
            }
        }
    }
}
