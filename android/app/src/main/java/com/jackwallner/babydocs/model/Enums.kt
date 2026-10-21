package com.jackwallner.babydocs.model

import com.jackwallner.babydocs.rules.Reference

/** A US state or territory, stored as its two-letter postal code (`USState` on iOS). */
data class USState(val code: String, val name: String) {
    companion object {
        val all: List<USState> get() = Reference.states

        fun named(code: String): USState? = all.firstOrNull { it.code.equals(code, ignoreCase = true) }

        fun displayName(code: String): String = named(code)?.name ?: code
    }
}

enum class SSNStatus(val raw: String, val label: String) {
    UNKNOWN("unknown", "Not sure"),
    REQUESTED_AT_HOSPITAL("requested_at_hospital", "Requested at the hospital"),
    APPLIED_DIRECTLY("applied_directly", "Applied at an SSA office"),
    CARD_RECEIVED("card_received", "Card received");

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: UNKNOWN
    }
}

enum class InsuranceKind(val raw: String, val label: String) {
    UNKNOWN("unknown", "Not sure yet"),
    EMPLOYER("employer", "Through a job"),
    MARKETPLACE("marketplace", "Marketplace (HealthCare.gov or a state site)"),
    MEDICAID_CHIP("medicaid_chip", "Medicaid or CHIP"),
    NONE("none", "No coverage right now");

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: UNKNOWN
        fun parse(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

enum class MarketplaceKind(val raw: String, val label: String) {
    UNKNOWN("unknown", "Not sure which"),
    FEDERAL("federal", "HealthCare.gov"),
    STATE("state", "My state runs its own site");

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: UNKNOWN
        fun parse(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

enum class ParentalLeaveTakers(val raw: String, val label: String) {
    NOBODY("nobody", "Nobody is taking leave"),
    ONE_PARENT("one_parent", "One parent"),
    BOTH_PARENTS("both_parents", "Both parents");

    companion object {
        fun parse(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

enum class ParentageSituation(val raw: String, val label: String) {
    UNKNOWN("unknown", "Prefer not to say"),
    MARRIED("married", "Married to the other parent"),
    UNMARRIED_BOTH_PARENTS("unmarried_both", "Not married, both parents involved"),
    SINGLE_PARENT("single_parent", "Single parent");

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: UNKNOWN
        fun parse(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

/** How hard the date is. Drives colour, sort order and whether a reminder is scheduled. */
enum class DeadlineKind(val raw: String) {
    HARD("hard"), RECOMMENDED("recommended"), NONE("none");

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: NONE
    }
}

enum class RequirementCategory(val raw: String, val label: String) {
    IDENTITY("identity", "Identity"),
    INSURANCE("insurance", "Insurance"),
    PARENTAGE("parentage", "Parentage"),
    MONEY("money", "Money"),
    TRAVEL("travel", "Travel"),
    WORK("work", "Work & leave"),
    HOUSEHOLD("household", "Household");

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: IDENTITY
    }
}

enum class ReceiptKind(val raw: String, val label: String) {
    SUBMITTED("submitted", "Submitted"),
    CONFIRMATION_NUMBER("confirmation_number", "Confirmation number"),
    TRACKING("tracking", "Tracking number"),
    RECEIVED("received", "Received"),
    NOTE("note", "Note");

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: NOTE
    }
}

enum class VaultDocumentKind(val raw: String, val label: String, val sortWeight: Int) {
    BIRTH_CERTIFICATE("birth_certificate", "Birth certificate", 0),
    SOCIAL_SECURITY_CARD("social_security_card", "Social Security card", 10),
    DISCHARGE_PAPERS("discharge_papers", "Hospital discharge papers", 30),
    INSURANCE_CARD("insurance_card", "Insurance card", 20),
    IMMUNIZATION_RECORD("immunization_record", "Immunization record", 40),
    PASSPORT("passport", "Passport", 60),
    PARENTAGE_FORM("parentage_form", "Parentage acknowledgment", 50),
    OTHER("other", "Something else", 90);

    /** The two documents whose loss is expensive and whose contents are worth stealing. */
    val isSensitive: Boolean get() = this == SOCIAL_SECURITY_CARD || this == PASSPORT

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: OTHER
    }
}
