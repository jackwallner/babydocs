package com.jackwallner.babydocs.data

import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * On-device record of how someone met Baby Docs Plus before they bought it,
 * mirrored onto the RevenueCat customer as the fleet-wide subscriber
 * attributes. Same keys and formats as `ConversionDiagnostics.swift`.
 * Counts, dates and short surface names only: never health data or free text.
 */
class ConversionDiagnostics(private val defaults: KeyValueStore, private val clock: Clock = Instant::now) {
    fun recordAppOpen() {
        if (!defaults.contains(INSTALLED_AT)) defaults.putLong(INSTALLED_AT, millis())
        defaults.putInt(APP_OPENS, defaults.getInt(APP_OPENS) + 1)
    }

    /** The "how early were they asked" pair is frozen on the first pitch only. */
    fun recordPitchView(impressionId: String) {
        val surface = surface(impressionId)
        defaults.putInt(TOTAL_VIEWS, defaults.getInt(TOTAL_VIEWS) + 1)
        defaults.putInt(views(surface), defaults.getInt(views(surface)) + 1)
        defaults.putString(LAST_SURFACE, surface)
        if (!defaults.contains(FIRST_SEEN)) {
            defaults.putLong(FIRST_SEEN, millis())
            defaults.putInt(OPENS_BEFORE_FIRST_PITCH, defaults.getInt(APP_OPENS))
            if (defaults.contains(INSTALLED_AT)) {
                defaults.putInt(DAYS_TO_FIRST_PITCH, daysSince(defaults.getLong(INSTALLED_AT)))
            }
        }
    }

    /** Only the first conversion is recorded: a renewal is not a new answer to "what sold this person". */
    fun recordConversion(plan: String, startedTrial: Boolean, offeringId: String? = null) {
        if (defaults.contains(CONVERTED_ON)) return
        defaults.putString(CONVERTED_ON, defaults.getString(LAST_SURFACE) ?: "unknown")
        defaults.putInt(VIEWS_AT_CONVERT, defaults.getInt(TOTAL_VIEWS))
        defaults.putString(CONVERTED_PLAN, plan)
        defaults.putBoolean(CONVERTED_WITH_TRIAL, startedTrial)
        offeringId?.let { defaults.putString(CONVERTED_OFFERING, it) }
        defaults.putLong(CONVERTED_AT, millis())
        if (defaults.contains(FIRST_SEEN)) defaults.putInt(DAYS_TO_CONVERT, daysSince(defaults.getLong(FIRST_SEEN)))
    }

    /** Empty until the first pitch; keys stay under RevenueCat's 40-character limit. */
    val subscriberAttributes: Map<String, String>
        get() {
            val total = defaults.getInt(TOTAL_VIEWS)
            if (total <= 0) return emptyMap()
            val a = linkedMapOf("pitch_views_total" to total.toString())
            defaults.keys().filter { it.startsWith(VIEWS_PREFIX) && it != TOTAL_VIEWS }.forEach { key ->
                val count = defaults.getInt(key)
                if (count > 0) a["pitch_views_${key.removePrefix(VIEWS_PREFIX)}".take(40)] = count.toString()
            }
            defaults.getString(LAST_SURFACE)?.let { a["pitch_last"] = it }
            if (defaults.contains(FIRST_SEEN)) {
                val first = defaults.getLong(FIRST_SEEN)
                a["pitch_first_seen"] = iso(first)
                a["days_since_first_pitch"] = daysSince(first).toString()
            }
            if (defaults.contains(DAYS_TO_FIRST_PITCH)) a["days_since_install"] = defaults.getInt(DAYS_TO_FIRST_PITCH).toString()
            if (defaults.contains(OPENS_BEFORE_FIRST_PITCH)) a["opens_before_first_pitch"] = defaults.getInt(OPENS_BEFORE_FIRST_PITCH).toString()
            defaults.getString(CONVERTED_ON)?.let { surface ->
                a["converted_surface"] = surface
                if (defaults.contains(CONVERTED_AT)) a["converted_at"] = iso(defaults.getLong(CONVERTED_AT))
                a["pitch_views_at_convert"] = defaults.getInt(VIEWS_AT_CONVERT).toString()
                a["days_to_convert"] = defaults.getInt(DAYS_TO_CONVERT).toString()
                a["converted_plan"] = defaults.getString(CONVERTED_PLAN) ?: "unknown"
                a["converted_with_trial"] = if (defaults.getBoolean(CONVERTED_WITH_TRIAL)) "true" else "false"
                defaults.getString(CONVERTED_OFFERING)?.let { a["converted_offering"] = it }
            }
            return a
        }

    private fun millis() = clock().toEpochMilli()
    private fun daysSince(start: Long) = maxOf(0, ((millis() - start) / DAY_MS).toInt())
    private fun iso(epochMillis: Long) =
        DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(epochMillis).truncatedTo(ChronoUnit.SECONDS))

    companion object {
        private const val IMPRESSION_PREFIX = "babydocs_"
        private const val VIEWS_PREFIX = "conv.pitchViews."
        private const val TOTAL_VIEWS = "conv.pitchViews.total"
        private const val FIRST_SEEN = "conv.pitchFirstSeen"
        private const val LAST_SURFACE = "conv.pitchLastSurface"
        private const val INSTALLED_AT = "conv.installedAt"
        private const val APP_OPENS = "conv.appOpens"
        private const val OPENS_BEFORE_FIRST_PITCH = "conv.opensBeforeFirstPitch"
        private const val DAYS_TO_FIRST_PITCH = "conv.daysToFirstPitch"
        private const val CONVERTED_ON = "conv.convertedOn"
        private const val CONVERTED_AT = "conv.convertedAt"
        private const val VIEWS_AT_CONVERT = "conv.viewsAtConvert"
        private const val DAYS_TO_CONVERT = "conv.daysToConvert"
        private const val CONVERTED_PLAN = "conv.convertedPlan"
        private const val CONVERTED_WITH_TRIAL = "conv.convertedWithTrial"
        private const val CONVERTED_OFFERING = "conv.convertedOffering"

        fun surface(impressionId: String) = impressionId.removePrefix(IMPRESSION_PREFIX)
        private fun views(surface: String) = "$VIEWS_PREFIX$surface"
    }
}
