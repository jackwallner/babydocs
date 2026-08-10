import Foundation

// MARK: - Inputs

/// Everything a rule is allowed to look at, as a plain value.
///
/// The catalog never sees SwiftData. That is what makes the whole rule set
/// testable as pure functions: a plan for a Californian marketplace family with
/// unmarried parents is a struct literal and an assertion, not a container, a
/// context and a fixture.
struct RuleInput: Sendable, Equatable {
    var childName: String = ""
    var birthDate: Date = Date()
    var birthStateCode: String = ""
    var isUSCitizen: Bool = true
    var hasSSN: Bool = false
    var ssnStatus: SSNStatus = .unknown
    var hasBirthCertificate: Bool = false

    var residenceStateCode: String = ""
    var parentage: ParentageSituation = .unknown
    var secondParentOnRecord: Bool = false
    var insuranceKind: InsuranceKind = .unknown
    var hasDependentCareFSA: Bool = false
    var wantsPassport: Bool = false
    var wants529: Bool = false
    var wantsTrumpAccount: Bool = false
    var takingParentalLeave: Bool = false

    var shortName: String {
        let trimmed = childName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "your baby" : trimmed
    }
}

/// The date a rule resolves to for one family, with the reason attached.
///
/// The reason is not decoration. "Within 30 days" and "within 30 days, because
/// job-based plans must allow at least that long after a birth" are different
/// products: the second one is checkable, and a parent who can check it will
/// trust the other nineteen dates.
struct Deadline: Sendable, Equatable {
    var date: Date?
    var kind: DeadlineKind
    var basis: String

    static let none = Deadline(date: nil, kind: .none, basis: "")
}

/// Where a rule comes from and when someone last read it.
struct SourceCitation: Sendable, Equatable {
    var label: String
    var urlString: String
    var verifiedOn: Date

    var url: URL? { URL(string: urlString) }
}

/// The button that sends the parent to the official page. Always a government
/// site, never an aggregator, and never something this app posts to on their
/// behalf.
struct OfficialLink: Sendable, Equatable {
    var label: String
    var urlString: String
}

/// One item on a task's "have these ready" list.
struct DocumentSpec: Sendable, Equatable {
    var key: String
    var title: String
    var detail: String = ""
}

// MARK: - Rule

struct RequirementRule: Identifiable, Sendable {
    let key: String
    let title: String
    let category: RequirementCategory
    /// Ascending. Ties inside a due-date bucket break on this, so the two hard
    /// insurance deadlines always sit above the nice-to-haves.
    let sortWeight: Int
    let source: SourceCitation
    let documents: [DocumentSpec]

    /// Does this apply to this family at all?
    let applies: @Sendable (RuleInput) -> Bool
    /// One sentence about *this* family. A task that cannot say why it is on
    /// the list is a generic checklist item, which is the thing this app exists
    /// not to be.
    let detail: @Sendable (RuleInput) -> String
    let deadline: @Sendable (RuleInput) -> Deadline
    let link: @Sendable (RuleInput) -> OfficialLink?

    var id: String { key }
}

// MARK: - Catalog

enum RequirementCatalog {
    /// The day this whole rule set was last reviewed end to end. Surfaced in
    /// Settings, because a rules app that cannot tell you how old its rules are
    /// is asking for trust it has not earned.
    static let reviewedOn = day(2026, 8, 9)

    static let all: [RequirementRule] = [
        ssnCard,
        birthCertificate,
        employerInsurance,
        marketplaceInsurance,
        medicaidCHIP,
        dependentCareFSA,
        parentageAcknowledgment,
        birthRecordNameCheck,
        newbornScreeningResult,
        parentalLeaveClaim,
        w4Update,
        hospitalBillCheck,
        trumpAccount,
        taxDependent,
        plan529,
        passport,
        beneficiaryUpdate,
        guardianNomination,
        pediatricPortal,
        childcareWaitlist
    ]

    static func rule(key: String) -> RequirementRule? {
        all.first { $0.key == key }
    }

    // MARK: Identity

