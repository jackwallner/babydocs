import Foundation

/// Every page the catalog is allowed to cite, declared once.
///
/// Rules used to carry their own URL and label inline, and that is exactly how a
/// birth-certificate page ends up cited under a childcare task and an IRS page
/// about college savings ends up cited as the deadline for a dependent care FSA.
/// Both of those had happened. A `.gov` host check cannot catch either, because
/// both URLs are perfectly valid government addresses for a different subject.
///
/// So a source is a value with a **subject**, and a rule declares the subject it
/// needs. Citing the wrong page is then a compile-time or test-time failure
/// rather than something a parent discovers at a counter.
///
/// The other half of the promise is honesty about what is *not* known: an entry
/// carries the day a person last read it, what it does not cover, and whether it
/// is the specific authority or a federal fallback standing in for fifty state
/// pages nobody has read yet.
enum SourceSubject: String, Sendable, CaseIterable {
    case socialSecurityNumber
    case birthCertificateOrder
    case birthRecordCorrection
    case employerCoverageEnrollment
    case marketplaceCoverageEnrollment
    case medicaidCHIP
    case dependentCareBenefits
    case claimsAndAppeals
    case parentageEstablishment
    case familyLeave
    case taxWithholding
    case childTaxCredit
    case trumpAccounts
    case qualifiedTuitionPrograms
    case passports
    case newbornScreening
    case healthRecordsAccess
    case childcare
}

/// How much weight the citation can carry.
enum SourceStatus: String, Sendable {
    /// Somebody read this page and it directly supports the rule's statement.
    case verified
    /// Correct and official, but general: it answers the federal question while
    /// the parent's actual answer is set by a state, a plan or an employer. The
    /// task says so rather than implying the page is the last word.
    case federalFallback
    /// Believed right, not yet read end to end. Shown to the user as unchecked.
    case awaitingReview
}

struct SourceEntry: Sendable, Equatable, Identifiable {
    let key: String
    /// The page's own title, so a rule cannot quietly relabel it into something
    /// it does not say.
    let title: String
    let agency: String
    let urlString: String
    /// What this page is actually about. A rule may only cite it for a subject
    /// in this set.
    let subjects: Set<SourceSubject>
    /// The day a person last read it.
    let reviewedOn: Date
    let status: SourceStatus
    /// What the page does not tell you. Shown on the task, because the gap is
    /// usually the thing that costs a parent a fortnight.
    let limitations: String

    var id: String { key }
    var url: URL? { URL(string: urlString) }
}

enum SourceManifest {
    static func entry(_ key: String) -> SourceEntry? { byKey[key] }

    /// The oldest review in the whole manifest. Surfaced in Settings, because
    /// "reviewed on the 9th" means nothing if one entry has been sitting
    /// unchecked since March.
    static var oldestReview: Date {
        all.map(\.reviewedOn).min() ?? Date()
    }

