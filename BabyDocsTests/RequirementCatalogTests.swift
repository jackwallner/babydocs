import Foundation
import Testing

@testable import BabyDocs

/// The catalog is the product. These tests are the only thing standing between
/// a wrong `applies` closure and an app that quietly tells a Marketplace family
/// they have 30 days when they have 60, or never mentions the second parent to
/// the family who needed to hear about it most.
struct RequirementCatalogTests {

    private func input(
        birthDaysAgo: Int = 3,
        insurance: InsuranceKind = .employer,
        marketplace: MarketplaceKind = .unknown,
        parentage: ParentageSituation = .married,
        secondParentOnRecord: Bool = true,
        hasSSN: Bool = false,
        hasBirthCertificate: Bool = false,
        citizen: Bool = true,
        hasFSA: Bool = false,
        birthYear: Int? = nil
    ) -> RuleInput {
        var birthDate = Calendar.current.date(byAdding: .day, value: -birthDaysAgo, to: Date())!
        if let birthYear {
            var components = Calendar.current.dateComponents([.month, .day], from: birthDate)
            components.year = birthYear
            birthDate = Calendar.current.date(from: components)!
        }
        return RuleInput(
            childName: "Rosa",
            birthDate: birthDate,
            birthStateCode: "CA",
            isUSCitizen: citizen,
            hasSSN: hasSSN,
            ssnStatus: hasSSN ? .cardReceived : .requestedAtHospital,
            hasBirthCertificate: hasBirthCertificate,
            residenceStateCode: "CA",
            parentage: parentage,
            secondParentOnRecord: secondParentOnRecord,
            insuranceKind: insurance,
            marketplaceKind: marketplace,
            hasDependentCareFSA: hasFSA,
            wantsPassport: true,
            wants529: true,
            wantsNewbornAccount: true,
            takingParentalLeave: true
        )
    }

