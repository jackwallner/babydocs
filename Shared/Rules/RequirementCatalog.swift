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
    var marketplaceKind: MarketplaceKind = .unknown
    var hasDependentCareFSA: Bool = false
    var wantsPassport: Bool = false
    var wants529: Bool = false
    var wantsNewbornAccount: Bool = false
    var parentalLeaveTakers: ParentalLeaveTakers = .nobody
    /// The family's own name for their job-based plan. Cosmetic to the rule and
    /// not cosmetic to the parent: a reminder that says "add Rosa to the Acme
    /// PPO" is one they can act on without opening anything.
    var employerPlanName: String = ""
    var benefitsContactNote: String = ""

    var takingParentalLeave: Bool { parentalLeaveTakers != .nobody }

    /// What to call the job-based plan in a sentence.
    var planPhrase: String {
        let trimmed = employerPlanName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "the job-based health plan" : "the \(trimmed) plan"
    }

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

/// Where a rule's statement comes from, or why nothing can be cited.
///
/// The second case is the important one. A rule that reaches for the nearest
/// plausible government URL rather than admitting it has none is how a childcare
/// prompt ends up citing a birth-certificate page: formally a `.gov` link,
/// substantively a lie about where the advice came from.
enum RuleSourcing: Sendable {
    /// Cites a manifest entry, which must itself cover this subject.
    case cite(key: String, subject: SourceSubject)
    /// Deliberately uncited, with the reason shown to the parent.
    case none(reason: String)
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
    /// The title with this family's own words in it, when there are any worth
    /// putting there. Defaults to `title`, which is what nineteen of the twenty
    /// rules use: a rule only overrides this when the family told the app
    /// something that makes the sentence more actionable, never to decorate it.
    var titleForFamily: (@Sendable (RuleInput) -> String)?
    /// The navigation-bar title. A full task title is a sentence, and a sentence
    /// truncates to "Order certified copies of the birth cer..." in a nav bar,
    /// which tells a parent nothing.
    let shortTitle: String
    let category: RequirementCategory
    /// Ascending. Ties inside a due-date bucket break on this, so the two hard
    /// insurance deadlines always sit above the nice-to-haves.
    let sortWeight: Int
    let sourcing: RuleSourcing
    let documents: [DocumentSpec]
    /// Whether this is a thing you send away and then wait for.
    ///
    /// True unlocks follow-up tracking on the task: the family records when it
    /// went and what the office told them to expect, and the app says something
    /// when that date passes. **No turnaround figure is hardcoded anywhere in
    /// this catalog.** Processing times move constantly and differ by county,
    /// so the only trustworthy number is the one the office gave this family,
    /// and the app asks for that rather than guessing on their behalf.
    var isPostedAway: Bool = false

    /// Does this apply to this family at all?
    let applies: @Sendable (RuleInput) -> Bool
    /// One sentence about *this* family. A task that cannot say why it is on
    /// the list is a generic checklist item, which is the thing this app exists
    /// not to be.
    let detail: @Sendable (RuleInput) -> String
    let deadline: @Sendable (RuleInput) -> Deadline
    let link: @Sendable (RuleInput) -> OfficialLink?

    var id: String { key }

    func title(for input: RuleInput) -> String {
        titleForFamily?(input) ?? title
    }

    /// The manifest entry behind this rule, or nil when the rule says outright
    /// that there is nothing to cite.
    var source: SourceEntry? {
        guard case .cite(let key, _) = sourcing else { return nil }
        return SourceManifest.entry(key)
    }

    /// What the rule needs the source to be about. Nil for uncited rules.
    var sourceSubject: SourceSubject? {
        guard case .cite(_, let subject) = sourcing else { return nil }
        return subject
    }

    var noSourceReason: String {
        guard case .none(let reason) = sourcing else { return "" }
        return reason
    }
}

// MARK: - Catalog

enum RequirementCatalog {
    /// The oldest source review in the whole manifest, which is the only
    /// honest single number: a rule set is exactly as fresh as its stalest page.
    static var reviewedOn: Date { SourceManifest.oldestReview }

    /// Shown wherever a document or a task mentions the number. Repeated
    /// verbatim rather than paraphrased, because it has to be the same sentence
    /// every time a parent sees it.
    static let ssnWarning = "Do not type the number into Baby Docs. Nothing here needs it, and receipts and notes are stored as ordinary text on this phone."

