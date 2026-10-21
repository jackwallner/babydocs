package com.jackwallner.babydocs

import android.content.Intent
import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The first-run intake, the core loop, and the free / Plus / reviewer
 * boundaries, driven through UI Automator (test tags are resource ids). Each
 * test runs on a cleared install (`scripts/android-connected-tests.sh` clears
 * app data between tests). Launch extras are the debug-only `DebugLaunchOptions`.
 */
@RunWith(AndroidJUnit4::class)
class SmokeTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val pkg = "com.jackwallner.babydocs"

    private fun launch(extras: Bundle.() -> Unit = {}) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = context.packageManager.getLaunchIntentForPackage(pkg)!!.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            putExtras(Bundle().apply { putBoolean("uiTest", true); extras() })
        }
        context.startActivity(intent)
        device.wait(Until.hasObject(By.pkg(pkg).depth(0)), 20_000)
    }

    private fun seeded(extras: Bundle.() -> Unit = {}) = launch { putBoolean("seed", true); extras() }

    private fun find(selector: BySelector, timeout: Long = 10_000): UiObject2 =
        device.wait(Until.findObject(selector), timeout) ?: throw AssertionError("Not on screen: $selector")

    /** Lazy lists compose only what is on screen, so search from the top down. */
    private fun findScrolling(selector: BySelector): UiObject2 {
        device.wait(Until.findObject(selector), 1_500)?.let { return it }
        repeat(6) { device.findObject(By.scrollable(true))?.scroll(Direction.UP, 1f) }
        repeat(12) {
            device.wait(Until.findObject(selector), 1_000)?.let { return it }
            device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.6f)
        }
        return find(selector)
    }

    private fun tag(id: String) = By.res(id)

    private fun next() {
        find(tag("intake-continue")).click()
        Thread.sleep(400)
    }

    @Test fun intakeBuildsAPlanWithTheHardWindowAndNoPaywallInFront() {
        launch { putBoolean("resetAll", true) }
        find(By.text("The paperwork, in order"))
        assertNull(device.findObject(tag("buy")))
        find(tag("intake-start")).click()
        find(By.text("Who is the plan for?"))
        assertTrue(!find(tag("intake-continue")).isEnabled)
        find(tag("birth-date")).click()
        find(tag("date-ok")).click()
        find(tag("date-confirmed")).click()
        find(tag("birth-state")).click()
        find(tag("search")).text = "Calif"
        find(tag("option-CA")).click()
        findScrolling(tag("citizen-yes")).click()
        next()
        find(By.text("Where do you live, and who is on the record?"))
        findScrolling(tag("parentage-married")).click()
        next()
        find(By.text("How is the family covered?"))
        find(tag("coverage-employer")).click()
        next()
        find(tag("leave-one_parent")).click()
        next()
        find(By.text("Claim the \$1,000 newborn account?"))
        next()
        find(By.text("Open a 529?"))
        next()
        find(By.text("Will the baby need a passport?"))
        next()
        find(By.text("Your plan is ready"))
        find(tag("see-plan")).click()
        // The offer comes after the plan is built, and skipping it is always there.
        findScrolling(tag("skip-plus")).click()
        find(By.text("NEXT HARD DEADLINE"))
        find(By.text("Add the baby to the job-based health plan"))
        assertNotNull(find(tag("tab-plan")))
    }

    @Test fun freePlanShowsEveryLinkAndDocumentButFollowUpAndOwnRemindersAreLocked() {
        seeded()
        findScrolling(tag("task-insurance_employer")).click()
        find(tag("detail-title"))
        findScrolling(tag("official-link"))
        findScrolling(tag("add-reminder-locked"))
        findScrolling(tag("doc-enrollment_form"))
        find(tag("back")).click()
        findScrolling(tag("task-birth_certificate")).click()
        findScrolling(tag("followup-locked")).click()
        find(By.text("Baby Docs Plus"))
        findScrolling(tag("restore"))
    }

    @Test fun plusUnlocksFollowUpTimelineAndTheirOwnReminders() {
        seeded { putBoolean("demoPro", true) }
        findScrolling(tag("task-birth_certificate")).click()
        findScrolling(tag("sent-it"))
        findScrolling(tag("add-reminder")).click()
        findScrolling(tag("reminder-date"))
        find(tag("back")).click()
        find(tag("tab-plus")).click()
        find(tag("open-timeline")).click()
        find(By.text("Timeline"))
        findScrolling(By.text("Waiting on something else".uppercase()))
    }

    @Test fun tickingAHardTaskKeepsItOnThePlan() {
        seeded()
        findScrolling(tag("tick-insurance_employer")).click()
        Thread.sleep(600)
        val row = findScrolling(tag("task-insurance_employer"))
        assertNotNull(row)
        find(By.desc("Done: Add the baby to the Acme PPO plan"))
        find(By.textContains("1 of"))
    }

    @Test fun documentsTabTicksMoveIntoInHand() {
        seeded()
        find(tag("tab-documents")).click()
        find(By.text("STILL TO FIND"))
        find(tag("gather-row")).click()
        findScrolling(By.textStartsWith("ALREADY IN HAND"))
        find(tag("documents-mode-1")).click()
        // Rosa is eleven days old, inside the free twelve weeks.
        find(tag("vault-add"))
        assertNull(device.findObject(tag("vault-add-locked")))
    }

    @Test fun reviewerCodeUnlocksPlus() {
        val code = InstrumentationRegistry.getArguments().getString("reviewCode").orEmpty()
        assertTrue("pass -e reviewCode", code.isNotEmpty())
        seeded()
        find(tag("tab-plus")).click()
        findScrolling(tag("restore"))
        assertNull(device.findObject(tag("open-timeline")))
        find(tag("tab-settings")).click()
        findScrolling(tag("version")).longClick()
        find(tag("review-code")).text = "wrong-code"
        find(tag("review-code-submit")).click()
        find(By.text("That code did not match."))
        find(tag("review-code")).text = code
        find(tag("review-code-submit")).click()
        Thread.sleep(500)
        find(tag("tab-plus")).click()
        find(tag("open-timeline"))
    }

    @Test fun testStorePaywallLoadsRealPlans() {
        seeded { putString("screen", "paywall") }
        find(By.text("Baby Docs Plus"))
        // A cold RevenueCat start on a slow emulator can take a while; the cards sit below the benefits.
        Thread.sleep(8_000)
        val plan = findScrolling(By.res(java.util.regex.Pattern.compile("plan-.*")))
        assertNotNull("No plan card from the Test Store offering", plan)
        findScrolling(tag("buy"))
        findScrolling(By.text("Terms of Use"))
    }

    @Test fun householdChangeRebuildsThePlanAndKeepsTheWork() {
        seeded()
        find(tag("household-card")).click()
        findScrolling(tag("household-coverage-marketplace")).click()
        findScrolling(tag("household-done")).click()
        findScrolling(By.text("Report the birth to the Marketplace and add the baby"))
        assertNull(device.findObject(By.text("Add the baby to the Acme PPO plan")))
    }

    @Test fun sendingThePlanIsFree() {
        seeded()
        find(tag("tab-children")).click()
        findScrolling(By.text("Send or print this plan")).click()
        find(tag("send-link"))
        assertNull(device.findObject(By.text("Plus").res("send-link")))
    }
}
