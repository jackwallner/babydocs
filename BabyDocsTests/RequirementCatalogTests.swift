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
        parentage: ParentageSituation = .married,
        secondParentOnRecord: Bool = true,
        hasSSN: Bool = false,
        hasBirthCertificate: Bool = false,
        citizen: Bool = true,
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
            hasDependentCareFSA: false,
            wantsPassport: true,
            wants529: true,
            wantsTrumpAccount: true,
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

    @Test("The two insurance rules are mutually exclusive")
    func onlyOneInsuranceRuleFires() {
        for kind in [InsuranceKind.employer, .marketplace, .medicaidCHIP, .none] {
            let family = input(insurance: kind)
            let firing = [
                RequirementCatalog.employerInsurance,
                RequirementCatalog.marketplaceInsurance,
                RequirementCatalog.medicaidCHIP
            ].filter { $0.applies(family) }
            #expect(firing.count == 1, "\(kind) produced \(firing.count) insurance tasks")
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

    // MARK: - Trump Accounts

    @Test("Trump Account applies only to eligible citizen children in the pilot years")
    func trumpAccountEligibility() {
        #expect(RequirementCatalog.trumpAccount.applies(input(birthYear: 2026)))
        #expect(!RequirementCatalog.trumpAccount.applies(input(citizen: false, birthYear: 2026)))
        #expect(!RequirementCatalog.trumpAccount.applies(input(birthYear: 2024)))
        #expect(!RequirementCatalog.trumpAccount.applies(input(birthYear: 2029)))
    }

    @Test("Trump Account holds no date of its own")
    func trumpAccountRefusesToGuessADate() {
        // A wrong date on a one-time $1,000 election is worse than no date, so
        // the rule deliberately carries none and points at the instructions.
        let deadline = RequirementCatalog.trumpAccount.deadline(input(birthYear: 2026))
        #expect(deadline.date == nil)
        #expect(deadline.basis.contains("4547"))
    }

    @Test("Without an SSN the Trump Account task says it is blocked")
    func trumpAccountExplainsTheSSNDependency() {
        let blocked = RequirementCatalog.trumpAccount.detail(input(hasSSN: false, birthYear: 2026))
        let ready = RequirementCatalog.trumpAccount.detail(input(hasSSN: true, birthYear: 2026))
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

    @Test("Every rule cites a source")
    func everyRuleCitesASource() {
        for rule in RequirementCatalog.all {
            #expect(!rule.source.urlString.isEmpty, "\(rule.key) has no source")
            #expect(rule.source.urlString.hasPrefix("https://"), "\(rule.key) source is not https")
        }
    }

    @Test("Every official link is a government address")
    func officialLinksAreGovernmentOnly() {
        // The promise is "we take you to the correct official place". An
        // aggregator or an affiliate link would break it silently.
        let family = input()
        for rule in RequirementCatalog.all {
            guard let link = rule.link(family), let host = URL(string: link.urlString)?.host else { continue }
            #expect(
                host.hasSuffix(".gov") || host.hasSuffix(".gov."),
                "\(rule.key) links to \(host), which is not a .gov host"
            )
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
