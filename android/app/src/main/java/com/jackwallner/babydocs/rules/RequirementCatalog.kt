package com.jackwallner.babydocs.rules

import com.jackwallner.babydocs.model.DeadlineKind
import com.jackwallner.babydocs.model.InsuranceKind
import com.jackwallner.babydocs.model.MarketplaceKind
import com.jackwallner.babydocs.model.ParentageSituation
import com.jackwallner.babydocs.model.ParentalLeaveTakers
import com.jackwallner.babydocs.model.SSNStatus
import com.jackwallner.babydocs.model.USState
import java.time.LocalDate

/** Everything a rule may look at, as a plain value (`RuleInput` on iOS). */
data class RuleInput(
    val childName: String = "",
    val birthDate: LocalDate = LocalDate.now(),
    val birthStateCode: String = "",
    val isUSCitizen: Boolean = true,
    val hasSSN: Boolean = false,
    val ssnStatus: SSNStatus = SSNStatus.UNKNOWN,
    val hasBirthCertificate: Boolean = false,
    val residenceStateCode: String = "",
    val parentage: ParentageSituation = ParentageSituation.UNKNOWN,
    val secondParentOnRecord: Boolean = false,
    val insuranceKind: InsuranceKind = InsuranceKind.UNKNOWN,
    val marketplaceKind: MarketplaceKind = MarketplaceKind.UNKNOWN,
    val hasDependentCareFSA: Boolean = false,
    val wantsPassport: Boolean = false,
    val wants529: Boolean = false,
    val wantsNewbornAccount: Boolean = false,
    val parentalLeaveTakers: ParentalLeaveTakers = ParentalLeaveTakers.NOBODY,
    val employerPlanName: String = "",
    val benefitsContactNote: String = "",
) {
    val takingParentalLeave: Boolean get() = parentalLeaveTakers != ParentalLeaveTakers.NOBODY

    val shortName: String get() = childName.trimSpaces().ifEmpty { "your baby" }
}

/** Swift's `trimmingCharacters(in: .whitespaces)`: spaces and tabs, not newlines. */
fun String.trimSpaces(): String = trim { it.isWhitespace() && it != '\n' && it != '\r' }

data class Deadline(val date: LocalDate?, val kind: DeadlineKind, val basis: String)

data class OfficialLink(val label: String, val urlString: String)

/** One catalog rule: the declared fields from [Reference] plus its logic. */
class RequirementRule(
    val spec: RuleSpec,
    val applies: (RuleInput) -> Boolean,
    val detail: (RuleInput) -> String,
    val deadline: (RuleInput) -> Deadline,
    val link: (RuleInput) -> OfficialLink?,
    private val titleForFamily: ((RuleInput) -> String)? = null,
) {
    val key get() = spec.key
    val shortTitle get() = spec.shortTitle
    val category get() = spec.category
    val sortWeight get() = spec.sortWeight
    val documents get() = spec.documents
    val isPostedAway get() = spec.isPostedAway
    val start get() = spec.start
    val noSourceReason get() = spec.noSourceReason

    fun title(input: RuleInput): String = titleForFamily?.invoke(input) ?: spec.title

    val source: SourceEntry? get() = spec.citeKey?.let(SourceManifest::entry)
}

/**
 * The twenty-three rules of `RequirementCatalog.swift`. The closures are
 * ported line for line; `PortParityTest` evaluates every one over the Swift
 * exporter's input matrix and compares title, detail, date, kind, basis and link.
 */
object RequirementCatalog {
    val reviewedOn: LocalDate get() = SourceManifest.oldestReview

    val ssnWarning: String get() = Reference.ssnWarning

    private fun spec(key: String) = Reference.ruleSpecs.first { it.key == key }

    private fun addDays(days: Long, date: LocalDate): LocalDate = date.plusDays(days)

    private fun stateName(code: String, fallback: String) = if (code.isEmpty()) fallback else USState.displayName(code)

