package com.jackwallner.babydocs

import com.jackwallner.babydocs.data.BabyData
import com.jackwallner.babydocs.data.BabyStore
import com.jackwallner.babydocs.data.CalendarExporter
import com.jackwallner.babydocs.data.Codecs
import com.jackwallner.babydocs.data.DeadlineReminderPlanner
import com.jackwallner.babydocs.data.InMemoryStore
import com.jackwallner.babydocs.data.PackageKind
import com.jackwallner.babydocs.data.PeriodUnit
import com.jackwallner.babydocs.data.Plan
import com.jackwallner.babydocs.data.PlanExporter
import com.jackwallner.babydocs.data.PlanPeriod
import com.jackwallner.babydocs.data.PlanSeed
import com.jackwallner.babydocs.data.ReminderPreferences
import com.jackwallner.babydocs.data.ReviewAccess
import com.jackwallner.babydocs.data.ReviewPromptTracker
import com.jackwallner.babydocs.data.SampleData
import com.jackwallner.babydocs.data.Sensitive
import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.Receipt
import com.jackwallner.babydocs.model.ReceiptKind
import com.jackwallner.babydocs.model.RequirementTask
import com.jackwallner.babydocs.model.SSNStatus
import com.jackwallner.babydocs.ui.screens.disclosure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/** Ports of RemindersAndExportTests, ReviewPromptTests, PlusTierTests and the store guards. */
class ServicesTest {
    private val zone = ZoneId.of("America/Los_Angeles")
    private val now = ZonedDateTime.of(2026, 10, 20, 12, 0, 0, 0, zone)
    private val today = now.toLocalDate()

    private fun task(due: LocalDate?, kind: DeadlineKind) = RequirementTask(title = "x", dueAt = due, deadlineKind = kind)

    @Test
    fun onlyHardDeadlinesFireForFree() {
        val hard = task(today.plusDays(20), DeadlineKind.HARD)
        val suggested = task(today.plusDays(20), DeadlineKind.RECOMMENDED)
        val plans = DeadlineReminderPlanner.plans(listOf(hard, suggested), now)
        assertEquals(2, plans.size)
        assertTrue(plans.all { it.isHardDeadline && it.taskID == hard.id })
        assertEquals(listOf("7 days left", "Last day tomorrow"), plans.map { it.title })
        assertEquals(today.plusDays(13).atTime(9, 0).atZone(zone), plans.first().fireAt)
        // Generic text: no task title, no name, nothing from the household on a lock screen.
        assertTrue(plans.none { it.body.contains("x ") })
    }

    @Test
    fun plusOptionsAddSuggestionsDigestAndOwnReminders() {
        val suggested = task(today.plusDays(10), DeadlineKind.RECOMMENDED)
        val own = task(null, DeadlineKind.NONE).apply { customReminderAt = today.plusDays(4).atStartOfDay(zone).toInstant().toEpochMilli() }
        val options = DeadlineReminderPlanner.Options(suggestedDates = true, weeklyDigest = true, customReminders = true)
        val plans = DeadlineReminderPlanner.plans(listOf(suggested, own), now, options)
        assertTrue(plans.any { it.identifier.startsWith("suggested.") && it.fireAt.toLocalDate() == today.plusDays(7) })
        assertTrue(plans.any { it.identifier.startsWith("custom.") && it.fireAt.toLocalDate() == today.plusDays(4) })
        val digest = plans.filter { it.identifier.startsWith("digest.") }
        assertEquals(1, digest.size)
        assertEquals(java.time.DayOfWeek.SUNDAY, digest.first().fireAt.dayOfWeek)
        assertEquals("One suggested task reaches its date this week. It is not a legal deadline. Open Baby Docs for details.", digest.first().body)
    }

    @Test
    fun completedAndPastDeadlinesAreSilentAndHardClaimsTheBudget() {
        val done = task(today.plusDays(20), DeadlineKind.HARD).apply { setCompleted(true) }
        val past = task(today.minusDays(1), DeadlineKind.HARD)
        assertTrue(DeadlineReminderPlanner.plans(listOf(done, past), now).isEmpty())
        val many = (1..40).map { task(today.plusDays(8L + it), DeadlineKind.RECOMMENDED) }
        val hard = task(today.plusDays(60), DeadlineKind.HARD)
        val plans = DeadlineReminderPlanner.plans(many + hard, now, DeadlineReminderPlanner.Options(suggestedDates = true))
        assertEquals(DeadlineReminderPlanner.MAX_SCHEDULED, plans.size)
        assertEquals(2, plans.count { it.isHardDeadline })
    }

