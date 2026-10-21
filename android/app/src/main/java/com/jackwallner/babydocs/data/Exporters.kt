package com.jackwallner.babydocs.data

import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.FamilyProfile
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.RequirementTask
import com.jackwallner.babydocs.model.SSNStatus
import com.jackwallner.babydocs.model.USState
import com.jackwallner.babydocs.model.toLocalDate
import com.jackwallner.babydocs.rules.RequirementCatalog
import com.jackwallner.babydocs.rules.TaskPlanner
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * The printable summary and the employer packet (`PlanExporter.swift`). Both
 * print the Social Security *status* and never a number; any text shaped
 * like one is redacted on the way out.
 */
object PlanExporter {
    const val DISCLAIMER = "Baby Docs tracks paperwork. It is not legal, tax, medical or insurance advice, it does not file anything on your behalf, and deadlines set by your own plan or your own state override anything printed here. Check the official page linked against each task before you rely on a date."

    private val medium: DateTimeFormatter get() = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

    private fun day(date: LocalDate) = date.format(medium)
    private fun moment(millis: Long) = day(millis.toLocalDate())
    private fun safe(value: String) = PlanSeed.safeExternalText(value)

    fun summary(child: Child, profile: FamilyProfile, data: BabyData, today: LocalDate = LocalDate.now()): String {
        val lines = mutableListOf<String>()
        lines += "NEWBORN PAPERWORK: ${safe(child.displayName).uppercase()}"
        lines += "Born ${day(child.birthDate)}${birthPlaceSuffix(child)}"
        if (profile.residenceStateCode.isNotEmpty()) lines += "Living in ${USState.displayName(profile.residenceStateCode)}"
        lines += "Prepared ${day(today)}"
        lines += ""
        lines += identitySection(child)
        lines += ""

        val tasks = data.liveTasks(child)
        val overview = TaskPlanner.overview(tasks, today)
        lines += "PROGRESS: ${overview.doneCount} of ${overview.totalCount} done"
        val past = overview.pastHardDeadline
        val next = overview.nextHardDeadline
        lines += when {
            past != null && overview.pastHardDeadlineTitle != null -> "HARD DEADLINE PASSED: ${day(past)}, ${overview.pastHardDeadlineTitle}"
            next != null && overview.nextHardDeadlineTitle != null -> "NEXT HARD DEADLINE: ${day(next)}, ${overview.nextHardDeadlineTitle}"
            else -> "HARD DEADLINES: none outstanding"
        }
        lines += ""

        for ((bucket, items) in TaskPlanner.buckets(tasks, today)) {
            if (bucket == TaskPlanner.Bucket.DONE) continue
            lines += bucket.title.uppercase()
            items.forEach { lines += taskLines(it, data, today) }
            lines += ""
        }

        val done = tasks.filter { it.isDone }
        lines += "DONE"
        if (done.isEmpty()) {
            lines += "  nothing yet"
        } else {
            for (task in TaskPlanner.sorted(done)) {
                val by = if (task.completedByName.isEmpty()) "" else " by ${safe(task.completedByName)}"
                lines += "  ${safe(task.title)}$by"
                data.liveReceipts(task).filter { it.value.isNotEmpty() }.forEach {
                    lines += "    ${it.kind.label}: ${safeReceiptValue(it.value)}"
                }
            }
        }
        lines += ""
        lines += DISCLAIMER
        return lines.joinToString("\n")
    }

    fun employerPacket(child: Child, profile: FamilyProfile, data: BabyData, today: LocalDate = LocalDate.now()): String {
        if (profile.insuranceKind != InsuranceKind.EMPLOYER) {
            return "EMPLOYER PACKET NOT APPLICABLE\n\nThis packet is only for job-based health coverage. Check your plan's own enrollment instructions for the coverage selected in Baby Docs."
        }
        val lines = mutableListOf<String>()
        val insurance = data.liveTasks(child).firstOrNull { it.catalogKey == "insurance_employer" }
        lines += "QUALIFYING LIFE EVENT: BIRTH OF A CHILD"
        lines += ""
        lines += "Event: birth"
        lines += "Date of event: ${day(child.birthDate)}"
        if (child.name.isNotBlank()) lines += "Dependent: ${safe(child.name)}"
        lines += "Dependent's date of birth: ${day(child.birthDate)}"
        lines += "Relationship: child"
        insurance?.dueAt?.let { lines += "Enrollment window closes: ${day(it)}" }
        lines += ""
        lines += "REQUESTING"
        lines += "  Add this dependent to my medical coverage, effective the date of birth."
        if (profile.hasDependentCareFSA) lines += "  Change my dependent care FSA election for this qualifying event."
        lines += ""
        lines += "ENCLOSED"
        val documents = insurance?.let(data::liveDocuments).orEmpty()
        if (documents.isEmpty()) {
            lines += "  (see the plan's own document list)"
        } else {
            documents.forEach { lines += "  ${if (it.isOnHand) "[x]" else "[ ]"} ${safe(it.title)}" }
        }
        lines += ""
        lines += "SOCIAL SECURITY NUMBER"
        when (child.ssnStatus) {
            SSNStatus.CARD_RECEIVED -> lines += "  Issued. I will provide it directly on your form, not in this message."
            SSNStatus.REQUESTED_AT_HOSPITAL, SSNStatus.APPLIED_DIRECTLY -> {
                lines += "  Applied for, not yet issued. Most plans accept an enrollment marked"
                lines += "  \"SSN applied for\" and take the number when it arrives. Please confirm"
                lines += "  the enrollment is not held up waiting for it."
            }
            SSNStatus.UNKNOWN -> lines += "  Status not yet confirmed."
        }
        lines += ""
        insurance?.deadlineBasis?.takeIf { it.isNotEmpty() }?.let {
            lines += "WHY THIS WINDOW"
            lines += "  $it"
            lines += ""
        }
        insurance?.officialURLString?.takeIf { it.isNotEmpty() }?.let {
            lines += "  $it"
            lines += ""
        }
        lines += "Prepared ${day(today)} with Baby Docs. Your plan's own rules and"
        lines += "deadlines override anything on this page."
        return lines.joinToString("\n")
    }

