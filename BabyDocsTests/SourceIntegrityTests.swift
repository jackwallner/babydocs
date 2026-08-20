import Foundation
import Testing

@testable import BabyDocs

/// The tests that would have caught the citations this release fixed.
///
/// A `.gov` host check passes happily on a childcare task that cites the federal
/// birth-certificate page, and on a dependent-care FSA deadline that cites the
/// IRS topic about college savings. Both of those shipped. The check that
/// catches them is not about the address at all: it is that a source declares
/// what it is *about*, and a rule declares what it *needs*.
struct SourceIntegrityTests {

    private func input() -> RuleInput {
        RuleInput(
            childName: "Rosa",
            birthDate: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            birthStateCode: "CA",
            residenceStateCode: "CA",
            parentage: .unmarriedBothParents,
            insuranceKind: .employer,
            hasDependentCareFSA: true,
            wantsPassport: true,
            wants529: true,
            wantsNewbornAccount: true,
            parentalLeaveTakers: .bothParents
        )
    }

    // MARK: - The manifest itself

    @Test("Every manifest entry is a unique, https, government address")
    func manifestEntriesAreWellFormed() {
        var seenKeys = Set<String>()
        for entry in SourceManifest.all {
            #expect(seenKeys.insert(entry.key).inserted, "duplicate source key \(entry.key)")
            #expect(entry.urlString.hasPrefix("https://"), "\(entry.key) is not https")
            guard let host = URL(string: entry.urlString)?.host else {
                Issue.record("\(entry.key) has an unparseable URL")
                continue
            }
            #expect(host.hasSuffix(".gov"), "\(entry.key) points at \(host), which is not a .gov host")
            #expect(!entry.subjects.isEmpty, "\(entry.key) declares no subject")
            #expect(!entry.title.isEmpty && !entry.agency.isEmpty, "\(entry.key) is unattributed")
        }
    }

    @Test("No source is dated in the future")
    func reviewDatesArePlausible() {
        for entry in SourceManifest.all {
            #expect(entry.reviewedOn <= Date(), "\(entry.key) claims a review date in the future")
        }
    }

    @Test("A federal fallback or an unread page says what it does not cover")
    func weakerSourcesDeclareTheirLimits() {
        for entry in SourceManifest.all where entry.status != .verified {
            #expect(
                !entry.limitations.isEmpty,
                "\(entry.key) is not fully verified and does not say what it leaves out"
            )
        }
    }

    // MARK: - Rule to source

    @Test("Every cited rule cites a source that is actually about its subject")
    func citationsMatchTheirSubject() {
        for rule in RequirementCatalog.all {
            guard case .cite(let key, let subject) = rule.sourcing else { continue }
            guard let entry = SourceManifest.entry(key) else {
                Issue.record("\(rule.key) cites unknown source \(key)")
                continue
            }
            #expect(
                entry.subjects.contains(subject),
                "\(rule.key) needs a \(subject) source and cites \(entry.key), which is about \(entry.subjects.map(\.rawValue).sorted().joined(separator: ", "))"
            )
        }
    }

    /// The gap that let a medically adjacent rule ship on a page nobody had
    /// read. The footnote said so honestly, and honest is not the same as ready:
    /// "nobody has read this page end to end yet" under an active task is a
    /// confession, not a citation.
    @Test("No rule in the catalog cites a page nobody has read")
    func activeRulesDoNotCiteUnreadPages() {
        for rule in RequirementCatalog.all {
            #expect(
                rule.source?.status != .awaitingReview,
                "\(rule.key) cites \(rule.source?.key ?? "?"), which is still awaiting review"
            )
        }
    }

    @Test("An uncited rule says why, and links nothing official it cannot back")
    func uncitedRulesExplainThemselves() {
        for rule in RequirementCatalog.all {
            guard case .none(let reason) = rule.sourcing else { continue }
            #expect(reason.count > 40, "\(rule.key) cites nothing and does not say why")
            #expect(rule.source == nil)
        }
    }

    @Test("The old wrong citations are gone")
    func knownBadCitationsCannotComeBack() {
        // Every one of these was live: a birth-certificate page standing in for
        // newborn screening, wills, health records and childcare, and a college
        // savings topic standing in for the dependent care FSA.
        let birthCertificate = "https://www.usa.gov/birth-certificate"
        let qualifiedTuition = "https://www.irs.gov/taxtopics/tc313"
        let borrowers = ["newborn_screening_result", "beneficiary_update", "guardian_nomination",
                         "pediatric_portal", "childcare_waitlist"]

        for key in borrowers {
            guard let rule = RequirementCatalog.rule(key: key) else {
                Issue.record("no rule \(key)")
                continue
            }
            #expect(rule.source?.urlString != birthCertificate,
                    "\(key) is citing the birth certificate page again")
        }
        #expect(RequirementCatalog.dependentCareFSA.source?.urlString != qualifiedTuition,
                "the dependent care FSA is citing the college savings topic again")
        #expect(RequirementCatalog.plan529.source?.urlString == qualifiedTuition,
                "the 529 rule is the one that legitimately cites it")
    }

    @Test("Only the birth certificate rules may cite the federal ordering page")
    func theBirthCertificatePageIsNotAGeneralPurposeLink() {
        for rule in RequirementCatalog.all {
            guard let entry = rule.source, entry.key == "usagov_birth_certificate" else { continue }
            #expect(rule.sourceSubject == .birthCertificateOrder, "\(rule.key) borrowed the birth certificate page")
        }
    }

    // MARK: - Official links

    @Test("Every official link is a government address")
    func officialLinksAreGovernmentOnly() {
        let family = input()
        for rule in RequirementCatalog.all {
            guard let link = rule.link(family), let host = URL(string: link.urlString)?.host else { continue }
            #expect(host.hasSuffix(".gov"), "\(rule.key) links to \(host), which is not a .gov host")
            #expect(!link.label.isEmpty, "\(rule.key) has an unlabelled link")
        }
    }

    // MARK: - The number this app refuses to hold

    @Test("Nothing in the catalog asks a parent to enter a Social Security number")
    func noCopyInvitesTheNumber() {
        // The newborn account document used to be titled "The baby's Social
        // Security number", which reads to a tired parent as a field to fill in.
        // Anywhere the number is mentioned at all, the warning has to be beside
        // it, verbatim.
        let family = input()
        let forbidden = ["enter the social security number", "type the social security number",
                         "your social security number:", "ssn:"]

        for rule in RequirementCatalog.all {
            var copy = [rule.title, rule.detail(family), rule.deadline(family).basis]
            copy += rule.documents.flatMap { [$0.title, $0.detail] }

            for text in copy {
                let lowered = text.lowercased()
                for phrase in forbidden {
                    #expect(!lowered.contains(phrase), "\(rule.key) asks for the number: \(text)")
                }
            }

            for document in rule.documents where document.title.lowercased().contains("social security") {
                #expect(
                    document.detail.contains(RequirementCatalog.ssnWarning),
                    "\(rule.key)/\(document.key) mentions the number without the warning beside it"
                )
            }
        }
    }

    @Test("The export prints the status of the number and never a value")
    func exportKeepsTheNumberOut() {
        // Belt and braces against the day someone adds an `ssn` field to Child.
        let mirror = Mirror(reflecting: Child())
        let numberLike = mirror.children.compactMap(\.label).filter {
            $0.lowercased().contains("ssnnumber") || $0.lowercased() == "ssn"
        }
        #expect(numberLike.isEmpty, "Child gained a field that looks like it holds the number: \(numberLike)")
    }
}