    static let byKey: [String: SourceEntry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.key, $0) }
    )

    // MARK: - Entries

    static let all: [SourceEntry] = [
        SourceEntry(
            key: "ssa_number_and_card",
            title: "Social Security numbers and cards",
            agency: "Social Security Administration",
            urlString: "https://www.ssa.gov/number-card/",
            subjects: [.socialSecurityNumber],
            reviewedOn: day(2026, 8, 9),
            status: .verified,
            limitations: ""
        ),
        SourceEntry(
            key: "ssa_card_timing",
            title: "How long does it take to get a Social Security card?",
            agency: "Social Security Administration",
            urlString: "https://www.ssa.gov/faqs/en/questions/KA-10041.html",
            subjects: [.socialSecurityNumber],
            reviewedOn: day(2026, 8, 9),
            status: .verified,
            limitations: "Processing times are an average, not a promise."
        ),
        SourceEntry(
            key: "usagov_birth_certificate",
            title: "How to get a certified copy of a U.S. birth certificate",
            agency: "USAGov",
            urlString: "https://www.usa.gov/birth-certificate",
            subjects: [.birthCertificateOrder],
            reviewedOn: day(2026, 8, 11),
            status: .federalFallback,
            limitations: """
            Covers ordering a copy only, and hands off to a national directory \
            rather than naming your office. It does not cover correcting a \
            record, and it does not carry your state's fee, ID rules or \
            processing time.
            """
        ),
        SourceEntry(
            key: "dol_newborn_special_enrollment",
            title: "Health Benefits Advisor: special enrollment after the birth of a child",
            agency: "U.S. Department of Labor",
            urlString: "https://webapps.dol.gov/elaws/ebsa/health/72.asp",
            subjects: [.employerCoverageEnrollment],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            States the federal floor: request enrollment within 30 days of the \
            birth and the plan must make coverage effective from the birth \
            date. Your own plan may allow longer, and only the plan can tell \
            you whether it does.
            """
        ),
        SourceEntry(
            key: "healthcaregov_special_enrollment",
            title: "Getting health coverage outside Open Enrollment",
            agency: "HealthCare.gov (Centers for Medicare & Medicaid Services)",
            urlString: "https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/",
            subjects: [.marketplaceCoverageEnrollment],
            reviewedOn: day(2026, 8, 11),
            status: .federalFallback,
            limitations: """
            Written for the federal Marketplace. State-run marketplaces use \
            their own site, account and documents, so confirm the exact date \
            and steps in the state's system even though the special-enrollment \
            window after a birth is generally 60 days.
            """
        ),
        SourceEntry(
            key: "healthcaregov_medicaid_chip",
            title: "Medicaid & CHIP coverage",
            agency: "HealthCare.gov (Centers for Medicare & Medicaid Services)",
            urlString: "https://www.healthcare.gov/medicaid-chip/getting-medicaid-chip/",
            subjects: [.medicaidCHIP],
            reviewedOn: day(2026, 8, 11),
            status: .federalFallback,
            limitations: """
            Eligibility, the agency and the application are all set by your \
            state. This page explains the programme and routes you there.
            """
        ),
        SourceEntry(
            key: "healthcaregov_appeals",
            title: "How to appeal an insurance company decision",
            agency: "HealthCare.gov (Centers for Medicare & Medicaid Services)",
            urlString: "https://www.healthcare.gov/appeal-insurance-company-decision/appeals/",
            subjects: [.claimsAndAppeals],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            Explains internal appeals and external review. The clock and the \
            address to send it to are on your own denial notice or explanation \
            of benefits.
            """
        ),
        SourceEntry(
            key: "irs_pub_503",
            title: "Publication 503, Child and Dependent Care Expenses",
            agency: "Internal Revenue Service",
            urlString: "https://www.irs.gov/publications/p503",
            subjects: [.dependentCareBenefits],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            Explains what a dependent care benefit is and the annual exclusion \
            limit. It does not set the window for changing an election after a \
            birth: that is your employer's cafeteria plan document.
            """
        ),
        SourceEntry(
            key: "acf_new_parent_checklist",
            title: "New Parent Checklist",
            agency: "HHS Administration for Children and Families, Office of Child Support Services",
            urlString: "https://acf.gov/css/outreach-material/new-parent-checklist",
            subjects: [.parentageEstablishment],
            reviewedOn: day(2026, 8, 11),
            status: .federalFallback,
            limitations: """
            Federal encouragement to establish parentage, not the form. The \
            form, the witnessing and the window in which a signature can be \
            withdrawn are all state law.
            """
        ),
        SourceEntry(
            key: "dol_fmla",
            title: "Family and Medical Leave Act",
            agency: "U.S. Department of Labor, Wage and Hour Division",
            urlString: "https://www.dol.gov/agencies/whd/fmla",
            subjects: [.familyLeave],
            reviewedOn: day(2026, 8, 9),
            status: .federalFallback,
            limitations: """
            Job protection only, and unpaid. It says nothing about your \
            employer's paid policy or a state paid-leave programme, and those \
            are the ones with filing windows.
            """
        ),
        SourceEntry(
            key: "irs_form_w4",
            title: "About Form W-4, Employee's Withholding Certificate",
            agency: "Internal Revenue Service",
            urlString: "https://www.irs.gov/forms-pubs/about-form-w-4",
            subjects: [.taxWithholding],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: ""
        ),
        SourceEntry(
            key: "irs_child_tax_credit",
            title: "Child Tax Credit",
            agency: "Internal Revenue Service",
            urlString: "https://www.irs.gov/credits-deductions/individuals/child-tax-credit",
            subjects: [.childTaxCredit],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            Amounts and rules are set per tax year, and whether you qualify \
            turns on facts this app does not hold. Confirm against the year you \
            are filing for.
            """
        ),
        SourceEntry(
            key: "irs_trump_accounts",
            title: "Trump Accounts",
            agency: "Internal Revenue Service",
            urlString: "https://www.irs.gov/trumpaccounts",
            subjects: [.trumpAccounts],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: ""
        ),
        SourceEntry(
            key: "irs_form_4547_instructions",
            title: "Instructions for Form 4547, Trump Account Election",
            agency: "Internal Revenue Service",
            urlString: "https://www.irs.gov/instructions/i4547",
            subjects: [.trumpAccounts],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            States that the child must have an SSN issued before the election \
            is made, that the form can be filed at any time, and that no pilot \
            contribution is deposited before July 4, 2026.
            """
        ),
        SourceEntry(
            key: "irs_topic_313",
            title: "Topic no. 313, Qualified tuition programs (QTPs)",
            agency: "Internal Revenue Service",
            urlString: "https://www.irs.gov/taxtopics/tc313",
            subjects: [.qualifiedTuitionPrograms],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            Federal tax treatment only. Whether your own state gives a \
            deduction or credit for its plan is a state question.
            """
        ),
        SourceEntry(
            key: "usagov_child_passport",
            title: "Get a passport for a minor under 18",
            agency: "USAGov",
            urlString: "https://www.usa.gov/child-passport",
            subjects: [.passports],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            Confirms that every child under 16 applies in person, that a parent \
            must be present and sign, and that the passport is valid for five \
            years. Photo rules and processing times live with the State \
            Department and move.
            """
        ),
        // Replaced an HRSA page that sat here as `awaitingReview` for a release,
        // because HRSA's site refuses every automated request and nobody could
        // read it. An unread citation under an active rule is the one thing this
        // manifest exists to prevent, and the honest fix is to cite a page that
        // has been read rather than to keep a placeholder wearing a warning
        // label. HRSA's state finder is still the task's *link*, which is a
        // different job: it routes, it does not support a claim.
        SourceEntry(
            key: "medlineplus_newborn_screening",
            title: "Newborn Screening",
            agency: "MedlinePlus, National Library of Medicine (NIH)",
            urlString: "https://medlineplus.gov/newbornscreening.html",
            subjects: [.newbornScreening],
            reviewedOn: day(2026, 8, 17),
            status: .verified,
            limitations: """
            Confirms the three screens every newborn gets, that the panel \
            differs by state, and that a provider or the state health \
            department calls you if something is out of range. It does not list \
            your own state's conditions, does not say who holds the result, and \
            says nothing about how to obtain a copy: that comes from the \
            practice and from your state's programme.
            """
        ),
        SourceEntry(
            key: "healthit_get_your_health_record",
            title: "Get It, Check It, Use It: how to get your health record",
            agency: "Office of the National Coordinator for Health Information Technology",
            urlString: "https://www.healthit.gov/how-to-get-your-health-record",
            subjects: [.healthRecordsAccess],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            Explains the federal right of access. Each practice runs its own \
            portal and its own sign-up, so the steps come from them.
            """
        ),
        SourceEntry(
            key: "childcare_gov",
            title: "Childcare.gov",
            agency: "HHS Administration for Children and Families, Office of Child Care",
            urlString: "https://childcare.gov/",
            subjects: [.childcare],
            reviewedOn: day(2026, 8, 11),
            status: .verified,
            limitations: """
            A directory of state child care resource and referral agencies and \
            of financial assistance. It does not hold any individual \
            provider's waitlist or deposit terms.
            """
        )
    ]

    private static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        RequirementCatalog.day(year, month, dayOfMonth)
    }
}
