package com.jackwallner.babydocs.data

import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.FamilyProfile
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.MarketplaceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.ParentalLeaveTakers
import com.jackwallner.babydocs.model.USState
import org.json.JSONObject
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Base64
import java.util.UUID

/**
 * The household answers that rebuild a plan, carried in the fragment of a
 * link to `docs/plan.html` (`PlanSeed.swift`). The fragment never reaches a
 * server. Nothing a parent typed about the work travels, only the answers, and
 * any text shaped like a Social Security number is redacted on both ends.
 */
data class PlanSeed(
    val version: Int = 1,
    val childID: UUID?,
    val name: String,
    val birthDate: LocalDate,
    val birthStateCode: String,
    val birthCounty: String,
    val isUSCitizen: Boolean,
    val residenceStateCode: String,
    val parentage: String,
    val secondParentOnRecord: Boolean,
    val insuranceKind: String,
    val marketplaceKind: String?,
    val employerPlanName: String?,
    val benefitsContactNote: String?,
    val hasDependentCareFSA: Boolean,
    val wantsPassport: Boolean,
    val wants529: Boolean,
    val wantsNewbornAccount: Boolean,
    val takingParentalLeave: Boolean,
    val parentalLeaveTakers: String?,
) {
    fun shareURL(): String = "$WEB_BASE#${encoded()}"

    fun encoded(): String {
        val o = JSONObject()
        o.put("version", version)
        childID?.let { o.put("childID", it.toString().uppercase()) }
        o.put("name", name)
        o.put("birthDate", birthDate.atTime(12, 0).toInstant(ZoneOffset.UTC).toString())
        o.put("birthStateCode", birthStateCode)
        o.put("birthCounty", birthCounty)
        o.put("isUSCitizen", isUSCitizen)
        o.put("residenceStateCode", residenceStateCode)
        o.put("parentage", parentage)
        o.put("secondParentOnRecord", secondParentOnRecord)
        o.put("insuranceKind", insuranceKind)
        marketplaceKind?.let { o.put("marketplaceKind", it) }
        employerPlanName?.let { o.put("employerPlanName", it) }
        benefitsContactNote?.let { o.put("benefitsContactNote", it) }
        o.put("hasDependentCareFSA", hasDependentCareFSA)
        o.put("wantsPassport", wantsPassport)
        o.put("wants529", wants529)
        o.put("wantsNewbornAccount", wantsNewbornAccount)
        o.put("takingParentalLeave", takingParentalLeave)
        parentalLeaveTakers?.let { o.put("parentalLeaveTakers", it) }
        return Base64.getUrlEncoder().withoutPadding().encodeToString(o.toString().toByteArray(Charsets.UTF_8))
    }

    private fun isSemanticallyValid(today: LocalDate): Boolean {
        val validMarketplace = marketplaceKind?.let { MarketplaceKind.parse(it) != null } ?: true
        val validLeave = parentalLeaveTakers?.let { raw ->
            val takers = ParentalLeaveTakers.parse(raw) ?: return@let false
            (takers != ParentalLeaveTakers.NOBODY) == takingParentalLeave
        } ?: true
        return name.trim().length <= 120 &&
            birthCounty.trim().length <= 120 &&
            !birthDate.isAfter(today) &&
            !birthDate.isBefore(LocalDate.of(1970, 1, 1)) &&
            USState.named(birthStateCode) != null &&
            USState.named(residenceStateCode) != null &&
            ParentageSituation.parse(parentage) != null &&
            InsuranceKind.parse(insuranceKind) != null &&
            validMarketplace && validLeave
    }

    companion object {
        const val WEB_BASE = "https://jackwallner.com/ios/babydocs/plan.html"
        const val CURRENT_VERSION = 1
        private const val REDACTED = "[redacted Social Security number]"
        private val ssnPattern = Regex("(?<![0-9])[0-9]{3}[- .]?[0-9]{2}[- .]?[0-9]{4}(?![0-9])")

        fun containsSocialSecurityNumber(value: String): Boolean = ssnPattern.containsMatchIn(value)

        fun safeExternalText(value: String): String = ssnPattern.replace(value, REDACTED)

        fun make(child: Child, profile: FamilyProfile): PlanSeed {
            val employer = profile.insuranceKind == InsuranceKind.EMPLOYER
            return PlanSeed(
                childID = child.id,
                name = safeExternalText(child.name),
                birthDate = child.birthDate,
                birthStateCode = child.birthStateCode,
                birthCounty = safeExternalText(child.birthCounty),
                isUSCitizen = child.isUSCitizen,
                residenceStateCode = profile.residenceStateCode,
                parentage = profile.parentage.raw,
                secondParentOnRecord = profile.secondParentOnRecord,
                insuranceKind = profile.insuranceKind.raw,
                marketplaceKind = profile.marketplaceKind.raw,
                employerPlanName = if (employer) safeExternalText(profile.employerPlanName) else null,
                benefitsContactNote = if (employer) safeExternalText(profile.benefitsContactNote) else null,
                hasDependentCareFSA = profile.hasDependentCareFSA,
                wantsPassport = profile.wantsPassport,
                wants529 = profile.wants529,
                wantsNewbornAccount = profile.wantsNewbornAccount,
                takingParentalLeave = profile.takingParentalLeave,
                parentalLeaveTakers = profile.parentalLeaveTakers.raw,
            )
        }

        /** Reads a link's fragment, or a `babydocs://...?d=` deep link. Null for anything not a valid plan. */
        fun decodeURL(url: String, today: LocalDate = LocalDate.now()): PlanSeed? {
            val fragment = url.substringAfter('#', "")
            val payload = fragment.ifEmpty {
                if (url.startsWith("babydocs:")) url.substringAfter("d=", "").substringBefore('&') else ""
            }
            return if (payload.isEmpty()) null else decode(payload, today)
        }

        fun decode(payload: String, today: LocalDate = LocalDate.now()): PlanSeed? {
            if (payload.length > 16_384) return null
            return runCatching {
                val o = JSONObject(String(Base64.getUrlDecoder().decode(payload), Charsets.UTF_8))
                val instant = Instant.parse(o.getString("birthDate"))
                fun opt(key: String) = if (o.has(key) && !o.isNull(key)) o.getString(key) else null
                PlanSeed(
                    version = o.optInt("version", 1),
                    childID = opt("childID")?.let(UUID::fromString),
                    name = safeExternalText(o.getString("name")),
                    birthDate = instant.atZone(ZoneOffset.UTC).toLocalDate(),
                    birthStateCode = o.getString("birthStateCode"),
                    birthCounty = safeExternalText(o.getString("birthCounty")),
                    isUSCitizen = o.getBoolean("isUSCitizen"),
                    residenceStateCode = o.getString("residenceStateCode"),
                    parentage = o.getString("parentage"),
                    secondParentOnRecord = o.getBoolean("secondParentOnRecord"),
                    insuranceKind = o.getString("insuranceKind"),
                    marketplaceKind = opt("marketplaceKind"),
                    employerPlanName = opt("employerPlanName")?.let(::safeExternalText),
                    benefitsContactNote = opt("benefitsContactNote")?.let(::safeExternalText),
                    hasDependentCareFSA = o.getBoolean("hasDependentCareFSA"),
                    wantsPassport = o.getBoolean("wantsPassport"),
                    wants529 = o.getBoolean("wants529"),
                    wantsNewbornAccount = o.getBoolean("wantsNewbornAccount"),
                    takingParentalLeave = o.getBoolean("takingParentalLeave"),
                    parentalLeaveTakers = opt("parentalLeaveTakers"),
                )
            }.getOrNull()?.takeIf { it.version in 1..CURRENT_VERSION && it.isSemanticallyValid(today) }
        }
    }
}

/** RFC 4122 version 5 ids, byte for byte with `DeterministicID.swift`. */
object DeterministicID {
    fun v5(namespace: UUID, name: String): UUID {
        val ns = java.nio.ByteBuffer.allocate(16)
            .putLong(namespace.mostSignificantBits)
            .putLong(namespace.leastSignificantBits)
            .array()
        val digest = MessageDigest.getInstance("SHA-1").apply {
            update(ns)
            update(name.toByteArray(Charsets.UTF_8))
        }.digest().copyOf(16)
        digest[6] = ((digest[6].toInt() and 0x0F) or 0x50).toByte()
        digest[8] = ((digest[8].toInt() and 0x3F) or 0x80).toByte()
        val buffer = java.nio.ByteBuffer.wrap(digest)
        return UUID(buffer.long, buffer.long)
    }
}
