package com.jackwallner.babydocs

import com.jackwallner.babydocs.data.BabyData
import com.jackwallner.babydocs.data.Codecs
import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.RequirementTask
import com.jackwallner.babydocs.model.Receipt
import com.jackwallner.babydocs.model.SSNStatus
import com.jackwallner.babydocs.rules.PlanTimeline
import com.jackwallner.babydocs.rules.RequirementCatalog
import com.jackwallner.babydocs.rules.RequirementEngine
import com.jackwallner.babydocs.rules.TaskPlanner
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

/** Ports of RequirementEngineTests, TaskPlannerTests and the timeline checks. */
class RulesEngineTest {
    private val today = LocalDate.of(2026, 10, 20)

    private fun family(insurance: InsuranceKind = InsuranceKind.EMPLOYER): Pair<BabyData, Child> {
        val data = BabyData()
        data.profile.residenceStateCode = "CA"
        data.profile.insuranceKind = insurance
        data.profile.parentage = ParentageSituation.MARRIED
        val child = Child(name = "Rosa", birthDate = today.minusDays(5), birthStateCode = "CA")
        data.children += child
        return data to child
    }

    private fun keys(data: BabyData, child: Child) = data.liveTasks(child).map { it.catalogKey }.toSet()

    @Test
    fun taskIDsAreDeterministicAndTwoStoresAgree() {
        val (a, child) = family()
        val b = BabyData(profile = a.profile)
        b.children += child
        RequirementEngine.reconcile(child, a.profile, a)
        RequirementEngine.reconcile(child, b.profile, b)
        assertEquals(a.tasks.map { it.id }.sorted(), b.tasks.map { it.id }.sorted())
        assertEquals(a.documents.map { it.id }.sorted(), b.documents.map { it.id }.sorted())
        val employer = a.tasks.first { it.catalogKey == "insurance_employer" }
        assertEquals(RequirementEngine.taskID(child.id, "insurance_employer"), employer.id)
    }

    @Test
    fun secondPassIsANoOp() {
        val (data, child) = family()
        val first = RequirementEngine.reconcile(child, data.profile, data)
        assertTrue(first.created > 0)
        val before = Codecs.encode(data)
        val second = RequirementEngine.reconcile(child, data.profile, data, now = 42)
        assertFalse(second.changed)
        assertEquals(before, Codecs.encode(data))
    }

    @Test
    fun employerFamilyGetsTheHardThirtyDayWindow() {
        val (data, child) = family()
        RequirementEngine.reconcile(child, data.profile, data)
        val task = data.liveTasks(child).first { it.catalogKey == "insurance_employer" }
        assertEquals(DeadlineKind.HARD, task.deadlineKind)
        assertEquals(child.birthDate.plusDays(30), task.dueAt)
        assertTrue(task.sourceURLString.startsWith("https://"))
        assertNotNull(task.sourceVerifiedOn)
        assertFalse("insurance_marketplace" in keys(data, child))
        assertFalse("coverage_unknown" in keys(data, child))
    }

    @Test
    fun onlyTheTwoInsuranceWindowsAreEverHard() {
        val hardKeys = mutableSetOf<String>()
        for (kind in InsuranceKind.entries) {
            val (data, child) = family(kind)
            data.profile.hasDependentCareFSA = true
            data.profile.parentage = ParentageSituation.UNMARRIED_BOTH_PARENTS
            RequirementEngine.reconcile(child, data.profile, data)
            hardKeys += data.liveTasks(child).filter { it.deadlineKind == DeadlineKind.HARD }.map { it.catalogKey }
        }
        assertEquals(setOf("insurance_employer", "insurance_marketplace"), hardKeys)
    }

