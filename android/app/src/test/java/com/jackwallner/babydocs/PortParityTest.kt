package com.jackwallner.babydocs

import com.jackwallner.babydocs.data.DeterministicID
import com.jackwallner.babydocs.data.PlanSeed
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.MarketplaceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.ParentalLeaveTakers
import com.jackwallner.babydocs.model.SSNStatus
import com.jackwallner.babydocs.rules.RequirementCatalog
import com.jackwallner.babydocs.rules.RuleInput
import com.jackwallner.babydocs.rules.StateVitalRecords
import com.jackwallner.babydocs.rules.USCounties
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.util.UUID

/**
 * Checks the Kotlin port against answers computed by the Swift sources
 * themselves (`scripts/sync-android-parity.sh` writes the fixture). Every rule
 * is evaluated over the same 240 households and must agree on whether it
 * applies, its title, detail, date, kind, basis and link.
 */
class PortParityTest {
    private val fixture: JSONObject by lazy {
        val stream = javaClass.classLoader!!.getResourceAsStream("babydocs-parity.json")!!
        JSONObject(stream.bufferedReader().use { it.readText() })
    }
    private val strings by lazy { fixture.getJSONArray("strings").let { a -> (0 until a.length()).map(a::getString) } }

    private fun input(o: JSONObject): RuleInput {
        val ssn = SSNStatus.of(o.getString("ssnStatus"))
        return RuleInput(
            childName = o.getString("childName"),
            birthDate = LocalDate.parse(o.getString("birthDate")),
            birthStateCode = o.getString("birthStateCode"),
            isUSCitizen = o.getBoolean("isUSCitizen"),
            hasSSN = ssn == SSNStatus.CARD_RECEIVED,
            ssnStatus = ssn,
            hasBirthCertificate = o.getBoolean("hasBirthCertificate"),
            residenceStateCode = o.getString("residenceStateCode"),
            parentage = ParentageSituation.of(o.getString("parentage")),
            secondParentOnRecord = o.getBoolean("secondParentOnRecord"),
            insuranceKind = InsuranceKind.of(o.getString("insuranceKind")),
            marketplaceKind = MarketplaceKind.of(o.getString("marketplaceKind")),
            hasDependentCareFSA = o.getBoolean("hasDependentCareFSA"),
            wantsPassport = o.getBoolean("wantsPassport"),
            wants529 = o.getBoolean("wants529"),
            wantsNewbornAccount = o.getBoolean("wantsNewbornAccount"),
            parentalLeaveTakers = ParentalLeaveTakers.parse(o.getString("parentalLeaveTakers"))!!,
            employerPlanName = o.getString("employerPlanName"),
            benefitsContactNote = o.getString("benefitsContactNote"),
        )
    }

    @Test
    fun catalogHasTheSwiftRulesInOrder() {
        val keys = fixture.getJSONArray("ruleKeys").let { a -> (0 until a.length()).map(a::getString) }
        assertEquals(23, keys.size)
        assertEquals(keys, RequirementCatalog.all.map { it.key })
    }