    private val logic: Map<String, (RuleSpec) -> RequirementRule> = mapOf(
        "ssn_card" to { s ->
            RequirementRule(
                s,
                applies = { !it.hasSSN },
                detail = {
                    when (it.ssnStatus) {
                        SSNStatus.REQUESTED_AT_HOSPITAL -> "You requested it on the hospital form. Nothing else is needed unless the card has not arrived, and it blocks the tax return, the \$1,000 newborn account and most bank accounts until it does."
                        SSNStatus.APPLIED_DIRECTLY -> "You applied directly with SSA. Watch for the card, then mark it received here so the tasks waiting on it open up."
                        SSNStatus.CARD_RECEIVED -> "Already received."
                        SSNStatus.UNKNOWN -> "Most hospitals request this on the birth-registration form, but the request is easy to miss and nobody tells you it failed. Confirm it was made before waiting on it."
                    }
                },
                deadline = {
                    Deadline(null, DeadlineKind.NONE, "No legal deadline. Ask SSA what to expect for this request and record that date in the follow-up section rather than relying on a bundled turnaround time.")
                },
                link = { OfficialLink("Social Security: numbers for children", "https://www.ssa.gov/number-card/") },
            )
        },
        "birth_certificate" to { s ->
            RequirementRule(
                s,
                applies = { !it.hasBirthCertificate },
                detail = { input ->
                    val office = StateVitalRecords.office(input.birthStateCode)
                    val where = stateName(input.birthStateCode, "the state where the birth was registered")
                    val verification = when (office.check) {
                        VitalRecordsOffice.Check.PAGEREAD -> "We have read that office's own page."
                        VitalRecordsOffice.Check.SUMMARYCHECKED -> "We have checked that address against the office's own guidance, though nobody here has read the page end to end."
                        VitalRecordsOffice.Check.FEDERALFALLBACK -> "We do not carry a specific office for this place yet, so the link goes to the national directory rather than to one we would be guessing at."
                    }
                    "Issued by $where, not by the hospital and not federally. Ask the issuing office how many certified copies your family needs and whether ordering them together is useful. Office: ${office.officeName}. $verification"
                },
                deadline = {
                    Deadline(null, DeadlineKind.NONE, "No legal deadline. Ask the issuing office when the record and certified copies will be ready, because filing and processing times differ by jurisdiction.")
                },
                link = { input ->
                    val office = StateVitalRecords.office(input.birthStateCode)
                    OfficialLink(if (office.isVerified) office.officeName else "USAGov: order a birth certificate", office.urlString)
                },
            )
        },
        "birth_record_name_check" to { s ->
            RequirementRule(
                s,
                applies = { it.hasBirthCertificate },
                detail = { "Read the certified copy against what you intended: spelling of ${it.shortName}'s name, the date, and the parent details. Ask the issuing office how corrections, amendments, fees and time limits work where the record was issued. Every document downstream is built from this one." },
                deadline = {
                    Deadline(addDays(30, it.birthDate), DeadlineKind.RECOMMENDED, "Correction windows and fees are set by the state that issued the record. Checking early is what keeps a fix inside the free window.")
                },
                link = { input ->
                    val office = StateVitalRecords.office(input.birthStateCode)
                    OfficialLink(office.officeName, office.urlString)
                },
            )
        },
        "insurance_employer" to { s ->
            RequirementRule(
                s,
                titleForFamily = { input ->
                    val trimmed = input.employerPlanName.trimSpaces()
                    if (trimmed.isEmpty()) "Add the baby to the job-based health plan" else "Add the baby to the $trimmed plan"
                },
                applies = { it.insuranceKind == InsuranceKind.EMPLOYER },
                detail = { input ->
                    var text = "This is the hardest date in the whole list, and it is handled by your employer's benefits administrator rather than by any website. Federal rules give you at least 30 days from the birth, and the plan then has to make coverage effective from the date of birth, which is what makes the hospital bill get paid. Outside the window you are waiting for open enrollment."
                    val contact = input.benefitsContactNote.trimSpaces()
                    if (contact.isNotEmpty()) text += " You said to contact: $contact."
                    text
                },
                deadline = {
                    Deadline(addDays(30, it.birthDate), DeadlineKind.HARD, "Federal rules give at least 30 days after a birth to request enrollment in a job-based plan, and coverage is then effective from the birth date. Your plan may allow longer. Ask your benefits administrator for the exact date and work to whichever is sooner.")
                },
                link = { OfficialLink("Department of Labor: special enrollment after a birth", "https://webapps.dol.gov/elaws/ebsa/health/72.asp") },
            )
        },
        "insurance_marketplace" to { s ->
            RequirementRule(
                s,
                applies = { it.insuranceKind == InsuranceKind.MARKETPLACE },
                detail = { input ->
                    val base = "Reporting the birth is also what re-runs your savings: a larger household usually changes the premium tax credit, and the change does not happen on its own. Marketplace coverage for a new baby is generally backdated to the date of birth, and it is not in force until the first premium is paid."
                    when (input.marketplaceKind) {
                        MarketplaceKind.FEDERAL -> base
                        MarketplaceKind.STATE -> "$base Your state runs its own marketplace, so all of this happens on your state's site and in your state's account, not on HealthCare.gov."
                        MarketplaceKind.UNKNOWN -> "$base You have not said which marketplace you use. About a third of states run their own site rather than HealthCare.gov, and signing in to the wrong one costs days inside a window that does not stop for it, so start from the state picker below."
                    }
                },
                deadline = { input ->
                    Deadline(
                        addDays(60, input.birthDate),
                        DeadlineKind.HARD,
                        if (input.marketplaceKind == MarketplaceKind.FEDERAL) {
                            "HealthCare.gov gives 60 days from the birth to enroll the baby, and the coverage then starts on the day of the birth."
                        } else {
                            "Marketplace special enrollment after a birth is 60 days. If your state runs its own marketplace, that window is the same but the site, the account and the documents are your state's, so do this there rather than on HealthCare.gov and confirm the date while you are in it."
                        },
                    )
                },
                link = { input ->
                    when (input.marketplaceKind) {
                        MarketplaceKind.FEDERAL -> OfficialLink("HealthCare.gov: report a life change", "https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/")
                        MarketplaceKind.STATE, MarketplaceKind.UNKNOWN -> OfficialLink("Find your state's Marketplace", "https://www.healthcare.gov/marketplace-in-your-state/")
                    }
                },
            )
        },
        "insurance_medicaid_chip" to { s ->
            RequirementRule(
                s,
                applies = { it.insuranceKind == InsuranceKind.MEDICAID_CHIP || it.insuranceKind == InsuranceKind.NONE },
                detail = { input ->
                    val state = stateName(input.residenceStateCode, "your state")
                    "Medicaid and CHIP take applications at any time of year, so there is no window to miss here. Eligibility and the agency are set by $state, and children qualify at higher household incomes than adults do."
                },
                deadline = { Deadline(null, DeadlineKind.NONE, "No enrollment window. Applications are accepted year-round.") },
                link = { OfficialLink("HealthCare.gov: Medicaid and CHIP", "https://www.healthcare.gov/medicaid-chip/getting-medicaid-chip/") },
            )
        },
        "dependent_care_fsa" to { s ->
            RequirementRule(
                s,
                applies = { it.hasDependentCareFSA },
                detail = { "A birth may let your employer plan permit a dependent care FSA election change, and it is separate from the medical plan. Ask the benefits administrator for the plan's qualifying-event rule and window before assuming an election is available or locked until open enrollment." },
                deadline = {
                    Deadline(addDays(30, it.birthDate), DeadlineKind.RECOMMENDED, "Your plan sets this window, not the IRS, and 30 days is only the commonest version of it. Ask your benefits administrator or read the plan document for your own date, and work to that. This app will not put a red date on a number it cannot check.")
                },
                link = { OfficialLink("IRS: child and dependent care expenses", "https://www.irs.gov/publications/p503") },
            )
        },
        "coverage_unknown" to { s ->
            RequirementRule(
                s,
                applies = { it.insuranceKind == InsuranceKind.UNKNOWN },
                detail = { "This is the only unanswered question in your plan that costs money. A job-based plan has to give at least 30 days from the birth and the Marketplace gives 60, and both start the coverage on the day of the birth, which is what gets the hospital bill paid. Medicaid and CHIP take applications all year, so if that is the answer there is nothing to miss. Find out which one it is, then set it in your household answers and the real deadline appears here." },
                deadline = {
                    Deadline(addDays(14, it.birthDate), DeadlineKind.RECOMMENDED, "Not a deadline anyone set: the shortest real window is 30 days, so answering this inside a fortnight leaves room to actually use it. Baby Docs will not put a red date or a reminder on a window it cannot name.")
                },
                link = { null },
            )
        },
        "hospital_bill_check" to { s ->
            RequirementRule(
                s,
                applies = { it.insuranceKind == InsuranceKind.EMPLOYER || it.insuranceKind == InsuranceKind.MARKETPLACE },
                detail = { "Ask the insurer how newborn claims should be billed under this plan, then compare the explanation of benefits with the hospital bill. Do not assume that a bill showing ${it.shortName} as uninsured tells you who owes it or why. Call the insurer before paying, and follow the denial notice's instructions if a claim is refused." },
                deadline = {
                    Deadline(addDays(60, it.birthDate), DeadlineKind.RECOMMENDED, "No deadline of its own, but appeal windows run from the date on the denial notice or explanation of benefits, so it is worth catching early.")
                },
                link = { OfficialLink("HealthCare.gov: appeal an insurance decision", "https://www.healthcare.gov/appeal-insurance-company-decision/appeals/") },
            )
        },
        "parentage_unknown" to { s ->
            RequirementRule(
                s,
                applies = { it.parentage == ParentageSituation.UNKNOWN },
                detail = { "You chose not to answer the parentage question. This task does not assume that paperwork applies. Ask the hospital birth registrar or your state's vital records or child-support agency whether anything is needed for this birth record, especially if a parent is not on the record or the situation is contested. This app will not prepare or file a legal form for you." },
                deadline = { Deadline(null, DeadlineKind.NONE, "No date is invented here. The office handling the birth record can tell you whether a form applies and what its own timing is.") },
                link = { OfficialLink("Find your state's child support agency", "https://acf.gov/css/contact-information/state-and-tribal-child-support-agency-contacts") },
            )
        },
        "parentage_acknowledgment" to { s ->
            RequirementRule(
                s,
                applies = { it.parentage == ParentageSituation.UNMARRIED_BOTH_PARENTS && !it.secondParentOnRecord },
                detail = { input ->
                    val state = stateName(input.birthStateCode, "your state")
                    "This is legally significant and it is state law, so $state sets the form, the witnessing and the window in which a signature can be withdrawn. It affects the birth record, inheritance, benefits and custody.\n\nThe fastest door is the hospital's birth registrar before discharge; after that it is usually the state vital records office or the child support agency, and the directory below is how to find the one for $state. Ask how long a signature can be withdrawn before you sign, not after.\n\nThis app will not prepare or file it for you, and if anything about the situation is contested or either parent is unsure, that is a conversation with a lawyer rather than a form to sign today."
                },
                deadline = {
                    Deadline(addDays(60, it.birthDate), DeadlineKind.RECOMMENDED, "Usually signed at the hospital. It can be done later, but rescission windows and the process for adding a parent afterwards are state-specific and get harder with time.")
                },
                link = { OfficialLink("Find your state's child support agency", "https://acf.gov/css/contact-information/state-and-tribal-child-support-agency-contacts") },
            )
        },
        "parental_leave_claim" to { s ->
            RequirementRule(
                s,
                titleForFamily = {
                    if (it.parentalLeaveTakers == ParentalLeaveTakers.BOTH_PARENTS) "File the first parent's leave claim" else "File the parental leave claim"
                },
                applies = { it.takingParentalLeave },
                detail = { input ->
                    var text = "FMLA protects the job but is unpaid, and eligibility depends on the employee and employer. Whether anything is paid depends on the employer's policy and the paid-leave programme in the state where the parent works. Ask the employer which work-state programme, notice rule and form apply; this household residence answer is not enough to determine it."
                    if (input.parentalLeaveTakers == ParentalLeaveTakers.BOTH_PARENTS) {
                        text += " You said both parents are taking leave, so this is the first parent's claim and there is a second task for the other one: two employers, two sets of forms, and possibly two different windows."
                    }
                    text
                },
                deadline = { Deadline(null, DeadlineKind.NONE, "FMLA itself has no filing deadline for the employee. Ask the employer for the notice window and the work-state programme's own date before relying on one.") },
                link = { OfficialLink("Department of Labor: FMLA", "https://www.dol.gov/agencies/whd/fmla") },
            )
        },
        "parental_leave_claim_second" to { s ->
            RequirementRule(
                s,
                applies = { it.parentalLeaveTakers == ParentalLeaveTakers.BOTH_PARENTS },
                detail = { "A separate claim, with a separate employer and possibly a separate work-state programme. Bonding leave for the non-birth parent can be governed by different rules than the birth parent's own leave, so the two dates cannot be assumed to match. Assign this one to whoever is filing it and ask that employer which jurisdiction and notice rule apply." },
                deadline = { Deadline(null, DeadlineKind.NONE, "FMLA sets no filing deadline for the employee. Ask the second parent's employer for its notice window and the applicable work-state programme's own date.") },
                link = { OfficialLink("Department of Labor: FMLA", "https://www.dol.gov/agencies/whd/fmla") },
            )
        },
        "w4_update" to { s ->
            RequirementRule(
                s,
                applies = { true },
                detail = { "A dependent changes what should be withheld. Nothing is lost by leaving it, but the money sits with the IRS until you file instead of arriving in the paychecks you need it in." },
                deadline = { Deadline(addDays(45, it.birthDate), DeadlineKind.RECOMMENDED, "No deadline. The sooner it changes, the more paychecks it affects.") },
                link = { OfficialLink("IRS: Form W-4", "https://www.irs.gov/forms-pubs/about-form-w-4") },
            )
        },
        "trump_account" to { s ->
            RequirementRule(
                s,
                applies = { input -> input.isUSCitizen && input.wantsNewbornAccount && input.birthDate.year in 2025..2028 },
                detail = { input ->
                    val official = "The IRS calls these Trump Accounts, which is the name on the form and on irs.gov."
                    val conditions = "Two other conditions sit behind it and only the instructions can settle them: no election having been made for this child already, and the person electing expecting to claim them for the tax year."
                    if (input.hasSSN) {
                        "${input.shortName} has an SSN, so the election can be made. US citizen children born from 2025 through 2028 may qualify for a one-time \$1,000 federal contribution. $conditions $official"
                    } else {
                        "US citizen children born from 2025 through 2028 may qualify for a one-time \$1,000 federal contribution. The election needs a Social Security number issued to the child first, so this one is waiting on the SSN card. $conditions $official"
                    }
                },
                deadline = {
                    Deadline(null, DeadlineKind.RECOMMENDED, "The current Form 4547 instructions set no filing deadline: the election can be made at any time, including with a return. They also say no pilot contribution is deposited before 4 July 2026. Read the current instructions before relying on any date, because a wrong date on a one-time \$1,000 election is worse than no date.")
                },
                link = { OfficialLink("IRS: the official page", "https://www.irs.gov/trumpaccounts") },
            )
        },
        "tax_dependent" to { s ->
            RequirementRule(
                s,
                applies = { true },
                detail = { input ->
                    val year = input.birthDate.year
                    "A baby born at any point in $year counts as a dependent for the whole of $year. The Child Tax Credit needs a valid SSN for the child issued before the return's due date, which is the real reason the SSN task sits at the top of this list. Whether you qualify depends on facts this app does not hold, so check the year you are filing for or ask whoever prepares the return."
                },
                deadline = { Deadline(null, DeadlineKind.NONE, "Handled when you file. Listed here so the SSN and childcare paperwork are gathered before the return, not during it.") },
                link = { OfficialLink("IRS: Child Tax Credit", "https://www.irs.gov/credits-deductions/individuals/child-tax-credit") },
            )
        },
        "plan_529" to { s ->
            RequirementRule(
                s,
                applies = { it.wants529 },
                detail = { input ->
                    val state = stateName(input.residenceStateCode, "your state")
                    "Optional and entirely yours to time. Worth checking whether $state gives a state income tax deduction for its own plan before picking one, because that is usually the only reason to prefer a home-state plan. Baby Docs does not recommend a plan or a provider."
                },
                deadline = { Deadline(null, DeadlineKind.NONE, "No deadline. Open it whenever you want to.") },
                link = { OfficialLink("IRS: qualified tuition programs", "https://www.irs.gov/taxtopics/tc313") },
            )
        },
        "passport" to { s ->
            RequirementRule(
                s,
                applies = { it.wantsPassport },
                detail = { input ->
                    if (input.hasBirthCertificate) {
                        "A first passport for a child under 16 is applied for in person, and a parent has to be present to sign. Book the appointment before you need it: processing times move, and a child's passport is valid for five years."
                    } else {
                        "Blocked until the certified birth certificate arrives, because the application submits the original. Every child under 16 applies in person, with a parent present to sign."
                    }
                },
                deadline = { Deadline(null, DeadlineKind.NONE, "No deadline. Driven by when you plan to travel.") },
                link = { OfficialLink("USAGov: passport for a child", "https://www.usa.gov/child-passport") },
            )
        },
        "newborn_screening_result" to { s ->
            RequirementRule(
                s,
                applies = { true },
                detail = { "Every state screens newborns for a panel of conditions, plus hearing and a heart-oxygen check. Ask the pediatric practice or state programme where the results are held and how to obtain a copy for your own file. If anything is out of range, the practice or the state health department contacts you: this task is not how you would find out, and Baby Docs does not read, hold or interpret a result." },
                deadline = { Deadline(null, DeadlineKind.NONE, "No deadline. Ask the pediatric practice when the results will be available and record that date in the follow-up section if you need to chase them.") },
                link = { OfficialLink("Newborn screening in your state", "https://newbornscreening.hrsa.gov/your-state") },
            )
        },
        "beneficiary_update" to { s ->
            RequirementRule(
                s,
                applies = { true },
                detail = { "Beneficiary designations on retirement accounts and life insurance override a will, so this is not covered by writing one. Naming a minor directly has consequences worth understanding first, which is usually why people name a trust or a custodian instead. Baby Docs is not a financial adviser and this is a prompt, not advice." },
                deadline = { Deadline(addDays(90, it.birthDate), DeadlineKind.RECOMMENDED, "No deadline. Listed at 90 days because it is the task everyone agrees to do and nobody does.") },
                link = { null },
            )
        },
        "guardian_nomination" to { s ->
            RequirementRule(
                s,
                applies = { true },
                detail = { "The nomination of a guardian for a minor is made in a will, and without one a court chooses. Requirements for a valid will are state law. This app tracks the task and nothing else: it does not draft or store legal documents, and the questions this raises are for a lawyer." },
                deadline = { Deadline(addDays(90, it.birthDate), DeadlineKind.RECOMMENDED, "No deadline. Ninety days is a prompt, not a rule.") },
                link = { null },
            )
        },
        "pediatric_portal" to { s ->
            RequirementRule(
                s,
                applies = { true },
                detail = { "The portal is where the immunization record lives, and daycare, school and travel all ask for it eventually. Federal law gives you the right to a copy of your child's record whether or not the practice runs a portal. Both parents should have their own login rather than sharing one." },
                deadline = { Deadline(null, DeadlineKind.NONE, "No deadline.") },
                link = { OfficialLink("How to get a health record", "https://www.healthit.gov/how-to-get-your-health-record") },
            )
        },
        "childcare_waitlist" to { s ->
            RequirementRule(
                s,
                applies = { true },
                detail = { "Not paperwork the government asks for, and on this list only because the waits are measured in months and the deposits are usually refundable. Your state's child care resource and referral agency also holds the list of financial help, which is worth a look before you pay a deposit. Nothing here is time-critical in the way the insurance window is." },
                deadline = { Deadline(null, DeadlineKind.NONE, "No deadline.") },
                link = { OfficialLink("Childcare.gov: find child care", "https://childcare.gov/") },
            )
        },
    )

    /** In the Swift catalog's order. A rule declared in Swift with no ported logic fails loudly. */
    val all: List<RequirementRule> by lazy {
        Reference.ruleSpecs.map { spec ->
            val make = logic[spec.key] ?: error("No Android logic for catalog rule ${spec.key}")
            make(spec)
        }
    }

    private val byKey by lazy { all.associateBy { it.key } }

    fun rule(key: String): RequirementRule? = byKey[key]
}