    private fun identitySection(child: Child): List<String> {
        val lines = mutableListOf("IDENTITY DOCUMENTS", "  Social Security: ${child.ssnStatus.label}")
        child.ssnReceivedAt?.let { lines += "    card received ${moment(it)}" }
        val cert = child.birthCertificateReceivedAt
        lines += if (cert != null) {
            "  Birth certificate: received ${moment(cert)}, ${child.certifiedCopiesOnHand} certified copies on hand"
        } else {
            "  Birth certificate: not received"
        }
        return lines
    }

    private fun taskLines(task: RequirementTask, data: BabyData, today: LocalDate): List<String> {
        val lines = mutableListOf<String>()
        val marker = if (task.deadlineKind == DeadlineKind.HARD) "!" else " "
        val due = task.dueAt?.let { " (${day(it)}, ${TaskPlanner.duePhrase(task, today)})" }.orEmpty()
        lines += "  $marker ${safe(task.title)}$due"
        if (task.assigneeName.isNotEmpty()) lines += "      with ${safe(task.assigneeName)}"
        task.submittedAt?.let { sent ->
            var line = "      sent ${moment(sent)}"
            task.expectedByAt?.let { expected ->
                line += if (task.isLate(today)) ", was due back ${day(expected)} (chase this)" else ", expected back ${day(expected)}"
            }
            lines += line
        }
        val outstanding = data.liveDocuments(task).filter { !it.isOnHand }
        lines += if (outstanding.isEmpty()) "      documents: all gathered" else "      still need: ${outstanding.joinToString("; ") { safe(it.title) }}"
        if (task.officialURLString.isNotEmpty()) lines += "      ${task.officialURLString}"
        return lines
    }

    private fun safeReceiptValue(value: String) =
        if (PlanSeed.containsSocialSecurityNumber(value)) "[redacted Social Security number]" else value

    private fun birthPlaceSuffix(child: Child): String {
        val parts = buildList {
            if (child.birthCounty.isNotEmpty()) add(safe(child.birthCounty))
            if (child.birthStateCode.isNotEmpty()) add(USState.displayName(child.birthStateCode))
        }
        return if (parts.isEmpty()) "" else " in ${parts.joinToString(", ")}"
    }
}

/** The dates as an `.ics`, and nothing a parent typed (`CalendarExporter.swift`). */
object CalendarExporter {
    fun ics(child: Child, data: BabyData, nowMillis: Long = System.currentTimeMillis()): String {
        val lines = mutableListOf(
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Baby Docs//Newborn paperwork//EN",
            "CALSCALE:GREGORIAN", "METHOD:PUBLISH", "X-WR-CALNAME:Baby Docs deadlines",
        )
        val exportable = data.liveTasks(child).filter { it.isOpen && it.dueAt != null }
        for (task in TaskPlanner.sorted(exportable)) {
            val due = task.dueAt ?: continue
            lines += listOf(
                "BEGIN:VEVENT",
                "UID:${task.id.toString().uppercase()}@babydocs",
                "DTSTAMP:${timestamp(nowMillis)}",
                "DTSTART;VALUE=DATE:${compact(due)}",
                "DTEND;VALUE=DATE:${compact(due.plusDays(1))}",
                "SUMMARY:${escape(summary(task))}",
                "DESCRIPTION:${escape(description(task))}",
            )
            if (task.officialURLString.isNotEmpty()) lines += "URL:${task.officialURLString}"
            lines += "END:VEVENT"
        }
        lines += "END:VCALENDAR"
        return lines.joinToString("\r\n") { fold(it) } + "\r\n"
    }

    private fun summary(task: RequirementTask): String {
        val prefix = if (task.deadlineKind == DeadlineKind.HARD) "Deadline" else "Suggested"
        val title = RequirementCatalog.rule(task.catalogKey)?.shortTitle ?: PlanSeed.safeExternalText(task.title)
        return "$prefix: $title"
    }

    private fun description(task: RequirementTask): String {
        val parts = mutableListOf(if (task.deadlineKind == DeadlineKind.HARD) "A window that closes." else "Suggested by Baby Docs. Not a legal deadline.")
        if (task.deadlineBasis.isNotEmpty()) parts += task.deadlineBasis
        parts += PlanExporter.DISCLAIMER
        return parts.joinToString("\n\n")
    }

    private fun compact(date: LocalDate) = date.format(DateTimeFormatter.BASIC_ISO_DATE)

    private fun timestamp(millis: Long) =
        DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").format(java.time.Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC))

    private fun escape(text: String) = text
        .replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
        .replace("\r\n", "\\n").replace("\n", "\\n")

    /** RFC 5545 folding at 75 octets, never inside a UTF-8 sequence. */
    fun fold(line: String): String {
        val bytes = line.toByteArray(Charsets.UTF_8)
        if (bytes.size <= 75) return line
        val out = StringBuilder()
        var index = 0
        var limit = 75
        while (index < bytes.size) {
            var end = minOf(index + limit, bytes.size)
            while (end > index && end < bytes.size && (bytes[end].toInt() and 0xC0) == 0x80) end -= 1
            val chunk = String(bytes, index, end - index, Charsets.UTF_8)
            if (index == 0) out.append(chunk) else out.append("\r\n ").append(chunk)
            index = end
            limit = 74
        }
        return out.toString()
    }
}