    @Test
    fun changingCoverageRetiresWithoutLosingWorkAndRestoresInPlace() {
        val (data, child) = family()
        RequirementEngine.reconcile(child, data.profile, data)
        val employer = data.liveTasks(child).first { it.catalogKey == "insurance_employer" }
        employer.assigneeName = "Sam"
        employer.setCompleted(true, 1000)
        data.liveDocuments(employer).first().isOnHand = true
        data.receipts += Receipt(taskId = employer.id, value = "ENR-1")

        data.profile.insuranceKind = InsuranceKind.MARKETPLACE
        val switched = RequirementEngine.reconcile(child, data.profile, data)
        assertTrue(switched.retired >= 1)
        assertFalse("insurance_employer" in keys(data, child))
        assertTrue("insurance_marketplace" in keys(data, child))
        assertNotNull(employer.deletedAt)

        data.profile.insuranceKind = InsuranceKind.EMPLOYER
        RequirementEngine.reconcile(child, data.profile, data)
        val restored = data.liveTasks(child).first { it.catalogKey == "insurance_employer" }
        assertTrue(restored === employer)
        assertEquals("Sam", restored.assigneeName)
        assertEquals(1000L, restored.completedAt)
        assertTrue(data.liveDocuments(restored).first().isOnHand)
        assertEquals(1, data.liveReceipts(restored).size)
        assertEquals(1, data.tasks.count { it.catalogKey == "insurance_employer" })
        assertEquals(data.liveDocuments(restored).size, data.documents.count { it.taskId == restored.id })
    }

    @Test
    fun answersOpenAndCloseTheRightRules() {
        val (data, child) = family(InsuranceKind.UNKNOWN)
        data.profile.parentage = ParentageSituation.UNKNOWN
        RequirementEngine.reconcile(child, data.profile, data)
        var k = keys(data, child)
        assertTrue("coverage_unknown" in k)
        assertTrue("parentage_unknown" in k)
        assertTrue("ssn_card" in k && "birth_certificate" in k)
        assertFalse("birth_record_name_check" in k)

        child.ssnStatus = SSNStatus.CARD_RECEIVED
        child.birthCertificateReceivedAt = 1
        data.profile.parentage = ParentageSituation.UNMARRIED_BOTH_PARENTS
        RequirementEngine.reconcile(child, data.profile, data)
        k = keys(data, child)
        assertFalse("ssn_card" in k)
        assertFalse("birth_certificate" in k)
        assertTrue("birth_record_name_check" in k)
        assertTrue("parentage_acknowledgment" in k)
    }

    @Test
    fun engineOwnsTheRuleNotTheWork() {
        val (data, child) = family()
        RequirementEngine.reconcile(child, data.profile, data)
        val task = data.liveTasks(child).first { it.catalogKey == "insurance_employer" }
        task.parentNotes = "call Dana"
        task.submittedAt = 5
        data.profile.employerPlanName = "Acme PPO"
        val result = RequirementEngine.reconcile(child, data.profile, data)
        assertEquals(1, result.updated)
        assertEquals("Add the baby to the Acme PPO plan", task.title)
        assertEquals("call Dana", task.parentNotes)
        assertEquals(5L, task.submittedAt)
    }

    @Test
    fun reconcileAllCoversEveryLiveChild() {
        val (data, child) = family()
        val twin = Child(name = "Theo", birthDate = child.birthDate, birthStateCode = "CA")
        val archived = Child(name = "Old", birthDate = child.birthDate, birthStateCode = "CA", deletedAt = 1)
        data.children += listOf(twin, archived)
        RequirementEngine.reconcileAll(data)
        assertTrue(data.liveTasks(child).isNotEmpty())
        assertEquals(data.liveTasks(child).size, data.liveTasks(twin).size)
        assertTrue(data.tasks.none { it.childId == archived.id })
    }

    // TaskPlanner

    private fun task(due: LocalDate?, kind: DeadlineKind = DeadlineKind.RECOMMENDED, title: String = "t", weight: Int = 100) =
        RequirementTask(title = title, dueAt = due, deadlineKind = kind, sortWeight = weight)

    @Test
    fun bucketingAndOrder() {
        val tasks = listOf(
            task(today.minusDays(1), title = "late"), task(today.plusDays(7), title = "week"),
            task(today.plusDays(8), title = "month"), task(today.plusDays(32), title = "later"), task(null, title = "none"),
        )
        val buckets = TaskPlanner.buckets(tasks, today).map { it.first }
        assertEquals(listOf(TaskPlanner.Bucket.OVERDUE, TaskPlanner.Bucket.THIS_WEEK, TaskPlanner.Bucket.THIS_MONTH, TaskPlanner.Bucket.LATER, TaskPlanner.Bucket.WHENEVER), buckets)
        val sorted = TaskPlanner.sorted(listOf(task(null, title = "b", weight = 1), task(today, title = "a", weight = 50), task(today, title = "c", weight = 10)))
        assertEquals(listOf("c", "a", "b"), sorted.map { it.title })
    }