    @Test
    fun digestBodyNamesRealWindows() {
        val hard = task(today, DeadlineKind.HARD)
        val soft = task(today, DeadlineKind.RECOMMENDED)
        assertEquals("2 things reach their date this week. 1 of them is a real window closing.", DeadlineReminderPlanner.digestBody(listOf(hard, soft)))
        assertEquals("2 things reach their date this week. None of them is a legal deadline.", DeadlineReminderPlanner.digestBody(listOf(soft, soft)))
    }

    @Test
    fun exportsNeverCarryANumberAndCarryTheDisclaimer() {
        val data = BabyData()
        val child = SampleData.seed(data, today)
        val insurance = data.liveTasks(child).first { it.catalogKey == "insurance_employer" }
        data.receipts += Receipt(taskId = insurance.id, kind = ReceiptKind.NOTE, value = "SSN 123-45-6789")
        insurance.setCompleted(true)
        val summary = PlanExporter.summary(child, data.profile, data, today)
        assertTrue(summary.startsWith("NEWBORN PAPERWORK: ROSA"))
        assertTrue(summary.contains("Social Security: Requested at the hospital"))
        assertFalse(summary.contains("123-45-6789"))
        assertTrue(summary.contains("[redacted Social Security number]"))
        assertTrue(summary.contains("was due back") && summary.contains("(chase this)"))
        assertTrue(summary.endsWith(PlanExporter.DISCLAIMER))
        val packet = PlanExporter.employerPacket(child, data.profile, data, today)
        assertTrue(packet.startsWith("QUALIFYING LIFE EVENT: BIRTH OF A CHILD"))
        assertTrue(packet.contains("Change my dependent care FSA election"))
        assertTrue(packet.contains("Applied for, not yet issued."))
        data.profile.insuranceKind = InsuranceKind.MARKETPLACE
        assertTrue(PlanExporter.employerPacket(child, data.profile, data, today).startsWith("EMPLOYER PACKET NOT APPLICABLE"))
    }

    @Test
    fun calendarCarriesDatesAndNothingTyped() {
        val data = BabyData()
        val child = SampleData.seed(data, today)
        data.liveTasks(child).forEach { it.parentNotes = "private note" }
        val ics = CalendarExporter.ics(child, data, 0)
        assertTrue(ics.startsWith("BEGIN:VCALENDAR\r\n"))
        assertTrue(ics.endsWith("END:VCALENDAR\r\n"))
        assertTrue(ics.contains("SUMMARY:Deadline: Job-based plan"))
        assertTrue(ics.contains("SUMMARY:Suggested: "))
        assertFalse(ics.contains("private note"))
        assertFalse(ics.contains("ENR-4471"))
        assertTrue(ics.split("\r\n").all { it.toByteArray().size <= 75 })
        val events = ics.split("BEGIN:VEVENT").size - 1
        assertEquals(data.liveTasks(child).count { it.isOpen && it.dueAt != null }, events)
    }

    @Test
    fun storeRoundTripsAndRefusesAnSSN() {
        val file = File.createTempFile("babydocs", ".json").apply { delete() }
        val store = BabyStore(file)
        assertTrue(store.commit { SampleData.seed(it, today) })
        val reopened = BabyStore(file)
        assertEquals(Codecs.encode(store.data), Codecs.encode(reopened.data))
        assertEquals(store.data.tasks.size, reopened.data.tasks.size)

        val task = reopened.data.tasks.first()
        assertFalse(reopened.commit { task.parentNotes = "her SSN is 123 45 6789" })
        assertEquals(com.jackwallner.babydocs.data.Sensitive.MESSAGE, reopened.failureMessage)
        assertFalse(Sensitive.containsAny(reopened.data))
        assertFalse(file.readText().contains("6789"))
        file.delete()
    }