    static let ssnCard = RequirementRule(
        key: "ssn_card",
        title: "Get the Social Security number and card",
        category: .identity,
        sortWeight: 10,
        source: SourceCitation(
            label: "Social Security Administration: how long it takes",
            urlString: "https://www.ssa.gov/faqs/en/questions/KA-10041.html",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(
                key: "hospital_form",
                title: "Your copy of the hospital birth-registration form",
                detail: "The page where the Social Security number was requested, if you have it."
            ),
            DocumentSpec(key: "parent_id", title: "Photo ID for the parent applying"),
            DocumentSpec(
                key: "proof_of_birth",
                title: "Proof of the birth",
                detail: "A certified birth certificate, or the hospital record if the certificate has not arrived."
            )
        ],
        applies: { !$0.hasSSN },
        detail: { input in
            switch input.ssnStatus {
            case .requestedAtHospital:
                return "You requested it on the hospital form. Nothing else is needed unless the card has not arrived, and it blocks the tax return, the Trump Account and most bank accounts until it does."
            case .appliedDirectly:
                return "You applied directly with SSA. Watch for the card, then mark it received here so the tasks waiting on it open up."
            case .cardReceived:
                return "Already received."
            case .unknown:
                return "Most hospitals request this on the birth-registration form, but the request is easy to miss and nobody tells you it failed. Confirm it was made before waiting on it."
            }
        },
        deadline: { input in
            // No statutory deadline. The date is a follow-up trigger: SSA
            // reports roughly two weeks to process and up to two more for the
            // card to arrive, so four weeks is the point at which silence stops
            // being normal and starts being a problem worth chasing.
            Deadline(
                date: addDays(28, to: input.birthDate),
                kind: .recommended,
                basis: "No legal deadline. SSA reports about two weeks to process the request and up to two more for the card to arrive, so chase it if nothing has come by then."
            )
        },
        link: { _ in
            OfficialLink(label: "Social Security: numbers for children", urlString: "https://www.ssa.gov/number-card/")
        }
    )