    @Test
    fun tickedTaskStaysWhereItWasTicked() {
        val t = task(today.plusDays(3))
        t.setCompleted(true, today.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli())
        val later = today.plusDays(20)
        assertEquals(TaskPlanner.Bucket.THIS_WEEK, TaskPlanner.bucket(t, later, TaskPlanner.CompletedPlacement.IN_PLACE))
        assertEquals(TaskPlanner.Bucket.DONE, TaskPlanner.bucket(t, later))
        val dismissed = task(today).apply { setDismissed(true) }
        assertEquals(TaskPlanner.Bucket.DONE, TaskPlanner.bucket(dismissed, today, TaskPlanner.CompletedPlacement.IN_PLACE))
        assertNull(dismissed.completedAt)
    }

    @Test
    fun overviewCountsAndKeepsThePastHardDeadline() {
        val past = task(today.minusDays(2), DeadlineKind.HARD, "past")
        val next = task(today.plusDays(10), DeadlineKind.HARD, "next")
        val done = task(today.plusDays(1)).apply { setCompleted(true) }
        val dismissed = task(today).apply { setDismissed(true) }
        val o = TaskPlanner.overview(listOf(past, next, done, dismissed), today)
        assertEquals(2, o.openCount)
        assertEquals(1, o.doneCount)
        assertEquals(1, o.overdueCount)
        assertEquals("past", o.pastHardDeadlineTitle)
        assertEquals("next", o.nextHardDeadlineTitle)
        assertEquals(1.0 / 3, o.progress, 1e-9)
    }

    @Test
    fun phrasingSaysSuggestionsAreSuggestions() {
        assertEquals("Suggested · Due today", TaskPlanner.duePhrase(task(today), today))
        assertEquals("Due tomorrow", TaskPlanner.duePhrase(task(today.plusDays(1), DeadlineKind.HARD), today))
        assertEquals("5 days left", TaskPlanner.duePhrase(task(today.plusDays(5), DeadlineKind.HARD), today))
        assertEquals("1 day past due", TaskPlanner.duePhrase(task(today.minusDays(1), DeadlineKind.HARD), today))
        assertEquals("3 days past due", TaskPlanner.duePhrase(task(today.minusDays(3), DeadlineKind.HARD), today))
        assertEquals("No deadline", TaskPlanner.duePhrase(task(null, DeadlineKind.NONE), today))
        assertEquals("Date depends on your plan", TaskPlanner.duePhrase(task(null, DeadlineKind.HARD), today))
        assertTrue(TaskPlanner.duePhrase(task(today.plusDays(20), DeadlineKind.HARD), today).startsWith("Due "))
        assertTrue(TaskPlanner.deadlineLine(today.plusDays(2), today).endsWith("· 2 days left"))
    }

    @Test
    fun timelineBlocksThePassportOnTheCertificate() {
        val (data, child) = family()
        data.profile.wantsPassport = true
        RequirementEngine.reconcile(child, data.profile, data)
        val tasks = data.liveTasks(child)
        val groups = PlanTimeline.groups(tasks, { child.birthDate }, today)
        val passport = groups.flatMap { it.steps }.first { it.title.contains("passport") }
        assertEquals(PlanTimeline.Phase.BLOCKED, passport.phase)
        assertTrue(passport.isBlocked)
        val employer = groups.flatMap { it.steps }.first { it.deadlineKind == DeadlineKind.HARD }
        assertEquals(PlanTimeline.Phase.NOW, employer.phase)

        tasks.first { it.catalogKey == "birth_certificate" }.setCompleted(true)
        val opened = PlanTimeline.groups(tasks, { child.birthDate }, today).flatMap { it.steps }.first { it.title.contains("passport") }
        assertEquals(PlanTimeline.Phase.NOW, opened.phase)
        assertTrue(opened.reason.endsWith("That has arrived, so this one is open."))
        // The timeline never sets a date.
        assertEquals(RequirementCatalog.rule("passport")!!.deadline(RequirementEngine.makeInput(child, data.profile)).date, opened.dueAt)
    }
}