    private func daysFromBirth(_ deadline: Deadline, _ input: RuleInput) -> Int? {
        guard let date = deadline.date else { return nil }
        return Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: input.birthDate),
            to: Calendar.current.startOfDay(for: date)
        ).day
    }

    // MARK: - The two windows that actually close

    @Test("A job-based plan gets a hard 30-day window")
    func employerWindowIsThirtyDaysAndHard() {
        let family = input(insurance: .employer)
        let rule = RequirementCatalog.employerInsurance
        #expect(rule.applies(family))
        let deadline = rule.deadline(family)
        #expect(deadline.kind == .hard)
        #expect(daysFromBirth(deadline, family) == 30)
    }

    @Test("The Marketplace gets a hard 60-day window")
    func marketplaceWindowIsSixtyDaysAndHard() {
        let family = input(insurance: .marketplace)
        let rule = RequirementCatalog.marketplaceInsurance
        #expect(rule.applies(family))
        let deadline = rule.deadline(family)
        #expect(deadline.kind == .hard)
        #expect(daysFromBirth(deadline, family) == 60)
    }

    @Test("Exactly one coverage rule fires, for every answer including no answer")
    func onlyOneInsuranceRuleFires() {
        // `.unknown` is in this list on purpose. The intake used to refuse to
        // continue without a coverage answer, which pushed anyone who did not
        // know into guessing, and a guess here turns on the wrong hard deadline.
        for kind in InsuranceKind.allCases {
            let family = input(insurance: kind)
            let firing = [
                RequirementCatalog.employerInsurance,
                RequirementCatalog.marketplaceInsurance,
                RequirementCatalog.medicaidCHIP,
                RequirementCatalog.coverageUnknown
            ].filter { $0.applies(family) }
            #expect(firing.count == 1, "\(kind) produced \(firing.count) coverage tasks")
        }
    }

    @Test("An unanswered coverage question never becomes a hard date")
    func unknownCoverageIsNeverAHardDeadline() {
        let family = input(insurance: .unknown)
        let rule = RequirementCatalog.coverageUnknown
        #expect(rule.applies(family))
        #expect(rule.deadline(family).kind != .hard)
        // Nothing to cite, and it says so rather than borrowing a plausible page.
        #expect(rule.source == nil)
        #expect(!rule.noSourceReason.isEmpty)
    }

    /// The rule's own basis says the number belongs to the employer's plan
    /// document rather than to the IRS. It shipped as a hard 30-day deadline
    /// anyway, which drew a red date and scheduled a notification from a window
    /// the app cannot see, and broke the promise in Settings that only the two
    /// insurance windows ever notify.
    @Test("The dependent care FSA window is a suggestion, not a hard date")
    func fsaWindowIsNotHard() {
        let family = input(hasFSA: true)
        let rule = RequirementCatalog.dependentCareFSA
        #expect(rule.applies(family))
        #expect(rule.deadline(family).kind == .recommended)
    }

    /// The 60 days is the same either way; the site is not. A family on a
    /// state-run exchange sent to HealthCare.gov signs in, is told it does not
    /// serve their state, and loses days inside a window that does not stop.
    @Test("A state marketplace family is routed to their own state, not HealthCare.gov")
    func stateMarketplaceIsRoutedToTheState() {
        let rule = RequirementCatalog.marketplaceInsurance
        let federal = input(insurance: .marketplace, marketplace: .federal)
        let state = input(insurance: .marketplace, marketplace: .state)
        let unsure = input(insurance: .marketplace, marketplace: .unknown)

        #expect(rule.link(federal)?.urlString.contains("special-enrollment-period") == true)
        for family in [state, unsure] {
            #expect(rule.link(family)?.urlString.contains("marketplace-in-your-state") == true)
            // The window itself does not move: it is 60 days for every
            // Marketplace, and softening it would cost the family the window.
            #expect(rule.deadline(family).kind == .hard)
            #expect(daysFromBirth(rule.deadline(family), family) == 60)
        }
    }

    @Test("Medicaid and CHIP carry no deadline at all")
    func medicaidHasNoWindow() {
        let family = input(insurance: .medicaidCHIP)
        let deadline = RequirementCatalog.medicaidCHIP.deadline(family)
        #expect(deadline.date == nil)
        #expect(deadline.kind == .none)
    }

    @Test("Every hard deadline states its basis")
    func hardDeadlinesExplainThemselves() {
        let family = input()
        for rule in RequirementCatalog.all where rule.applies(family) {
            let deadline = rule.deadline(family)
            guard deadline.kind == .hard else { continue }
            #expect(!deadline.basis.isEmpty, "\(rule.key) has a hard deadline and no basis")
        }
    }

    // MARK: - Parentage

    @Test("Married parents are never shown the acknowledgment task")
    func marriedParentsSkipAcknowledgment() {
        #expect(!RequirementCatalog.parentageAcknowledgment.applies(input(parentage: .married)))
        #expect(!RequirementCatalog.parentageAcknowledgment.applies(input(parentage: .singleParent)))
    }

    @Test("Unmarried parents not yet on the record are shown it")
    func unmarriedParentsSeeAcknowledgment() {
        let family = input(parentage: .unmarriedBothParents, secondParentOnRecord: false)
        #expect(RequirementCatalog.parentageAcknowledgment.applies(family))
        // The copy has to say it is state law and has to refuse to file.
        let detail = RequirementCatalog.parentageAcknowledgment.detail(family)
        #expect(detail.contains("state"))
        #expect(detail.lowercased().contains("will not prepare"))
    }

    @Test("Once both parents are on the record it drops off")
    func acknowledgmentRetiresWhenDone() {
        let family = input(parentage: .unmarriedBothParents, secondParentOnRecord: true)
        #expect(!RequirementCatalog.parentageAcknowledgment.applies(family))
    }

    // MARK: - The $1,000 newborn account

    @Test("The newborn account applies only to eligible citizen children in the pilot years")
    func trumpAccountEligibility() {
        #expect(RequirementCatalog.newbornAccount.applies(input(birthYear: 2026)))
        #expect(!RequirementCatalog.newbornAccount.applies(input(citizen: false, birthYear: 2026)))
        #expect(!RequirementCatalog.newbornAccount.applies(input(birthYear: 2024)))
        #expect(!RequirementCatalog.newbornAccount.applies(input(birthYear: 2029)))
    }

    @Test("The newborn account holds no date of its own")
    func trumpAccountRefusesToGuessADate() {
        // A wrong date on a one-time $1,000 election is worse than no date, so
        // the rule deliberately carries none and points at the instructions.
        let deadline = RequirementCatalog.newbornAccount.deadline(input(birthYear: 2026))
        #expect(deadline.date == nil)
        #expect(deadline.basis.contains("4547"))
    }

    @Test("Without an SSN the newborn account task says it is blocked")
    func trumpAccountExplainsTheSSNDependency() {
        let blocked = RequirementCatalog.newbornAccount.detail(input(hasSSN: false, birthYear: 2026))
        let ready = RequirementCatalog.newbornAccount.detail(input(hasSSN: true, birthYear: 2026))
        #expect(blocked.contains("waiting on the SSN"))
        #expect(!ready.contains("waiting on the SSN"))
    }

    // MARK: - Document-driven tasks

    @Test("The birth certificate task retires once a copy is in hand")
    func birthCertificateRetires() {
        #expect(RequirementCatalog.birthCertificate.applies(input(hasBirthCertificate: false)))
        #expect(!RequirementCatalog.birthCertificate.applies(input(hasBirthCertificate: true)))
    }

    @Test("The name check appears only once there is a certificate to check")
    func nameCheckWaitsForTheCertificate() {
        #expect(!RequirementCatalog.birthRecordNameCheck.applies(input(hasBirthCertificate: false)))
        #expect(RequirementCatalog.birthRecordNameCheck.applies(input(hasBirthCertificate: true)))
    }

    @Test("The SSN task retires once the card arrives")
    func ssnRetires() {
        #expect(RequirementCatalog.ssnCard.applies(input(hasSSN: false)))
        #expect(!RequirementCatalog.ssnCard.applies(input(hasSSN: true)))
    }

    @Test("The passport task says what is blocking it")
    func passportExplainsTheBlock() {
        let blocked = RequirementCatalog.passport.detail(input(hasBirthCertificate: false))
        #expect(blocked.contains("Blocked"))
    }

    // MARK: - Structural invariants

    @Test("Every rule has a unique key")
    func keysAreUnique() {
        let keys = RequirementCatalog.all.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("Every rule either cites a source or says why it cannot")
    func everyRuleAccountsForItsSource() {
        // Source *correctness* lives in SourceIntegrityTests. This is only the
        // structural half: no rule may be silent about where it came from.
        for rule in RequirementCatalog.all {
            switch rule.sourcing {
            case .cite:
                #expect(rule.source != nil, "\(rule.key) cites a source key the manifest does not hold")
            case .none(let reason):
                #expect(!reason.isEmpty, "\(rule.key) cites nothing and does not say why")
            }
        }
    }

    @Test("Every rule has a short title that fits a navigation bar")
    func shortTitlesAreShort() {
        for rule in RequirementCatalog.all {
            #expect(!rule.shortTitle.isEmpty, "\(rule.key) has no short title")
            #expect(rule.shortTitle.count <= 22, "\(rule.key) short title will truncate: \(rule.shortTitle)")
        }
    }

    @Test("Every applicable rule says why it applies to this family")
    func everyRuleJustifiesItself() {
        let family = input()
        for rule in RequirementCatalog.all where rule.applies(family) {
            #expect(rule.detail(family).count > 40, "\(rule.key) has no real explanation")
        }
    }

    @Test("Nothing in the catalog uses an em dash")
    func copyAvoidsEmDashes() {
        let family = input()
        for rule in RequirementCatalog.all {
            let copy = [rule.title, rule.detail(family), rule.deadline(family).basis]
                + rule.documents.flatMap { [$0.title, $0.detail] }
            for text in copy {
                #expect(!text.contains("\u{2014}"), "\(rule.key) contains an em dash")
            }
        }
    }
}
