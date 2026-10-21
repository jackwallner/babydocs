package com.jackwallner.babydocs.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.jackwallner.babydocs.model.USState
import com.jackwallner.babydocs.rules.USCounties
import com.jackwallner.babydocs.ui.theme.AppTheme
import com.jackwallner.babydocs.ui.theme.DialogTags
import com.jackwallner.babydocs.ui.theme.NavRow
import com.jackwallner.babydocs.ui.theme.Type
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** A row that opens a searchable list of states and territories. */
@Composable
fun StatePickerRow(title: String, code: String, tag: String, onPick: (String) -> Unit) {
    var open by rememberSaveable { mutableStateOf(false) }
    NavRow(title, value = if (code.isEmpty()) "Select" else USState.displayName(code), modifier = Modifier.testTag(tag)) { open = true }
    if (open) {
        SearchListDialog(
            title = title,
            options = USState.all.map { it.code to it.name },
            onDismiss = { open = false },
            onPick = { onPick(it); open = false },
        )
    }
}

/** County names only: it spells the county correctly and routes nothing. Falls back to free text. */
@Composable
fun CountyPickerRow(stateCode: String, county: String, onPick: (String) -> Unit) {
    var open by rememberSaveable { mutableStateOf(false) }
    val names = USCounties.names(stateCode)
    if (stateCode.isEmpty()) return
    if (names.isEmpty()) {
        OutlinedTextField(
            value = county, onValueChange = onPick, label = { Text("County (optional)") },
            singleLine = true, modifier = Modifier.fillMaxWidth().padding(horizontal = AppTheme.spacing, vertical = 6.dp),
        )
        return
    }
    NavRow("County", value = county.ifEmpty { "Not sure" }, modifier = Modifier.testTag("county")) { open = true }
    if (open) {
        SearchListDialog(
            title = "County",
            options = listOf("" to "Not sure") + names.map { it to it },
            onDismiss = { open = false },
            onPick = { onPick(it); open = false },
        )
    }
}

@Composable
fun SearchListDialog(title: String, options: List<Pair<String, String>>, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    var query by remember { mutableStateOf("") }
    val filtered = options.filter { query.isBlank() || it.second.contains(query.trim(), ignoreCase = true) }
    AlertDialog(
        modifier = DialogTags,
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                OutlinedTextField(query, { query = it }, label = { Text("Search") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("search"))
                LazyColumn(Modifier.heightIn(max = 380.dp).padding(top = 8.dp)) {
                    items(filtered, key = { it.first }) { (value, label) ->
                        Text(
                            label, style = Type.body,
                            modifier = Modifier.fillMaxWidth().clickable { onPick(value) }.padding(vertical = 12.dp).testTag("option-$value"),
                        )
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

val mediumDate: DateTimeFormatter get() = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

fun LocalDate.medium(): String = format(mediumDate)

/** A date row with Material's picker. Dates are calendar days, read and written in UTC like the picker itself. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateRow(
    title: String,
    date: LocalDate?,
    tag: String,
    placeholder: String = "Choose",
    notAfter: LocalDate? = null,
    notBefore: LocalDate? = null,
    onPick: (LocalDate) -> Unit,
) {
    var open by rememberSaveable { mutableStateOf(false) }
    NavRow(title, value = date?.medium() ?: placeholder, modifier = Modifier.testTag(tag)) { open = true }
    if (!open) return
    val state = rememberDatePickerState(
        initialSelectedDateMillis = (date ?: notAfter ?: LocalDate.now()).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                val day = Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate()
                return (notAfter == null || !day.isAfter(notAfter)) && (notBefore == null || !day.isBefore(notBefore))
            }
        },
    )
    DatePickerDialog(
        modifier = DialogTags,
        onDismissRequest = { open = false },
        confirmButton = {
            TextButton(onClick = {
                state.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }
                open = false
            }, modifier = Modifier.testTag("date-ok")) { Text("OK") }
        },
        dismissButton = { TextButton(onClick = { open = false }) { Text("Cancel") } },
    ) { DatePicker(state) }
}