    @Test
    fun planSeedLeavesTheWorkBehind() {
        val data = BabyData()
        val child = SampleData.seed(data, today)
        child.ssnStatus = SSNStatus.CARD_RECEIVED
        val url = PlanSeed.make(child, data.profile).shareURL()
        assertTrue(url.startsWith("https://jackwallner.com/ios/babydocs/plan.html#"))
        assertFalse(url.contains("?"))
        val seed = PlanSeed.decodeURL(url, today)!!
        assertEquals("Rosa", seed.name)
        assertEquals("Acme PPO", seed.employerPlanName)
        val json = String(java.util.Base64.getUrlDecoder().decode(url.substringAfter('#')))
        assertFalse(json.contains("ENR-4471"))
        assertFalse(json.contains("ssn"))
        assertNull(PlanSeed.decodeURL("https://jackwallner.com/ios/babydocs/plan.html#not-a-plan", today))
        // A birth in the future is not a plan.
        assertNull(PlanSeed.decode(seed.copy(birthDate = today.plusDays(2)).encoded(), today))
    }

    @Test
    fun reviewAskWaitsForTwoHardDeadlinesMet() {
        val defaults = InMemoryStore()
        var clock = Instant.parse("2026-10-01T12:00:00Z")
        val tracker = ReviewPromptTracker(defaults) { clock }
        repeat(3) { tracker.recordAppLaunch() }
        val hard = task(today.plusDays(5), DeadlineKind.HARD)
        tracker.recordCompletion(task(today.plusDays(5), DeadlineKind.RECOMMENDED), today)
        tracker.recordCompletion(task(today.minusDays(1), DeadlineKind.HARD), today)
        assertEquals(0, tracker.positiveMomentCount)
        tracker.recordCompletion(hard, today)
        tracker.recordCompletion(hard, today)
        assertFalse(tracker.shouldRequestAfterPositiveMoment())
        clock = clock.plusSeconds(3 * 86_400L)
        assertTrue(tracker.shouldRequestAfterPositiveMoment())
        tracker.markRequested()
        tracker.recordCompletion(hard, today)
        assertFalse(tracker.shouldRequestAfterPositiveMoment())
        clock = clock.plusSeconds(120 * 86_400L)
        assertTrue(tracker.shouldRequestAfterPositiveMoment())
        tracker.suppressed = true
        assertFalse(tracker.canRequestReview())
    }

    @Test
    fun reminderPreferencesDefaultOn() {
        val prefs = ReminderPreferences(InMemoryStore())
        assertTrue(prefs.suggestedDateReminders && prefs.weeklyDigest)
        prefs.weeklyDigest = false
        assertFalse(prefs.weeklyDigest)
    }

    @Test
    fun reviewerCodeUnlocksOnlyWithTheRightCode() {
        val digest = MessageDigest.getInstance("SHA-256").digest("bd-test".toByteArray()).joinToString("") { "%02x".format(it) }
        val defaults = InMemoryStore()
        val access = ReviewAccess(defaults, digest)
        assertFalse(access.activate("wrong"))
        assertFalse(access.isGranted)
        assertTrue(access.activate(" bd-test "))
        assertTrue(access.isGranted)
        assertFalse(ReviewAccess(InMemoryStore(), "").activate("bd-test"))
    }

    @Test
    fun paywallWordsComeFromTheStore() {
        val weekly = Plan("\$rc_weekly", "w", PackageKind.WEEKLY, 4_990_000, "\$4.99", "USD", PlanPeriod(1, PeriodUnit.WEEK), PlanPeriod(3, PeriodUnit.DAY))
        val lifetime = Plan("\$rc_lifetime", "l", PackageKind.LIFETIME, 59_990_000, "\$59.99", "USD", null, null)
        assertEquals("Weekly", weekly.displayName)
        assertEquals("Keep it forever", lifetime.displayName)
        assertEquals("\$4.99 / week", weekly.priceLabel)
        assertEquals("3-day free trial", weekly.introOfferLabel)
        assertEquals("3-day free trial, then \$4.99 / week, renewing automatically until cancelled.", disclosure(weekly, true))
        assertEquals("\$4.99 / week, renewing automatically until cancelled.", disclosure(weekly, false))
        assertEquals("\$59.99 once. No renewal.", disclosure(lifetime, true))
        assertNotNull(PackageKind.fromIdentifiers("com.jackwallner.babydocs.pro.weekly").takeIf { it == PackageKind.WEEKLY })
    }
}