    static let birthCertificate = RequirementRule(
        key: "birth_certificate",
        title: "Order certified copies of the birth certificate",
        category: .identity,
        sortWeight: 20,
        source: SourceCitation(
            label: "USAGov: how to get a birth certificate",
            urlString: "https://www.usa.gov/birth-certificate",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "parent_id", title: "Photo ID for the parent named on the record"),
            DocumentSpec(
                key: "application",
                title: "The state or county application form",
                detail: "Some states require the request to be notarized unless it is made in person."
            ),
            DocumentSpec(key: "fee", title: "The per-copy fee")
        ],
        applies: { !$0.hasBirthCertificate },
        detail: { input in
            let office = StateVitalRecords.office(for: input.birthStateCode)
            let where_ = input.birthStateCode.isEmpty
                ? "the state where the birth was registered"
                : USState.displayName(for: input.birthStateCode)
            return "Issued by \(where_), not by the hospital and not federally. Order two or three certified copies at once: the passport application keeps one, and a second request later costs the same fee and the same wait. Office: \(office.officeName)."
        },
        deadline: { input in
            Deadline(
                date: addDays(21, to: input.birthDate),
                kind: .recommended,
                basis: "No legal deadline. The record usually is not filed for one to three weeks after the birth, and the passport and several bank tasks are blocked until a certified copy is in hand."
            )
        },
        link: { input in
            let office = StateVitalRecords.office(for: input.birthStateCode)
            return OfficialLink(
                label: office.isVerified ? office.officeName : "USAGov: order a birth certificate",
                urlString: office.urlString
            )
        }
    )

    static let birthRecordNameCheck = RequirementRule(
        key: "birth_record_name_check",
        title: "Check the name and details on the certificate",
        category: .identity,
        sortWeight: 55,
        source: SourceCitation(
            label: "USAGov: correcting a birth certificate",
            urlString: "https://www.usa.gov/birth-certificate",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "certified_copy", title: "The certified copy, in hand")
        ],
        applies: { $0.hasBirthCertificate },
        detail: { input in
            "Read the certified copy against what you intended: spelling of \(input.shortName)'s name, the date, and both parents' details. States usually correct a registration error at no charge within a limited window and charge for an amendment afterwards, and every document downstream is built from this one."
        },
        deadline: { input in
            Deadline(
                date: addDays(30, to: input.birthDate),
                kind: .recommended,
                basis: "Correction windows and fees are set by the state that issued the record. Checking early is what keeps a fix inside the free window."
            )
        },
        link: { input in
            let office = StateVitalRecords.office(for: input.birthStateCode)
            return OfficialLink(label: office.officeName, urlString: office.urlString)
        }
    )

    // MARK: Insurance

    static let employerInsurance = RequirementRule(
        key: "insurance_employer",
        title: "Add the baby to the job-based health plan",
        category: .insurance,
        sortWeight: 1,
        source: SourceCitation(
            label: "HealthCare.gov: special enrollment period",
            urlString: "https://www.healthcare.gov/glossary/special-enrollment-period/",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "enrollment_form", title: "The plan's dependent enrollment form"),
            DocumentSpec(
                key: "proof_of_birth",
                title: "Proof of the birth",
                detail: "Most plans accept the hospital record while the certificate is still being issued."
            ),
            DocumentSpec(
                key: "ssn_or_pending",
                title: "The baby's Social Security number, if you have it",
                detail: "Plans generally cannot refuse enrollment for a number that has not arrived yet. Say it is pending."
            )
        ],
        applies: { $0.insuranceKind == .employer },
        detail: { _ in
            "This is the hardest date in the whole list. Job-based plans must offer at least a 30-day special enrollment period after a birth, and outside it you are waiting for open enrollment. Enrollment is normally backdated to the date of birth, which is what makes the hospital bill get paid."
        },
        deadline: { input in
            Deadline(
                date: addDays(30, to: input.birthDate),
                kind: .hard,
                basis: "Job-based plans must provide a special enrollment period of at least 30 days after a birth. Your plan may allow longer, so check the plan documents, but never assume it does."
            )
        },
        link: { _ in
            OfficialLink(
                label: "HealthCare.gov: special enrollment",
                urlString: "https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/"
            )
        }
    )

    static let marketplaceInsurance = RequirementRule(
        key: "insurance_marketplace",
        title: "Report the birth to the Marketplace and add the baby",
        category: .insurance,
        sortWeight: 2,
        source: SourceCitation(
            label: "HealthCare.gov: special enrollment period",
            urlString: "https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "marketplace_login", title: "Your Marketplace account sign-in"),
            DocumentSpec(key: "proof_of_birth", title: "Proof of the birth"),
            DocumentSpec(key: "household_income", title: "Current household income estimate")
        ],
        applies: { $0.insuranceKind == .marketplace },
        detail: { _ in
            "Reporting the birth is also what re-runs your savings: a larger household usually changes the premium tax credit, and the change does not happen on its own. Marketplace coverage for a new baby is generally backdated to the date of birth."
        },
        deadline: { input in
            Deadline(
                date: addDays(60, to: input.birthDate),
                kind: .hard,
                basis: "Marketplace special enrollment after a birth is generally 60 days. Some state-run marketplaces differ, so confirm on your own state's site."
            )
        },
        link: { _ in
            OfficialLink(
                label: "HealthCare.gov: report a life change",
                urlString: "https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/"
            )
        }
    )

    static let medicaidCHIP = RequirementRule(
        key: "insurance_medicaid_chip",
        title: "Apply for Medicaid or CHIP coverage",
        category: .insurance,
        sortWeight: 3,
        source: SourceCitation(
            label: "HealthCare.gov: getting Medicaid and CHIP",
            urlString: "https://www.healthcare.gov/medicaid-chip/getting-medicaid-chip/",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "income", title: "Household income for the last month"),
            DocumentSpec(key: "proof_of_birth", title: "Proof of the birth"),
            DocumentSpec(key: "residency", title: "Proof of state residency")
        ],
        applies: { $0.insuranceKind == .medicaidCHIP || $0.insuranceKind == .none },
        detail: { input in
            let state = input.residenceStateCode.isEmpty
                ? "your state"
                : USState.displayName(for: input.residenceStateCode)
            return "Medicaid and CHIP take applications at any time of year, so there is no window to miss here. Eligibility and the agency are set by \(state), and children qualify at higher household incomes than adults do."
        },
        deadline: { _ in
            Deadline(
                date: nil,
                kind: .none,
                basis: "No enrollment window. Applications are accepted year-round."
            )
        },
        link: { _ in
            OfficialLink(
                label: "HealthCare.gov: Medicaid and CHIP",
                urlString: "https://www.healthcare.gov/medicaid-chip/getting-medicaid-chip/"
            )
        }
    )

    static let dependentCareFSA = RequirementRule(
        key: "dependent_care_fsa",
        title: "Change the dependent care FSA election",
        category: .insurance,
        sortWeight: 25,
        source: SourceCitation(
            label: "IRS Topic 602: child and dependent care credit",
            urlString: "https://www.irs.gov/taxtopics/tc313",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "benefits_portal", title: "Your employer's benefits portal sign-in"),
            DocumentSpec(key: "care_estimate", title: "An estimate of childcare spending for the rest of the year")
        ],
        applies: { $0.hasDependentCareFSA },
        detail: { _ in
            "A birth is a qualifying life event for the dependent care FSA, and it is a separate election from the medical plan. This is the one people miss: they add the baby to the health plan and never touch the FSA, and the election is then locked until the next open enrollment."
        },
        deadline: { input in
            Deadline(
                date: addDays(30, to: input.birthDate),
                kind: .hard,
                basis: "Cafeteria-plan election changes after a qualifying life event are limited by the plan, commonly to 30 days. The number is your plan's, so confirm it in the plan documents."
            )
        },
        link: { _ in nil }
    )

    static let hospitalBillCheck = RequirementRule(
        key: "hospital_bill_check",
        title: "Check the hospital billed under the baby's own coverage",
        category: .insurance,
        sortWeight: 60,
        source: SourceCitation(
            label: "HealthCare.gov: special enrollment period",
            urlString: "https://www.healthcare.gov/glossary/special-enrollment-period/",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "eob", title: "The explanation of benefits for the delivery stay"),
            DocumentSpec(key: "member_id", title: "The baby's member ID card or number")
        ],
        applies: { $0.insuranceKind == .employer || $0.insuranceKind == .marketplace },
        detail: { input in
            "A newborn's nursery and pediatric charges are billed against the baby's own coverage, not the birth parent's. Enrollment is backdated to the date of birth, so a bill that arrives showing \(input.shortName) as uninsured usually means the enrollment landed late in the insurer's system rather than that you owe it."
        },
        deadline: { input in
            Deadline(
                date: addDays(60, to: input.birthDate),
                kind: .recommended,
                basis: "No deadline of its own, but appeal windows run from the date on the explanation of benefits, so it is worth catching early."
            )
        },
        link: { _ in nil }
    )

    // MARK: Parentage

    static let parentageAcknowledgment = RequirementRule(
        key: "parentage_acknowledgment",
        title: "Establish the second parent on the record",
        category: .parentage,
        sortWeight: 15,
        source: SourceCitation(
            label: "HHS Office of Child Support Services: establishing paternity",
            urlString: "https://www.acf.hhs.gov/css/parents/establishing-paternity",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "vap_form", title: "Your state's voluntary acknowledgment form"),
            DocumentSpec(key: "both_ids", title: "Photo ID for both parents"),
            DocumentSpec(key: "witness", title: "A notary or witness, if your state requires one")
        ],
        applies: { $0.parentage == .unmarriedBothParents && !$0.secondParentOnRecord },
        detail: { input in
            let state = input.birthStateCode.isEmpty
                ? "your state"
                : USState.displayName(for: input.birthStateCode)
            return "This is legally significant and it is state law, so \(state) sets the form, the witnessing and the window in which a signature can be withdrawn. It affects the birth record, inheritance, benefits and custody. This app will not prepare or file it for you: read your state's own form, and talk to a lawyer if anything about the situation is contested."
        },
        deadline: { input in
            Deadline(
                date: addDays(60, to: input.birthDate),
                kind: .recommended,
                basis: "Usually signed at the hospital. It can be done later, but rescission windows and the process for adding a parent afterwards are state-specific and get harder with time."
            )
        },
        link: { _ in
            OfficialLink(
                label: "Establishing parentage: state programs",
                urlString: "https://www.acf.hhs.gov/css/parents/establishing-paternity"
            )
        }
    )

    // MARK: Work and leave

    static let parentalLeaveClaim = RequirementRule(
        key: "parental_leave_claim",
        title: "File the parental leave claim",
        category: .work,
        sortWeight: 12,
        source: SourceCitation(
            label: "US Department of Labor: FMLA",
            urlString: "https://www.dol.gov/agencies/whd/fmla",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "employer_form", title: "Your employer's leave request form"),
            DocumentSpec(key: "proof_of_birth", title: "Proof of the birth"),
            DocumentSpec(key: "wage_info", title: "Recent pay stubs, if the state program asks for them")
        ],
        applies: { $0.takingParentalLeave },
        detail: { input in
            let state = input.residenceStateCode.isEmpty
                ? "Your state"
                : USState.displayName(for: input.residenceStateCode)
            return "FMLA protects the job but is unpaid. Whether anything is paid depends on your employer's policy and on whether \(state) runs a paid family leave programme, and the state programmes are the ones with real filing windows measured in weeks."
        },
        deadline: { input in
            Deadline(
                date: addDays(30, to: input.birthDate),
                kind: .recommended,
                basis: "FMLA itself has no filing deadline for the employee, but state paid-leave programmes do, and several of them run from the first day of leave rather than from the birth."
            )
        },
        link: { _ in
            OfficialLink(label: "Department of Labor: FMLA", urlString: "https://www.dol.gov/agencies/whd/fmla")
        }
    )

    static let w4Update = RequirementRule(
        key: "w4_update",
        title: "Update tax withholding at work",
        category: .work,
        sortWeight: 70,
        source: SourceCitation(
            label: "IRS: About Form W-4",
            urlString: "https://www.irs.gov/forms-pubs/about-form-w-4",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "payroll_portal", title: "Your payroll or HR portal sign-in")
        ],
        applies: { _ in true },
        detail: { _ in
            "A dependent changes what should be withheld. Nothing is lost by leaving it, but the money sits with the IRS until you file instead of arriving in the paychecks you need it in."
        },
        deadline: { input in
            Deadline(
                date: addDays(45, to: input.birthDate),
                kind: .recommended,
                basis: "No deadline. The sooner it changes, the more paychecks it affects."
            )
        },
        link: { _ in
            OfficialLink(label: "IRS: Form W-4", urlString: "https://www.irs.gov/forms-pubs/about-form-w-4")
        }
    )

    // MARK: Money

    static let trumpAccount = RequirementRule(
        key: "trump_account",
        title: "Make the Trump Account election",
        category: .money,
        sortWeight: 30,
        source: SourceCitation(
            label: "IRS: Trump Accounts",
            urlString: "https://www.irs.gov/trumpaccounts",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(
                key: "ssn",
                title: "The baby's Social Security number",
                detail: "The election cannot be made without a valid SSN for the child."
            ),
            DocumentSpec(key: "form_4547", title: "Form 4547 and its instructions"),
            DocumentSpec(key: "account_details", title: "The account the contribution should go to")
        ],
        applies: { input in
            guard input.isUSCitizen, input.wantsTrumpAccount else { return false }
            let year = Calendar.current.component(.year, from: input.birthDate)
            return (2025...2028).contains(year)
        },
        detail: { input in
            input.hasSSN
                ? "\(input.shortName) has an SSN, so the election can be made. Eligible US citizen children born from 2025 through 2028 can receive a one-time $1,000 pilot contribution."
                : "Eligible US citizen children born from 2025 through 2028 can receive a one-time $1,000 pilot contribution, but the election needs a valid Social Security number for the child first. This one is waiting on the SSN card."
        },
        deadline: { _ in
            Deadline(
                date: nil,
                kind: .recommended,
                basis: "Read the current Form 4547 instructions for the election deadline before you rely on a date. This app does not hold one, because a wrong date on a one-time $1,000 election is worse than no date."
            )
        },
        link: { _ in
            OfficialLink(label: "IRS: Trump Accounts", urlString: "https://www.irs.gov/trumpaccounts")
        }
    )

    static let taxDependent = RequirementRule(
        key: "tax_dependent",
        title: "Claim the baby on your next tax return",
        category: .money,
        sortWeight: 75,
        source: SourceCitation(
            label: "IRS: Child Tax Credit",
            urlString: "https://www.irs.gov/credits-deductions/individuals/child-tax-credit",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "ssn", title: "The baby's Social Security number"),
            DocumentSpec(key: "childcare_receipts", title: "Childcare receipts and the provider's tax ID, if any")
        ],
        applies: { _ in true },
        detail: { input in
            let year = Calendar.current.component(.year, from: input.birthDate)
            return "A baby born at any point in \(year) counts as a dependent for the whole of \(year). The Child Tax Credit needs a valid SSN for the child issued before the return's due date, which is the real reason the SSN task sits at the top of this list."
        },
        deadline: { _ in
            Deadline(
                date: nil,
                kind: .none,
                basis: "Handled when you file. Listed here so the SSN and childcare paperwork are gathered before the return, not during it."
            )
        },
        link: { _ in
            OfficialLink(
                label: "IRS: Child Tax Credit",
                urlString: "https://www.irs.gov/credits-deductions/individuals/child-tax-credit"
            )
        }
    )

    static let plan529 = RequirementRule(
        key: "plan_529",
        title: "Open a 529 college savings account",
        category: .money,
        sortWeight: 85,
        source: SourceCitation(
            label: "IRS Topic 313: qualified tuition programs",
            urlString: "https://www.irs.gov/taxtopics/tc313",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "ssn", title: "The baby's Social Security number"),
            DocumentSpec(key: "beneficiary_details", title: "The baby's full legal name and date of birth"),
            DocumentSpec(key: "funding", title: "The account you will fund it from")
        ],
        applies: { $0.wants529 },
        detail: { input in
            let state = input.residenceStateCode.isEmpty
                ? "your state"
                : USState.displayName(for: input.residenceStateCode)
            return "Optional and entirely yours to time. Worth checking whether \(state) gives a state income tax deduction for its own plan before picking one, because that is usually the only reason to prefer a home-state plan."
        },
        deadline: { _ in
            Deadline(date: nil, kind: .none, basis: "No deadline. Open it whenever you want to.")
        },
        link: { _ in
            OfficialLink(label: "IRS: qualified tuition programs", urlString: "https://www.irs.gov/taxtopics/tc313")
        }
    )

    // MARK: Travel

    static let passport = RequirementRule(
        key: "passport",
        title: "Apply for the baby's first passport",
        category: .travel,
        sortWeight: 80,
        source: SourceCitation(
            label: "USAGov: passports",
            urlString: "https://www.usa.gov/passport",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(
                key: "certified_birth_certificate",
                title: "A certified birth certificate naming both parents",
                detail: "The original is submitted and mailed back. An informational or hospital copy is not accepted."
            ),
            DocumentSpec(key: "both_parents", title: "Both parents present, or a notarized consent form from the absent one"),
            DocumentSpec(key: "parent_ids", title: "Photo ID for each parent, plus a photocopy of each"),
            DocumentSpec(key: "photo", title: "A passport photo of the baby, eyes open, plain background")
        ],
        applies: { $0.wantsPassport },
        detail: { input in
            input.hasBirthCertificate
                ? "A first passport for a child under 16 is applied for in person, and both parents normally have to appear. Book the appointment before you need it: processing times move, and a child's passport is valid for five years."
                : "Blocked until the certified birth certificate arrives, because the application submits the original. Both parents normally have to appear in person for a child under 16."
        },
        deadline: { _ in
            Deadline(date: nil, kind: .none, basis: "No deadline. Driven by when you plan to travel.")
        },
        link: { _ in
            OfficialLink(label: "USAGov: passports", urlString: "https://www.usa.gov/passport")
        }
    )

    // MARK: Household

    static let newbornScreeningResult = RequirementRule(
        key: "newborn_screening_result",
        title: "Get the newborn screening results in writing",
        category: .household,
        sortWeight: 40,
        source: SourceCitation(
            label: "USAGov: birth and health records",
            urlString: "https://www.usa.gov/birth-certificate",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "screening_letter", title: "The screening result letter or portal printout"),
            DocumentSpec(key: "hearing_result", title: "The hearing screening result")
        ],
        applies: { _ in true },
        detail: { _ in
            "Every state screens newborns and the results go to the pediatrician, not usually to you. Ask the practice for a copy for your own file. This is a records task, not medical advice: anything about what a result means is a conversation with the pediatrician."
        },
        deadline: { input in
            Deadline(
                date: addDays(21, to: input.birthDate),
                kind: .recommended,
                basis: "No deadline. Results are typically back within a couple of weeks, and the paperwork is easiest to collect at the first well-baby visit."
            )
        },
        link: { _ in nil }
    )

    static let beneficiaryUpdate = RequirementRule(
        key: "beneficiary_update",
        title: "Update beneficiaries on life insurance and retirement accounts",
        category: .household,
        sortWeight: 90,
        source: SourceCitation(
            label: "USAGov: life events and benefits",
            urlString: "https://www.usa.gov/birth-certificate",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "account_list", title: "A list of the accounts that carry a beneficiary"),
            DocumentSpec(key: "ssn", title: "The baby's Social Security number")
        ],
        applies: { _ in true },
        detail: { _ in
            "Beneficiary designations on retirement accounts and life insurance override a will, so this is not covered by writing one. Naming a minor directly has consequences worth understanding first, which is usually why people name a trust or a custodian instead."
        },
        deadline: { input in
            Deadline(
                date: addDays(90, to: input.birthDate),
                kind: .recommended,
                basis: "No deadline. Listed at 90 days because it is the task everyone agrees to do and nobody does."
            )
        },
        link: { _ in nil }
    )

    static let guardianNomination = RequirementRule(
        key: "guardian_nomination",
        title: "Name a guardian in a will",
        category: .household,
        sortWeight: 95,
        source: SourceCitation(
            label: "USAGov: wills and estates",
            urlString: "https://www.usa.gov/birth-certificate",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "guardian_choice", title: "Who you have both agreed on, and a second choice"),
            DocumentSpec(key: "existing_will", title: "Any existing will")
        ],
        applies: { _ in true },
        detail: { _ in
            "The nomination of a guardian for a minor is made in a will, and without one a court chooses. Requirements for a valid will are state law. This app tracks the task and nothing else: it does not draft or store legal documents."
        },
        deadline: { input in
            Deadline(
                date: addDays(90, to: input.birthDate),
                kind: .recommended,
                basis: "No deadline. Ninety days is a prompt, not a rule."
            )
        },
        link: { _ in nil }
    )

    static let pediatricPortal = RequirementRule(
        key: "pediatric_portal",
        title: "Set up the pediatric patient portal",
        category: .household,
        sortWeight: 100,
        source: SourceCitation(
            label: "USAGov: health records",
            urlString: "https://www.usa.gov/birth-certificate",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "practice_details", title: "The practice's portal invitation or sign-up link")
        ],
        applies: { _ in true },
        detail: { _ in
            "The portal is where the immunization record lives, and daycare, school and travel all ask for it eventually. Both parents should have their own login rather than sharing one."
        },
        deadline: { _ in
            Deadline(date: nil, kind: .none, basis: "No deadline.")
        },
        link: { _ in nil }
    )

    static let childcareWaitlist = RequirementRule(
        key: "childcare_waitlist",
        title: "Get on childcare waitlists",
        category: .household,
        sortWeight: 110,
        source: SourceCitation(
            label: "USAGov: childcare",
            urlString: "https://www.usa.gov/birth-certificate",
            verifiedOn: reviewedOn
        ),
        documents: [
            DocumentSpec(key: "shortlist", title: "A shortlist of places, with their deposit terms")
        ],
        applies: { _ in true },
        detail: { _ in
            "Not paperwork the government asks for, and on this list only because the waits are measured in months and the deposits are usually refundable. Nothing here is time-critical in the way the insurance window is."
        },
        deadline: { _ in
            Deadline(date: nil, kind: .none, basis: "No deadline.")
        },
        link: { _ in nil }
    )

    // MARK: Helpers

    static func addDays(_ days: Int, to date: Date) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: date)
    }

    static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
