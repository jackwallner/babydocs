import Foundation
import SwiftData
import Testing

@testable import BabyDocs

/// The two promises this build makes that a reader cannot verify by reading one
/// file: that nothing from the document vault can reach an export or a share
/// sheet, and that a shared plan link carries the answers and nothing else.
///
/// Both are the kind of guarantee that decays quietly. Somebody adds an
/// `attachments` line to the summary because it seemed useful, or widens
/// `PlanSeed` to "just include what's done so they can see progress", and the
/// App Store page becomes untrue with no test failing and no reviewer noticing.
@MainActor
struct VaultAndSharingTests {

    private func makeContext() -> ModelContext {
        ModelContext(BabyModelStore.makeInMemoryContainer())
    }

    private func makeFamily(in context: ModelContext) -> (Child, FamilyProfile) {
        let profile = FamilyProfileStore.current(in: context)
        profile.residenceStateCode = "CA"
        profile.parentage = .unmarriedBothParents
        profile.secondParentOnRecord = false
        profile.insuranceKind = .employer
        profile.hasDependentCareFSA = true
        profile.wantsNewbornAccount = true
        profile.wantsPassport = true
        profile.wants529 = true
        profile.parentalLeaveTakers = .bothParents

        let child = Child(name: "Rosa", birthDate: Date(), birthStateCode: "CA")
        child.birthCounty = "Alameda County"
        context.insert(child)
        RequirementEngine.reconcile(child: child, profile: profile, in: context)
        return (child, profile)
    }

    // MARK: - The vault cannot leak

    @Test("No export mentions a vault filename, whatever is in the vault")
    func exportsCannotReachAVaultImage() {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)

        let document = VaultDocument(kind: .socialSecurityCard, child: child)
        document.pageFileNames = ["SENTINEL-0001.jpg", "SENTINEL-0002.jpg"]
        context.insert(document)

        let summary = PlanExporter.summary(for: child, profile: profile)
        let packet = PlanExporter.employerPacket(for: child, profile: profile)