    @Test
    fun everyRuleAgreesWithSwiftOverTheInputMatrix() {
        val cases = fixture.getJSONArray("cases")
        assertEquals(240, cases.length())
        var compared = 0
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i)
            val input = input(case.getJSONObject("input"))
            val rules = case.getJSONArray("rules")
            for (r in 0 until rules.length()) {
                val expected = rules.getJSONObject(r)
                val rule = RequirementCatalog.rule(expected.getString("key"))!!
                val where = "case $i rule ${rule.key}"
                assertEquals(where, expected.getBoolean("applies"), rule.applies(input))
                assertEquals(where, strings[expected.getInt("title")], rule.title(input))
                assertEquals(where, strings[expected.getInt("detail")], rule.detail(input))
                val deadline = rule.deadline(input)
                val due = if (expected.isNull("due")) null else expected.getString("due")
                assertEquals(where, due, deadline.date?.toString())
                assertEquals(where, expected.getString("kind"), deadline.kind.raw)
                assertEquals(where, strings[expected.getInt("basis")], deadline.basis)
                val link = rule.link(input)
                val label = expected.getInt("linkLabel")
                assertEquals(where, if (label < 0) null else strings[label], link?.label)
                val url = expected.getInt("linkURL")
                assertEquals(where, if (url < 0) null else strings[url], link?.urlString)
                compared += 1
            }
        }
        assertEquals(240 * 23, compared)
    }

    @Test
    fun sourcesOfficesAndCountiesMatch() {
        assertEquals(fixture.getString("reviewedOn"), RequirementCatalog.reviewedOn.toString())
        val verified = fixture.getJSONArray("verifiedStateCodes").let { a -> (0 until a.length()).map(a::getString) }
        assertEquals(51, verified.size)
        assertEquals(verified, StateVitalRecords.verifiedStateCodes)
        val read = fixture.getJSONArray("fullyReadStateCodes").let { a -> (0 until a.length()).map(a::getString) }
        assertEquals(read, StateVitalRecords.fullyReadStateCodes)
        assertEquals(fixture.getInt("countyCount"), USCounties.totalCount)
        assertTrue(USCounties.totalCount > 3000)
        val canonical = fixture.getJSONArray("canonicalCounties")
        for (i in 0 until canonical.length()) {
            val o = canonical.getJSONObject(i)
            assertEquals(o.getString("match"), USCounties.canonicalName(o.getString("raw"), o.getString("state")).orEmpty())
        }
        // Territories fall back to the federal directory and say so.
        assertTrue(!StateVitalRecords.office("GU").isVerified)
        assertEquals("https://www.usa.gov/birth-certificate", StateVitalRecords.office("GU").urlString)
    }

    @Test
    fun citedRulesCiteAManifestEntryForTheirSubject() {
        for (rule in RequirementCatalog.all) {
            val key = rule.spec.citeKey
            if (key == null) {
                assertTrue("${rule.key} must say why it cites nothing", rule.noSourceReason.isNotBlank())
                continue
            }
            val source = assertNotNull(rule.source).let { rule.source!! }
            assertTrue("${rule.key} cites $key for ${rule.spec.citeSubject}", rule.spec.citeSubject in source.subjects)
            assertTrue(source.urlString.startsWith("https://"))
        }
    }

    @Test
    fun deterministicIDsAreByteForByteSwift() {
        val ids = fixture.getJSONArray("deterministicIDs")
        assertEquals(4, ids.length())
        for (i in 0 until ids.length()) {
            val o = ids.getJSONObject(i)
            val id = DeterministicID.v5(UUID.fromString(o.getString("namespace")), o.getString("name"))
            assertEquals(o.getString("id").lowercase(), id.toString())
        }
    }

    @Test
    fun socialSecurityPatternMatchesSwift() {
        val samples = fixture.getJSONArray("sensitive")
        assertEquals(10, samples.length())
        for (i in 0 until samples.length()) {
            val o = samples.getJSONObject(i)
            assertEquals(o.getString("text"), o.getBoolean("contains"), PlanSeed.containsSocialSecurityNumber(o.getString("text")))
            assertEquals(o.getString("safe"), PlanSeed.safeExternalText(o.getString("text")))
        }
    }

    @Test
    fun swiftPlanLinkDecodesAndRoundTrips() {
        val today = LocalDate.of(2026, 10, 20)
        val seed = PlanSeed.decode(fixture.getString("seedPayload"), today)!!
        assertEquals("Rosa", seed.name)
        assertEquals(LocalDate.of(2026, 9, 1), seed.birthDate)
        assertEquals("CA", seed.birthStateCode)
        assertEquals("Alameda County", seed.birthCounty)
        assertEquals("employer", seed.insuranceKind)
        assertEquals("Acme PPO", seed.employerPlanName)
        assertEquals("both_parents", seed.parentalLeaveTakers)
        assertEquals(UUID.fromString("6F9619FF-8B86-D011-B42D-00C04FC964FF"), seed.childID)
        assertEquals(seed, PlanSeed.decode(seed.encoded(), today))
        assertEquals(seed, PlanSeed.decodeURL(fixture.getString("seedURL"), today))
        assertEquals(seed, PlanSeed.decodeURL("babydocs://plan?d=" + fixture.getString("seedPayload"), today))
        assertTrue(fixture.getString("seedURL").startsWith(PlanSeed.WEB_BASE + "#"))
    }
}