    static let all: [RequirementRule] = [
        ssnCard,
        birthCertificate,
        employerInsurance,
        marketplaceInsurance,
        medicaidCHIP,
        coverageUnknown,
        dependentCareFSA,
        parentageAcknowledgment,
        birthRecordNameCheck,
        newbornScreeningResult,
        parentalLeaveClaim,
        secondParentLeaveClaim,
        w4Update,
        hospitalBillCheck,
        newbornAccount,
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
        shortTitle: "Social Security",
        category: .identity,
        sortWeight: 10,
        sourcing: .cite(key: "ssa_card_timing", subject: .socialSecurityNumber),
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
        isPostedAway: true,
        applies: { !$0.hasSSN },
        detail: { input in
            switch input.ssnStatus {
            case .requestedAtHospital:
                return "You requested it on the hospital form. Nothing else is needed unless the card has not arrived, and it blocks the tax return, the $1,000 newborn account and most bank accounts until it does."
            case .appliedDirectly:
                return "You applied directly with SSA. Watch for the card, then mark it received here so the tasks waiting on it open up."
            case .cardReceived:
                return "Already received."
            case .unknown:
                return "Most hospitals request this on the birth-registration form, but the request is easy to miss and nobody tells you it failed. Confirm it was made before waiting on it."
            }
        },
        deadline: { input in
            Deadline(
                date: nil,
                kind: .none,
                basis: "No legal deadline. Ask SSA what to expect for this request and record that date in the follow-up section rather than relying on a bundled turnaround time."
            )
        },
        link: { _ in
            OfficialLink(label: "Social Security: numbers for children", urlString: "https://www.ssa.gov/number-card/")
        }
    )