        for name in document.pageFileNames {
            #expect(!summary.contains(name), "The one-pager reached a vault filename")
            #expect(!packet.contains(name), "The employer packet reached a vault filename")
        }
        #expect(!summary.contains(".jpg"))
        #expect(!packet.contains(".jpg"))
    }

    /// `VaultStore` hands back images, never locations. This is the structural
    /// half of the guarantee above: with no `URL` on the type, a future share
    /// sheet has nothing to be handed, so the leak cannot be written by
    /// accident, only on purpose.
    @Test("VaultStore exposes no API that returns a file location")
    func vaultStoreNeverVendsAPath() {
        let mirror = Mirror(reflecting: VaultStore.shared)
        let leaky = mirror.children.compactMap(\.label).filter {
            $0.lowercased().contains("url") || $0.lowercased().contains("path")
        }
        #expect(leaky.isEmpty, "VaultStore gained something that looks like a location: \(leaky)")
    }

    @Test("The employer packet states the SSN status and never a number")
    func employerPacketKeepsTheNumberOut() {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        child.ssnStatus = .requestedAtHospital

        let packet = PlanExporter.employerPacket(for: child, profile: profile)
        #expect(packet.contains("SOCIAL SECURITY NUMBER"))
        #expect(packet.contains("Applied for"))
        // A packet is written to be emailed to a third party and forwarded
        // inside a company, which makes it the worst possible place for one.
        // Matched by shape rather than by a sentinel, because the failure this
        // guards against is a future field that prints a real number.
        let ssnShaped = try? NSRegularExpression(pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b")
        let range = NSRange(packet.startIndex..., in: packet)
        #expect(
            ssnShaped?.firstMatch(in: packet, range: range) == nil,
            "The employer packet printed something shaped like a Social Security number"
        )
    }

    @Test("The employer packet refuses non-employer coverage")
    func employerPacketDoesNotInventAJobPlan() {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        profile.insuranceKind = .marketplace

        let packet = PlanExporter.employerPacket(for: child, profile: profile)

        #expect(packet.contains("NOT APPLICABLE"))
        #expect(!packet.contains("Add this dependent to my medical coverage"))
    }

    // MARK: - The link carries answers and nothing else

    @Test("A seed round-trips through its own link")
    func seedSurvivesTheLink() throws {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        profile.employerPlanName = "Acme PPO"
        profile.benefitsContactNote = "Dana in HR"

        let seed = PlanSeed.make(child: child, profile: profile)
        let url = try #require(seed.shareURL())
        let decoded = try #require(PlanSeed.decode(from: url))

        #expect(decoded.name == "Rosa")
        #expect(decoded.childID == child.id)
        #expect(decoded.birthStateCode == "CA")
        #expect(decoded.birthCounty == "Alameda County")
        #expect(decoded.residenceStateCode == "CA")
        #expect(decoded.insuranceKind == InsuranceKind.employer.rawValue)
        #expect(decoded.employerPlanName == "Acme PPO")
        #expect(decoded.benefitsContactNote == "Dana in HR")
        #expect(decoded.wantsNewbornAccount)
        // Whole seconds only: the payload is ISO8601, and a birth date that
        // arrives a fraction off would push every derived deadline by a day at
        // the wrong end of a timezone.
        #expect(abs(decoded.birthDate.timeIntervalSince(child.birthDate)) < 1)
    }

    @Test("A non-employer seed does not carry employer-only details")
    func seedOmitsEmployerDetailsWhenCoverageChanges() throws {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        profile.insuranceKind = .marketplace
        profile.employerPlanName = "Stale employer plan"
        profile.benefitsContactNote = "Stale HR contact"

        let seed = PlanSeed.make(child: child, profile: profile)
        #expect(seed.employerPlanName == nil)
        #expect(seed.benefitsContactNote == nil)

        let payload = try #require(seed.encoded())
        let decoded = try #require(PlanSeed.decode(payload: payload))
        #expect(decoded.employerPlanName == nil)
        #expect(decoded.benefitsContactNote == nil)
    }

    @Test("Shared free text redacts a Social Security number")
    func sharedFreeTextRedactsSensitiveShape() {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        profile.employerPlanName = "Acme 123-45-6789 PPO"
        profile.benefitsContactNote = "Call 555 12 3456"

        let seed = PlanSeed.make(child: child, profile: profile)
        #expect(seed.employerPlanName?.contains("123-45-6789") == false)
        #expect(seed.benefitsContactNote?.contains("555 12 3456") == false)
    }

    @Test("Exports redact a Social Security number in an assignee name")
    func exportsRedactSensitiveFreeText() throws {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        let task = try #require(child.liveTasks.first)
        task.completedAt = Date()
        task.completedByName = "123-45-6789"

        let summary = PlanExporter.summary(for: child, profile: profile)
        #expect(!summary.contains("123-45-6789"))
        #expect(summary.contains("redacted Social Security number"))
    }

    @Test("A shared birth date stays the same across US time zones")
    func birthDateIsDateOnly() throws {
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let sourceDate = sourceCalendar.date(from: DateComponents(year: 2026, month: 8, day: 22))!
        let child = Child(name: "Rosa", birthDate: sourceDate, birthStateCode: "NY")
        let profileContext = makeContext()
        let profile = FamilyProfileStore.current(in: profileContext)
        profile.residenceStateCode = "NY"
        var seed = PlanSeed.make(child: child, profile: profile)
        seed.birthDate = sourceDate

        let payload = try #require(seed.encoded())
        let decoded = try #require(PlanSeed.decode(payload: payload))
        #expect(DateOnly.dayKey(decoded.birthDate) == "2026-08-22")
        #expect(DateOnly.sameDay(decoded.birthDate, DateOnly.date(from: "2026-08-22")!))
    }

    @Test("Both link shapes carry the same payload")
    func customSchemeAndWebLinkAgree() throws {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        let seed = PlanSeed.make(child: child, profile: profile)
        let payload = try #require(seed.encoded())

        let web = try #require(URL(string: "\(PlanSeed.webBase)#\(payload)"))
        let scheme = try #require(URL(string: "babydocs://plan?d=\(payload)"))

        #expect(PlanSeed.decode(from: web) == PlanSeed.decode(from: scheme))
    }

    /// The privacy claim on `docs/plan.html` depends entirely on this. A
    /// fragment is never sent to a server; a query string is sent to, and logged
    /// by, every host in the path. Moving the payload would silently turn a page
    /// that receives nothing into one that receives a birth date.
    @Test("The web link keeps its payload in the fragment, never the query")
    func payloadNeverEntersTheQueryString() throws {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        let url = try #require(PlanSeed.make(child: child, profile: profile).shareURL())
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.query == nil, "The shared link put family data in the query string")
        #expect(components.fragment?.isEmpty == false)
        #expect(components.path.hasSuffix("plan.html"), "The link must point at the published page")
    }

    @Test("A seed carries no work, no receipts and no documents")
    func seedCarriesAnswersOnly() throws {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)

        // Do some work worth not leaking.
        let task = try #require(child.liveTasks.first)
        task.completedAt = Date()
        task.assigneeName = "Sam"
        task.parentNotes = "CONFIDENTIAL-NOTE"
        let receipt = Receipt(kind: .confirmationNumber, value: "SECRET-4471")
        receipt.task = task
        context.insert(receipt)
        let document = VaultDocument(kind: .birthCertificate, child: child)
        document.pageFileNames = ["SENTINEL.jpg"]
        context.insert(document)

        let payload = try #require(PlanSeed.make(child: child, profile: profile).encoded())
        let json = String(decoding: try #require(Data(base64URLEncoded: payload)), as: UTF8.self)

        for secret in ["CONFIDENTIAL-NOTE", "SECRET-4471", "SENTINEL.jpg", "Sam"] {
            #expect(!json.contains(secret), "A shared link carried \(secret)")
        }
    }

    @Test("A mangled link is refused rather than half-read")
    func brokenLinksDecodeToNothing() {
        #expect(PlanSeed.decode(payload: "") == nil)
        #expect(PlanSeed.decode(payload: "not-base64-at-all!!") == nil)
        #expect(PlanSeed.decode(from: URL(string: "https://example.com/plan.html")!) == nil)
        // A truncated payload is the realistic case: message apps cut long
        // links, and a half-decoded plan would be worse than none.
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        let full = PlanSeed.make(child: child, profile: profile).encoded() ?? ""
        #expect(PlanSeed.decode(payload: String(full.prefix(full.count / 2))) == nil)
    }

    @Test("A semantically invalid seed is refused")
    func invalidSeedIsRejected() throws {
        let context = makeContext()
        let (child, profile) = makeFamily(in: context)
        var seed = PlanSeed.make(child: child, profile: profile)

        seed.version = 0
        #expect(PlanSeed.decode(payload: try #require(seed.encoded())) == nil)

        seed = PlanSeed.make(child: child, profile: profile)
        seed.birthStateCode = "XX"
        #expect(PlanSeed.decode(payload: try #require(seed.encoded())) == nil)

        seed = PlanSeed.make(child: child, profile: profile)
        seed.insuranceKind = "not-an-insurance-kind"
        #expect(PlanSeed.decode(payload: try #require(seed.encoded())) == nil)
    }

    // MARK: - Follow-up tracking

    @Test("Only a task that was sent and is overdue back counts as late")
    func lateNeedsBothDates() {
        let task = RequirementTask(title: "Order certified copies")
        let past = Calendar.current.date(byAdding: .day, value: -3, to: Date())

        #expect(!task.isLate(), "Nothing sent cannot be late")

        task.expectedByAt = past
        #expect(!task.isLate(), "An expected date with nothing sent is not late")

        task.submittedAt = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        #expect(task.isLate())

        task.completedAt = Date()
        #expect(!task.isLate(), "Something that arrived is not late")
    }

    @Test("An expected date is not late until the next calendar day")
    func expectedTodayIsNotLateBeforeTomorrow() {
        let task = RequirementTask(title: "Order certified copies")
        let now = Date()
        task.submittedAt = Calendar.current.date(byAdding: .day, value: -2, to: now)
        task.expectedByAt = DateOnly.canonical(now)

        #expect(!task.isLate(from: now), "An item expected today is not late today")

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        #expect(task.isLate(from: tomorrow), "An item expected yesterday is late tomorrow")
    }

    @Test("A local day does not roll over at UTC midnight")
    func localDayKeyUsesTheDeviceCalendar() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let justAfterUTCMidnight = utc.date(
            from: DateComponents(year: 2026, month: 8, day: 23, hour: 1)
        )!
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        #expect(DateOnly.localDayKey(justAfterUTCMidnight, calendar: pacific) == "2026-08-22")
    }

    @Test("Only rules that involve waiting on an office offer follow-up tracking")
    func followUpIsOfferedWhereWaitingHappens() {
        let posted = Set(RequirementCatalog.all.filter(\.isPostedAway).map(\.key))
        #expect(posted.contains("ssn_card"))
        #expect(posted.contains("birth_certificate"))
        // A W-4 is handed to a payroll system and takes effect; there is nothing
        // to chase, and offering to chase it would teach people to ignore the
        // control where it matters.
        #expect(!posted.contains("w4_update"))
        #expect(!posted.contains("tax_dependent"))
    }
}
