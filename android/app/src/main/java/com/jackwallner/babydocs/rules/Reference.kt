package com.jackwallner.babydocs.rules

import com.jackwallner.babydocs.model.RequirementCategory
import com.jackwallner.babydocs.model.USState
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

/**
 * Everything the iOS sources declare as data rather than logic: states, the
 * catalog's static rule fields and document lists, the source manifest, the
 * vital records offices and the county names. Generated from the Swift
 * sources by `scripts/sync-android-parity.sh` into
 * `src/main/resources/babydocs-reference.json`, so none of it is transcribed.
 */
object Reference {
    private val root: JSONObject by lazy {
        val stream = Reference::class.java.classLoader!!.getResourceAsStream("babydocs-reference.json")
            ?: error("babydocs-reference.json is missing from the classpath")
        JSONObject(stream.bufferedReader().use { it.readText() })
    }

    val states: List<USState> by lazy {
        root.getJSONArray("states").objects().map { USState(it.getString("code"), it.getString("name")) }
    }

    val ssnWarning: String by lazy { root.getString("ssnWarning") }

    val ruleSpecs: List<RuleSpec> by lazy { root.getJSONArray("rules").objects().map(::ruleSpec) }

    val sources: List<SourceEntry> by lazy {
        root.getJSONArray("sources").objects().map {
            SourceEntry(
                key = it.getString("key"),
                title = it.getString("title"),
                agency = it.getString("agency"),
                urlString = it.getString("urlString"),
                subjects = it.getJSONArray("subjects").strings().toSet(),
                reviewedOn = LocalDate.parse(it.getString("reviewedOn")),
                status = it.getString("status"),
                limitations = it.getString("limitations"),
            )
        }
    }

    val federalDirectoryURL: String by lazy { root.getJSONObject("vitalRecords").getString("federalDirectoryURL") }

    val offices: List<VitalRecordsOffice> by lazy {
        root.getJSONObject("vitalRecords").getJSONArray("offices").objects().map {
            VitalRecordsOffice(
                stateCode = it.getString("stateCode"),
                officeName = it.getString("officeName"),
                urlString = it.getString("urlString"),
                orderingNote = it.getString("orderingNote"),
                verifiedOn = if (it.isNull("verifiedOn")) null else LocalDate.parse(it.getString("verifiedOn")),
                check = VitalRecordsOffice.Check.valueOf(it.getString("check").uppercase()),
            )
        }
    }

    val counties: Map<String, List<String>> by lazy {
        val obj = root.getJSONObject("counties")
        obj.keys().asSequence().associateWith { obj.getJSONArray(it).strings() }
    }

    private fun ruleSpec(o: JSONObject): RuleSpec {
        val sourcing = o.getJSONObject("sourcing")
        val start = o.getJSONObject("start")
        return RuleSpec(
            key = o.getString("key"),
            title = o.getString("title"),
            shortTitle = o.getString("shortTitle"),
            category = RequirementCategory.of(o.getString("category")),
            sortWeight = o.getInt("sortWeight"),
            citeKey = sourcing.optString("cite").ifEmpty { null },
            citeSubject = sourcing.optString("subject").ifEmpty { null },
            noSourceReason = sourcing.optString("noneReason"),
            documents = o.getJSONArray("documents").objects().map {
                DocumentSpec(it.getString("key"), it.getString("title"), it.getString("detail"))
            },
            isPostedAway = o.getBoolean("isPostedAway"),
            start = when (start.getString("kind")) {
                "afterDays" -> StartAdvice.AfterDays(start.getInt("days"), start.getString("because"))
                "after" -> StartAdvice.After(start.getString("key"), start.getString("because"))
                else -> StartAdvice.StraightAway
            },
        )
    }
}

internal fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }
internal fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }

data class DocumentSpec(val key: String, val title: String, val detail: String = "")

/** When it is worth starting a task: the app's own opinion, never a deadline. */
sealed interface StartAdvice {
    data object StraightAway : StartAdvice
    data class AfterDays(val days: Int, val because: String) : StartAdvice
    data class After(val key: String, val because: String) : StartAdvice
}

/** The static half of a `RequirementRule`, as declared in Swift. */
data class RuleSpec(
    val key: String,
    val title: String,
    val shortTitle: String,
    val category: RequirementCategory,
    val sortWeight: Int,
    val citeKey: String?,
    val citeSubject: String?,
    val noSourceReason: String,
    val documents: List<DocumentSpec>,
    val isPostedAway: Boolean,
    val start: StartAdvice,
)

data class SourceEntry(
    val key: String,
    val title: String,
    val agency: String,
    val urlString: String,
    val subjects: Set<String>,
    val reviewedOn: LocalDate,
    val status: String,
    val limitations: String,
)

object SourceManifest {
    val all: List<SourceEntry> get() = Reference.sources
    private val byKey by lazy { all.associateBy { it.key } }

    fun entry(key: String): SourceEntry? = byKey[key]

    /** A rule set is exactly as fresh as its stalest page. */
    val oldestReview: LocalDate get() = all.minOf { it.reviewedOn }
}

data class VitalRecordsOffice(
    val stateCode: String,
    val officeName: String,
    val urlString: String,
    val orderingNote: String,
    val verifiedOn: LocalDate?,
    val check: Check,
) {
    enum class Check { PAGEREAD, SUMMARYCHECKED, FEDERALFALLBACK }

    val isVerified: Boolean get() = check != Check.FEDERALFALLBACK
    val wasReadInFull: Boolean get() = check == Check.PAGEREAD
}

object StateVitalRecords {
    private val offices by lazy { Reference.offices.associateBy { it.stateCode } }

    fun office(stateCode: String): VitalRecordsOffice {
        val code = stateCode.uppercase()
        offices[code]?.let { return it }
        return VitalRecordsOffice(
            stateCode = code,
            officeName = if (code.isEmpty()) "Your state's vital records office" else "${USState.displayName(code)} vital records office",
            urlString = Reference.federalDirectoryURL,
            orderingNote = "",
            verifiedOn = null,
            check = VitalRecordsOffice.Check.FEDERALFALLBACK,
        )
    }

    val allOffices: List<VitalRecordsOffice> get() = offices.values.sortedBy { it.stateCode }
    val verifiedStateCodes: List<String> get() = offices.keys.sorted()
    val fullyReadStateCodes: List<String> get() = offices.values.filter { it.wasReadInFull }.map { it.stateCode }.sorted()
}

/** County names only. It spells a county correctly and routes nothing. */
object USCounties {
    fun names(stateCode: String): List<String> = Reference.counties[stateCode.uppercase()].orEmpty()

    fun contains(county: String, stateCode: String): Boolean {
        val trimmed = county.trim()
        if (trimmed.isEmpty()) return false
        return names(stateCode).any { it.equals(trimmed, ignoreCase = true) }
    }

    fun canonicalName(raw: String, stateCode: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val candidates = names(stateCode)
        candidates.firstOrNull { it.equals(trimmed, ignoreCase = true) }?.let { return it }
        return candidates.firstOrNull { candidate ->
            val head = candidate.split(" ").dropLast(1).joinToString(" ")
            head.isNotEmpty() && head.equals(trimmed, ignoreCase = true)
        }
    }

    val totalCount: Int get() = Reference.counties.values.sumOf { it.size }
}