    static let birthCertificate = RequirementRule(
        key: "birth_certificate",
        title: "Order certified copies of the birth certificate",
        shortTitle: "Birth certificate",
        category: .identity,
        sortWeight: 20,
        sourcing: .cite(key: "usagov_birth_certificate", subject: .birthCertificateOrder),
        documents: [
            DocumentSpec(key: "parent_id", title: "Photo ID for the parent named on the record"),
            DocumentSpec(
                key: "application",
                title: "The state or county application form",
                detail: "Some states require the request to be notarized unless it is made in person."
            ),
            DocumentSpec(key: "fee", title: "The per-copy fee")
        ],
        isPostedAway: true,
        applies: { !$0.hasBirthCertificate },
        detail: { input in
            let office = StateVitalRecords.office(for: input.birthStateCode)
            let where_ = input.birthStateCode.isEmpty
                ? "the state where the birth was registered"
                : USState.displayName(for: input.birthStateCode)
            let verification: String
            switch office.check {
            case .pageRead:
                verification = "We have read that office's own page."
            case .summaryChecked:
                verification = "We have checked that address against the office's own guidance, though nobody here has read the page end to end."
            case .federalFallback:
                verification = "We do not carry a specific office for this place yet, so the link goes to the national directory rather than to one we would be guessing at."
            }
            return "Issued by \(where_), not by the hospital and not federally. Order two or three certified copies at once: the passport application keeps one, and a second request later costs the same fee and the same wait. Office: \(office.officeName). \(verification)"
        },
        deadline: { input in
            Deadline(
                date: nil,
                kind: .none,
                basis: "No legal deadline. Ask the issuing office when the record and certified copies will be ready, because filing and processing times differ by jurisdiction."
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
        shortTitle: "Check the record",
        category: .identity,
        sortWeight: 55,
        // Deliberately uncited. Corrections are state law end to end, and no
        // federal page states the window, the fee or the form. Citing the
        // federal ordering page here, which is what this rule used to do, would
        // be an official-looking link that does not support a word of it.
        sourcing: .none(reason: """
        Correction windows, fees and forms are set by the state that issued the \
        record, and no federal page states them. Rather than cite a page that \
        does not say this, the task sends you to the issuing office.
        """),
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
        // Filled in with the plan's own name when the family gave one. The
        // title is what a notification reads out at 9am on day 23, and "add
        // Rosa to the Acme PPO" is a sentence somebody can act on without
        // opening anything.
        titleForFamily: { input in
            let trimmed = input.employerPlanName.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty
                ? "Add the baby to the job-based health plan"
                : "Add the baby to the \(trimmed) plan"
        },
        shortTitle: "Job-based plan",
        category: .insurance,
        sortWeight: 1,
        // The Marketplace glossary used to stand in for this, which is the wrong
        // authority: a job-based plan's window comes from the federal special
        // enrollment rules the Department of Labor administers, not from
        // HealthCare.gov.
        sourcing: .cite(key: "dol_newborn_special_enrollment", subject: .employerCoverageEnrollment),
        documents: [
            DocumentSpec(key: "enrollment_form", title: "The plan's dependent enrollment form"),
            DocumentSpec(
                key: "proof_of_birth",
                title: "Proof of the birth",
                detail: "Most plans accept the hospital record while the certificate is still being issued."
            ),
            DocumentSpec(
                key: "ssn_or_pending",
                title: "Whether the baby's Social Security number has been issued yet",
                detail: "Plans generally cannot refuse enrollment for a number that has not arrived. Tell them it is pending. \(ssnWarning)"
            ),
            DocumentSpec(
                key: "benefits_contact",
                title: "Your benefits administrator's name and number",
                detail: "They are the only ones who can tell you your plan's exact window, which may be longer than the federal floor."
            )
        ],
        applies: { $0.insuranceKind == .employer },
        detail: { input in
            var text = "This is the hardest date in the whole list, and it is handled by your employer's benefits administrator rather than by any website. Federal rules give you at least 30 days from the birth, and the plan then has to make coverage effective from the date of birth, which is what makes the hospital bill get paid. Outside the window you are waiting for open enrollment."
            let contact = input.benefitsContactNote.trimmingCharacters(in: .whitespaces)
            if !contact.isEmpty {
                text += " You said to contact: \(contact)."
            }
            return text
        },
        deadline: { input in
            Deadline(
                date: addDays(30, to: input.birthDate),
                kind: .hard,
                basis: "Federal rules give at least 30 days after a birth to request enrollment in a job-based plan, and coverage is then effective from the birth date. Your plan may allow longer. Ask your benefits administrator for the exact date and work to whichever is sooner."
            )
        },
        link: { _ in
            OfficialLink(
                label: "Department of Labor: special enrollment after a birth",
                urlString: "https://webapps.dol.gov/elaws/ebsa/health/72.asp"
            )
        }
    )

    static let marketplaceInsurance = RequirementRule(
        key: "insurance_marketplace",
        title: "Report the birth to the Marketplace and add the baby",
        shortTitle: "Marketplace",
        category: .insurance,
        sortWeight: 2,
        sourcing: .cite(key: "healthcaregov_special_enrollment", subject: .marketplaceCoverageEnrollment),
        documents: [
            DocumentSpec(key: "marketplace_login", title: "Your Marketplace account sign-in"),
            DocumentSpec(key: "proof_of_birth", title: "Proof of the birth"),
            DocumentSpec(key: "household_income", title: "Current household income estimate"),
            DocumentSpec(
                key: "first_premium",
                title: "The first premium payment, once a plan is selected",
                detail: "Enrolling is not the last step. Coverage does not start until the first payment is made."
            )
        ],
        isPostedAway: true,
        applies: { $0.insuranceKind == .marketplace },
        detail: { input in
            let base = "Reporting the birth is also what re-runs your savings: a larger household usually changes the premium tax credit, and the change does not happen on its own. Marketplace coverage for a new baby is generally backdated to the date of birth, and it is not in force until the first premium is paid."
            switch input.marketplaceKind {
            case .federal:
                return base
            case .state:
                return base + " Your state runs its own marketplace, so all of this happens on your state's site and in your state's account, not on HealthCare.gov."
            case .unknown:
                return base + " You have not said which marketplace you use. About a third of states run their own site rather than HealthCare.gov, and signing in to the wrong one costs days inside a window that does not stop for it, so start from the state picker below."
            }
        },
        deadline: { input in
            Deadline(
                date: addDays(60, to: input.birthDate),
                kind: .hard,
                basis: input.marketplaceKind == .federal
                    ? "HealthCare.gov gives 60 days from the birth to enroll the baby, and the coverage then starts on the day of the birth."
                    : "Marketplace special enrollment after a birth is 60 days. If your state runs its own marketplace, that window is the same but the site, the account and the documents are your state's, so do this there rather than on HealthCare.gov and confirm the date while you are in it."
            )
        },
        // **The link is the part the state answer changes, not the date.**
        //
        // A family on a state exchange sent to HealthCare.gov signs in, is told
        // it does not serve their state, and loses days inside a window that
        // does not stop for it. HealthCare.gov's own state page is the honest
        // middle: federal, read, and it carries a state picker, which is the
        // same trade `StateVitalRecords` makes rather than guessing twenty-one
        // state URLs.
        link: { input in
            switch input.marketplaceKind {
            case .federal:
                return OfficialLink(
                    label: "HealthCare.gov: report a life change",
                    urlString: "https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/"
                )
            case .state, .unknown:
                return OfficialLink(
                    label: "Find your state's Marketplace",
                    urlString: "https://www.healthcare.gov/marketplace-in-your-state/"
                )
            }
        }
    )

    static let medicaidCHIP = RequirementRule(
        key: "insurance_medicaid_chip",
        title: "Apply for Medicaid or CHIP coverage",
        shortTitle: "Medicaid or CHIP",
        category: .insurance,
        sortWeight: 3,
        sourcing: .cite(key: "healthcaregov_medicaid_chip", subject: .medicaidCHIP),
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
        shortTitle: "Dependent care FSA",
        category: .insurance,
        sortWeight: 25,
        // This rule used to cite "IRS Topic 602" while linking IRS Topic 313,
        // which is college savings. The label was right and the address was
        // somebody else's subject entirely.
        sourcing: .cite(key: "irs_pub_503", subject: .dependentCareBenefits),
        documents: [
            DocumentSpec(key: "benefits_portal", title: "Your employer's benefits portal sign-in"),
            DocumentSpec(key: "care_estimate", title: "An estimate of childcare spending for the rest of the year"),
            DocumentSpec(
                key: "plan_window",
                title: "The plan's own election-change window, in writing",
                detail: "The IRS sets what a dependent care benefit is. Your employer's plan sets how long you have."
            )
        ],
        applies: { $0.hasDependentCareFSA },
        detail: { _ in
            "A birth is a qualifying life event for the dependent care FSA, and it is a separate election from the medical plan. This is the one people miss: they add the baby to the health plan and never touch the FSA, and the election is then locked until the next open enrollment."
        },
        // **Not a hard deadline, because the app does not know the date.**
        //
        // It shipped as one: 30 days after the birth, drawn in red, and
        // scheduled a notification, while the basis directly underneath said
        // the number belongs to the employer's plan document rather than to the
        // law. A red date the app invented is worse than no date, and it also
        // broke the promise in Settings that only the two insurance windows ever
        // notify. Thirty days is the common case and it is offered as one; the
        // parent's own plan window is the thing they are being sent to find.
        deadline: { input in
            Deadline(
                date: addDays(30, to: input.birthDate),
                kind: .recommended,
                basis: "Your plan sets this window, not the IRS, and 30 days is only the commonest version of it. Ask your benefits administrator or read the plan document for your own date, and work to that. This app will not put a red date on a number it cannot check."
            )
        },
        link: { _ in
            OfficialLink(
                label: "IRS: child and dependent care expenses",
                urlString: "https://www.irs.gov/publications/p503"
            )
        }
    )

    /// What "Not sure yet" produces instead of silence.
    ///
    /// The intake used to refuse to continue until a coverage category was
    /// picked, which sounds like rigour and is the opposite: a parent who is
    /// between jobs, mid-COBRA, or simply does not know what their partner's
    /// plan is guesses, and a guess here turns on the wrong hard deadline or
    /// turns off the right one. Letting them say so is only honest if the app
    /// then does something about it, so the unanswered question becomes the task.
    static let coverageUnknown = RequirementRule(
        key: "coverage_unknown",
        title: "Find out which enrollment window applies to you",
        shortTitle: "Which window",
        category: .insurance,
        sortWeight: 0,
        // Deliberately uncited. There is no page that answers this, because the
        // answer is a fact about this household rather than about the law.
        sourcing: .none(reason: """
        No page can answer this one: which window applies depends on where your \
        coverage comes from, and only you can find that out. Once you tell Baby \
        Docs, this turns into the real task, with the real date and the office \
        that runs it.
        """),
        documents: [
            DocumentSpec(
                key: "who_covers_us",
                title: "Whose plan the family is on, and the number on the card",
                detail: "A partner's employer, a Marketplace account, Medicaid or CHIP, or nothing yet."
            )
        ],
        applies: { $0.insuranceKind == .unknown },
        detail: { _ in
            "This is the only unanswered question in your plan that costs money. A job-based plan has to give at least 30 days from the birth and the Marketplace gives 60, and both start the coverage on the day of the birth, which is what gets the hospital bill paid. Medicaid and CHIP take applications all year, so if that is the answer there is nothing to miss. Find out which one it is, then set it in your household answers and the real deadline appears here."
        },
        deadline: { input in
            Deadline(
                date: addDays(14, to: input.birthDate),
                kind: .recommended,
                basis: "Not a deadline anyone set: the shortest real window is 30 days, so answering this inside a fortnight leaves room to actually use it. Baby Docs will not put a red date or a reminder on a window it cannot name."
            )
        },
        link: { _ in nil }
    )

    static let hospitalBillCheck = RequirementRule(
        key: "hospital_bill_check",
        title: "Check the hospital billed under the baby's own coverage",
        shortTitle: "Hospital bills",
        category: .insurance,
        sortWeight: 60,
        // Previously cited a Marketplace enrollment page, which says nothing
        // about claims, explanations of benefits or appeals.
        sourcing: .cite(key: "healthcaregov_appeals", subject: .claimsAndAppeals),
        documents: [
            DocumentSpec(key: "eob", title: "The explanation of benefits for the delivery stay"),
            DocumentSpec(key: "member_id", title: "The baby's member ID card or number"),
            DocumentSpec(
                key: "denial_notice",
                title: "Any denial notice, if a charge came back unpaid",
                detail: "The appeal window and the address to send it to are printed on the notice itself."
            )
        ],
        applies: { $0.insuranceKind == .employer || $0.insuranceKind == .marketplace },
        detail: { input in
            "A newborn's nursery and pediatric charges are billed against the baby's own coverage, not the birth parent's. Enrollment is backdated to the date of birth, so a bill that arrives showing \(input.shortName) as uninsured usually means the enrollment landed late in the insurer's system rather than that you owe it. Call the number on the bill before you pay it, and if a claim is refused you have a right to an internal appeal and an external review."
        },
        deadline: { input in
            Deadline(
                date: addDays(60, to: input.birthDate),
                kind: .recommended,
                basis: "No deadline of its own, but appeal windows run from the date on the denial notice or explanation of benefits, so it is worth catching early."
            )
        },
        link: { _ in
            OfficialLink(
                label: "HealthCare.gov: appeal an insurance decision",
                urlString: "https://www.healthcare.gov/appeal-insurance-company-decision/appeals/"
            )
        }
    )

    // MARK: Parentage

    static let parentageAcknowledgment = RequirementRule(
        key: "parentage_acknowledgment",
        title: "Establish the second parent on the record",
        shortTitle: "Parentage",
        category: .parentage,
        sortWeight: 15,
        sourcing: .cite(key: "acf_new_parent_checklist", subject: .parentageEstablishment),
        documents: [
            DocumentSpec(
                key: "vap_form",
                title: "Your state's voluntary acknowledgment form",
                detail: "Before discharge, ask the hospital's birth registrar for it by name. They are usually the office that holds it, and they are on the ward."
            ),
            DocumentSpec(key: "both_ids", title: "Photo ID for both parents"),
            DocumentSpec(key: "witness", title: "A notary or witness, if your state requires one"),
            DocumentSpec(
                key: "rescission_window",
                title: "How long a signature can be withdrawn, in writing",
                detail: "Ask before signing, not after. It is a fixed period in every state and it is short, and after it closes the acknowledgment is usually as hard to undo as a court order."
            )
        ],
        isPostedAway: true,
        applies: { $0.parentage == .unmarriedBothParents && !$0.secondParentOnRecord },
        detail: { input in
            let state = input.birthStateCode.isEmpty
                ? "your state"
                : USState.displayName(for: input.birthStateCode)
            // The link below is a federal directory of child support agencies,
            // which is the right federal door and is not the same as the form.
            // Saying which office actually holds it is the part that saves a
            // fortnight, so it is in the first screenful rather than implied.
            return "This is legally significant and it is state law, so \(state) sets the form, the witnessing and the window in which a signature can be withdrawn. It affects the birth record, inheritance, benefits and custody.\n\nThe fastest door is the hospital's birth registrar before discharge; after that it is usually the state vital records office or the child support agency, and the directory below is how to find the one for \(state). Ask how long a signature can be withdrawn before you sign, not after.\n\nThis app will not prepare or file it for you, and if anything about the situation is contested or either parent is unsure, that is a conversation with a lawyer rather than a form to sign today."
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
                label: "Find your state's child support agency",
                urlString: "https://acf.gov/css/contact-information/state-and-tribal-child-support-agency-contacts"
            )
        }
    )

    // MARK: Work and leave

    static let parentalLeaveClaim = RequirementRule(
        key: "parental_leave_claim",
        title: "File the parental leave claim",
        titleForFamily: { input in
            input.parentalLeaveTakers == .bothParents
                ? "File the first parent's leave claim"
                : "File the parental leave claim"
        },
        shortTitle: "Parental leave",
        category: .work,
        sortWeight: 12,
        sourcing: .cite(key: "dol_fmla", subject: .familyLeave),
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
            var text = "FMLA protects the job but is unpaid. Whether anything is paid depends on your employer's policy and on whether \(state) runs a paid family leave programme, and the state programmes are the ones with real filing windows measured in weeks."
            if input.parentalLeaveTakers == .bothParents {
                text += " You said both parents are taking leave, so this is the first parent's claim and there is a second task for the other one: two employers, two sets of forms, and possibly two different windows."
            }
            return text
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

    /// **The second parent's claim is a second task, not a footnote on the
    /// first.**
    ///
    /// Leave is not a household arrangement, it is a claim: each parent files
    /// with their own employer, under their own policy, and often under a
    /// different state programme rule than the one that covers the birth
    /// parent. One shared row meant one tick, one assignee and one set of
    /// receipts for two separate pieces of paperwork, and the commonest way the
    /// second one gets missed is that nothing ever asked about it.
    static let secondParentLeaveClaim = RequirementRule(
        key: "parental_leave_claim_second",
        title: "File the second parent's leave claim",
        shortTitle: "Second parent's leave",
        category: .work,
        sortWeight: 13,
        sourcing: .cite(key: "dol_fmla", subject: .familyLeave),
        documents: [
            DocumentSpec(key: "employer_form", title: "The second parent's employer leave request form"),
            DocumentSpec(key: "proof_of_birth", title: "Proof of the birth"),
            DocumentSpec(
                key: "policy_window",
                title: "The second parent's own notice window, in writing",
                detail: "Employer policies for the non-birth parent differ from the birth parent's, and so does the amount of notice they ask for."
            )
        ],
        applies: { $0.parentalLeaveTakers == .bothParents },
        detail: { input in
            let state = input.residenceStateCode.isEmpty
                ? "your state"
                : USState.displayName(for: input.residenceStateCode)
            return "A separate claim, with a separate employer and possibly a separate programme. Bonding leave for the non-birth parent is often governed by different rules than the birth parent's own leave, both in \(state)'s programme and in the employer's policy, so the two dates cannot be assumed to match. Assign this one to whoever is filing it."
        },
        deadline: { input in
            Deadline(
                date: addDays(30, to: input.birthDate),
                kind: .recommended,
                basis: "FMLA sets no filing deadline for the employee, but employer policies and state paid-leave programmes do, and bonding leave for a second parent commonly has to start inside the first year and be claimed far earlier than that."
            )
        },
        link: { _ in
            OfficialLink(label: "Department of Labor: FMLA", urlString: "https://www.dol.gov/agencies/whd/fmla")
        }
    )

    static let w4Update = RequirementRule(
        key: "w4_update",
        title: "Update tax withholding at work",
        shortTitle: "Withholding",
        category: .work,
        sortWeight: 70,
        sourcing: .cite(key: "irs_form_w4", subject: .taxWithholding),
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

    static let newbornAccount = RequirementRule(
        key: "trump_account",
        title: "Claim the $1,000 newborn account",
        shortTitle: "Newborn account",
        category: .money,
        sortWeight: 30,
        sourcing: .cite(key: "irs_form_4547_instructions", subject: .trumpAccounts),
        documents: [
            DocumentSpec(
                key: "ssn",
                title: "Confirmation that the baby's Social Security number has been issued",
                detail: "The election cannot be made until SSA has issued a number valid for employment. Baby Docs tracks whether it exists and nothing else. \(ssnWarning)"
            ),
            DocumentSpec(key: "form_4547", title: "Form 4547, Trump Account Election, and its current instructions"),
            DocumentSpec(
                key: "eligibility_check",
                title: "The instructions' own eligibility list, read once",
                detail: "Citizenship and a birth year are not the whole test. It also turns on nobody having made this election for the child already, on your relationship to the child, and on your expecting to claim them for the tax year."
            ),
            DocumentSpec(key: "account_details", title: "The account the contribution should go to")
        ],
        applies: { input in
            guard input.isUSCitizen, input.wantsNewbornAccount else { return false }
            let year = Calendar.current.component(.year, from: input.birthDate)
            return (2025...2028).contains(year)
        },
        detail: { input in
            // The official name is stated once, deliberately. The government
            // calls these Trump Accounts, the IRS page lives at
            // irs.gov/trumpaccounts and the form is titled "Trump Account
            // Election", so a parent who follows the link without having read
            // the term here would arrive somewhere that looks like the wrong
            // page and turn around. Naming it once is what makes the link work.
            let official = "The IRS calls these Trump Accounts, which is the name on the form and on irs.gov."
            // Deliberately "may qualify" rather than "gets". This task is on the
            // list because of two answers, citizenship and a birth year, and the
            // IRS test has more in it than that: an SSN issued to the child, no
            // election already made for them, and the person electing expecting
            // to claim the child. Promising a thousand dollars from two toggles
            // and letting the form disagree later is how a helpful task becomes
            // a broken one.
            let conditions = "Two other conditions sit behind it and only the instructions can settle them: no election having been made for this child already, and the person electing expecting to claim them for the tax year."
            return input.hasSSN
                ? "\(input.shortName) has an SSN, so the election can be made. US citizen children born from 2025 through 2028 may qualify for a one-time $1,000 federal contribution. \(conditions) \(official)"
                : "US citizen children born from 2025 through 2028 may qualify for a one-time $1,000 federal contribution. The election needs a Social Security number issued to the child first, so this one is waiting on the SSN card. \(conditions) \(official)"
        },
        deadline: { _ in
            Deadline(
                date: nil,
                kind: .recommended,
                basis: "The current Form 4547 instructions set no filing deadline: the election can be made at any time, including with a return. They also say no pilot contribution is deposited before 4 July 2026. Read the current instructions before relying on any date, because a wrong date on a one-time $1,000 election is worse than no date."
            )
        },
        link: { _ in
            OfficialLink(label: "IRS: the official page", urlString: "https://www.irs.gov/trumpaccounts")
        }
    )

    static let taxDependent = RequirementRule(
        key: "tax_dependent",
        title: "Claim the baby on your next tax return",
        shortTitle: "Tax return",
        category: .money,
        sortWeight: 75,
        sourcing: .cite(key: "irs_child_tax_credit", subject: .childTaxCredit),
        documents: [
            DocumentSpec(
                key: "ssn",
                title: "The baby's Social Security card, for whoever prepares the return",
                detail: ssnWarning
            ),
            DocumentSpec(key: "childcare_receipts", title: "Childcare receipts and the provider's tax ID, if any")
        ],
        applies: { _ in true },
        detail: { input in
            let year = Calendar.current.component(.year, from: input.birthDate)
            return "A baby born at any point in \(year) counts as a dependent for the whole of \(year). The Child Tax Credit needs a valid SSN for the child issued before the return's due date, which is the real reason the SSN task sits at the top of this list. Whether you qualify depends on facts this app does not hold, so check the year you are filing for or ask whoever prepares the return."
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
        shortTitle: "529 account",
        category: .money,
        sortWeight: 85,
        sourcing: .cite(key: "irs_topic_313", subject: .qualifiedTuitionPrograms),
        documents: [
            DocumentSpec(
                key: "ssn",
                title: "The baby's Social Security card, which the provider will ask to see",
                detail: ssnWarning
            ),
            DocumentSpec(key: "beneficiary_details", title: "The baby's full legal name and date of birth"),
            DocumentSpec(key: "funding", title: "The account you will fund it from")
        ],
        applies: { $0.wants529 },
        detail: { input in
            let state = input.residenceStateCode.isEmpty
                ? "your state"
                : USState.displayName(for: input.residenceStateCode)
            return "Optional and entirely yours to time. Worth checking whether \(state) gives a state income tax deduction for its own plan before picking one, because that is usually the only reason to prefer a home-state plan. Baby Docs does not recommend a plan or a provider."
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
        shortTitle: "Passport",
        category: .travel,
        sortWeight: 80,
        sourcing: .cite(key: "usagov_child_passport", subject: .passports),
        documents: [
            DocumentSpec(
                key: "certified_birth_certificate",
                title: "A certified birth certificate naming both parents",
                detail: "The original is submitted and mailed back. An informational or hospital copy is not accepted."
            ),
            DocumentSpec(key: "both_parents", title: "Both parents present, or a notarized consent form from the absent one"),
            DocumentSpec(key: "parent_ids", title: "Photo ID for each parent, plus a photocopy of each"),
            DocumentSpec(
                key: "photo",
                title: "A passport photo of the baby",
                detail: "Check the State Department's current photo rules before you take it. There are specific allowances for infants, and a rejected photo costs an appointment."
            )
        ],
        isPostedAway: true,
        applies: { $0.wantsPassport },
        detail: { input in
            input.hasBirthCertificate
                ? "A first passport for a child under 16 is applied for in person, and a parent has to be present to sign. Book the appointment before you need it: processing times move, and a child's passport is valid for five years."
                : "Blocked until the certified birth certificate arrives, because the application submits the original. Every child under 16 applies in person, with a parent present to sign."
        },
        deadline: { _ in
            Deadline(date: nil, kind: .none, basis: "No deadline. Driven by when you plan to travel.")
        },
        link: { _ in
            OfficialLink(label: "USAGov: passport for a child", urlString: "https://www.usa.gov/child-passport")
        }
    )

    // MARK: Household

    static let newbornScreeningResult = RequirementRule(
        key: "newborn_screening_result",
        title: "Get the newborn screening results in writing",
        shortTitle: "Screening results",
        category: .household,
        sortWeight: 40,
        // Previously cited the federal birth-certificate page, which has nothing
        // to do with newborn screening.
        sourcing: .cite(key: "medlineplus_newborn_screening", subject: .newbornScreening),
        documents: [
            DocumentSpec(key: "screening_letter", title: "The screening result letter or portal printout"),
            DocumentSpec(key: "hearing_result", title: "The hearing screening result")
        ],
        applies: { _ in true },
        // **A records errand, and it says where it stops.**
        //
        // The one thing a parent must not take from this task is that silence
        // from the app means the results were fine, so the boundary is in the
        // first screenful rather than in a disclaimer: an out-of-range result is
        // a phone call from a person, and it does not wait for a checklist.
        detail: { _ in
            "Every state screens newborns for a panel of conditions, plus hearing and a heart-oxygen check, and the results go to the pediatrician rather than to you. Ask the practice for a copy for your own file, because the passport, some daycare enrollments and any specialist referral will want it. If anything is out of range, the practice or the state health department phones you and it is urgent: this task is not how you would find out, and Baby Docs does not read, hold or interpret a result."
        },
        deadline: { input in
            Deadline(
                date: nil,
                kind: .none,
                basis: "No deadline. Ask the pediatric practice when the results will be available and record that date in the follow-up section if you need to chase them."
            )
        },
        link: { _ in
            OfficialLink(
                label: "Newborn screening in your state",
                urlString: "https://newbornscreening.hrsa.gov/your-state"
            )
        }
    )

    static let beneficiaryUpdate = RequirementRule(
        key: "beneficiary_update",
        title: "Update beneficiaries on life insurance and retirement accounts",
        shortTitle: "Beneficiaries",
        category: .household,
        sortWeight: 90,
        // Household planning rather than government paperwork. Every account's
        // rules come from its own plan documents, so there is nothing official
        // to cite and the rule says so instead of borrowing a plausible URL.
        sourcing: .none(reason: """
        This is household planning, not government paperwork. Beneficiary rules \
        come from each account's own plan documents, so there is no official \
        page to send you to.
        """),
        documents: [
            DocumentSpec(key: "account_list", title: "A list of the accounts that carry a beneficiary"),
            DocumentSpec(
                key: "ssn",
                title: "The baby's Social Security card, which some forms ask to see",
                detail: ssnWarning
            )
        ],
        applies: { _ in true },
        detail: { _ in
            "Beneficiary designations on retirement accounts and life insurance override a will, so this is not covered by writing one. Naming a minor directly has consequences worth understanding first, which is usually why people name a trust or a custodian instead. Baby Docs is not a financial adviser and this is a prompt, not advice."
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
        shortTitle: "Guardian",
        category: .household,
        sortWeight: 95,
        sourcing: .none(reason: """
        A valid will is state law and this app is not a lawyer. There is no \
        federal page that sets it, and we will not link one state's page we have \
        not read.
        """),
        documents: [
            DocumentSpec(key: "guardian_choice", title: "Who you have both agreed on, and a second choice"),
            DocumentSpec(key: "existing_will", title: "Any existing will")
        ],
        applies: { _ in true },
        detail: { _ in
            "The nomination of a guardian for a minor is made in a will, and without one a court chooses. Requirements for a valid will are state law. This app tracks the task and nothing else: it does not draft or store legal documents, and the questions this raises are for a lawyer."
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
        shortTitle: "Pediatric portal",
        category: .household,
        sortWeight: 100,
        sourcing: .cite(key: "healthit_get_your_health_record", subject: .healthRecordsAccess),
        documents: [
            DocumentSpec(key: "practice_details", title: "The practice's portal invitation or sign-up link")
        ],
        applies: { _ in true },
        detail: { _ in
            "The portal is where the immunization record lives, and daycare, school and travel all ask for it eventually. Federal law gives you the right to a copy of your child's record whether or not the practice runs a portal. Both parents should have their own login rather than sharing one."
        },
        deadline: { _ in
            Deadline(date: nil, kind: .none, basis: "No deadline.")
        },
        link: { _ in
            OfficialLink(
                label: "How to get a health record",
                urlString: "https://www.healthit.gov/how-to-get-your-health-record"
            )
        }
    )

    static let childcareWaitlist = RequirementRule(
        key: "childcare_waitlist",
        title: "Get on childcare waitlists",
        shortTitle: "Childcare",
        category: .household,
        sortWeight: 110,
        sourcing: .cite(key: "childcare_gov", subject: .childcare),
        documents: [
            DocumentSpec(key: "shortlist", title: "A shortlist of places, with their deposit terms")
        ],
        applies: { _ in true },
        detail: { _ in
            "Not paperwork the government asks for, and on this list only because the waits are measured in months and the deposits are usually refundable. Your state's child care resource and referral agency also holds the list of financial help, which is worth a look before you pay a deposit. Nothing here is time-critical in the way the insurance window is."
        },
        deadline: { _ in
            Deadline(date: nil, kind: .none, basis: "No deadline.")
        },
        link: { _ in
            OfficialLink(label: "Childcare.gov: find child care", urlString: "https://childcare.gov/")
        }
    )

    // MARK: Helpers

    static func addDays(_ days: Int, to date: Date) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: date)
    }

    /// Noon UTC, not midnight. These dates are only ever *displayed* ("checked
    /// on the 9th"), and midnight UTC renders as the previous day everywhere
    /// west of Greenwich, so a rule reviewed today reads as reviewed yesterday
    /// to every user in the country this app is for.
    static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
