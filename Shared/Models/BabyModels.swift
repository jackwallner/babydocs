import Foundation
import SwiftData

// MARK: - Enumerations

/// A US state or territory, stored as its two-letter postal code.
///
/// Modelled as a value rather than a free-text string because almost every rule
/// in this app forks on it: where the birth was registered decides who issues
/// the birth certificate, and where the family lives decides the Medicaid/CHIP
/// agency and the paid-leave programme.
struct USState: Hashable, Sendable, Codable, Identifiable {
    var code: String
    var name: String

    var id: String { code }

    static let all: [USState] = [
        USState(code: "AL", name: "Alabama"), USState(code: "AK", name: "Alaska"),
        USState(code: "AZ", name: "Arizona"), USState(code: "AR", name: "Arkansas"),
        USState(code: "CA", name: "California"), USState(code: "CO", name: "Colorado"),
        USState(code: "CT", name: "Connecticut"), USState(code: "DE", name: "Delaware"),
        USState(code: "DC", name: "District of Columbia"), USState(code: "FL", name: "Florida"),
        USState(code: "GA", name: "Georgia"), USState(code: "HI", name: "Hawaii"),
        USState(code: "ID", name: "Idaho"), USState(code: "IL", name: "Illinois"),
        USState(code: "IN", name: "Indiana"), USState(code: "IA", name: "Iowa"),
        USState(code: "KS", name: "Kansas"), USState(code: "KY", name: "Kentucky"),
        USState(code: "LA", name: "Louisiana"), USState(code: "ME", name: "Maine"),
        USState(code: "MD", name: "Maryland"), USState(code: "MA", name: "Massachusetts"),
        USState(code: "MI", name: "Michigan"), USState(code: "MN", name: "Minnesota"),
        USState(code: "MS", name: "Mississippi"), USState(code: "MO", name: "Missouri"),
        USState(code: "MT", name: "Montana"), USState(code: "NE", name: "Nebraska"),
        USState(code: "NV", name: "Nevada"), USState(code: "NH", name: "New Hampshire"),
        USState(code: "NJ", name: "New Jersey"), USState(code: "NM", name: "New Mexico"),
        USState(code: "NY", name: "New York"), USState(code: "NC", name: "North Carolina"),
        USState(code: "ND", name: "North Dakota"), USState(code: "OH", name: "Ohio"),
        USState(code: "OK", name: "Oklahoma"), USState(code: "OR", name: "Oregon"),
        USState(code: "PA", name: "Pennsylvania"), USState(code: "RI", name: "Rhode Island"),
        USState(code: "SC", name: "South Carolina"), USState(code: "SD", name: "South Dakota"),
        USState(code: "TN", name: "Tennessee"), USState(code: "TX", name: "Texas"),
        USState(code: "UT", name: "Utah"), USState(code: "VT", name: "Vermont"),
        USState(code: "VA", name: "Virginia"), USState(code: "WA", name: "Washington"),
        USState(code: "WV", name: "West Virginia"), USState(code: "WI", name: "Wisconsin"),
        USState(code: "WY", name: "Wyoming"),
        // The five territories. They were missing, and the type's own comment
        // called it "a state or territory", so a family in Guam had no honest
        // answer to the first question in the app and the only way forward was
        // to pick a state they do not live in. That is worse than a federal
        // fallback: every rule then routes to the wrong jurisdiction, silently.
        //
        // Nothing here is verified detail and nothing pretends to be.
        // `StateVitalRecords` has no entry for any of them, so the birth
        // certificate task links to the federal directory, which carries a
        // picker that includes territories, and the task says the page is
        // federal and the jurisdiction has the last word.
        USState(code: "PR", name: "Puerto Rico"),
        USState(code: "VI", name: "US Virgin Islands"),
        USState(code: "GU", name: "Guam"),
        USState(code: "MP", name: "Northern Mariana Islands"),
        USState(code: "AS", name: "American Samoa")
    ]

    static func named(_ code: String) -> USState? {
        all.first { $0.code.caseInsensitiveCompare(code) == .orderedSame }
    }

    static func displayName(for code: String) -> String {
        named(code)?.name ?? code
    }
}

/// How far along the Social Security number is.
///
/// This is the single most load-bearing piece of state in the app. A missing SSN
/// blocks the tax return, the $1,000 newborn account election and most bank
/// accounts, and the commonest way it goes wrong is quiet: the hospital form was
/// never submitted and nobody finds out until April.
enum SSNStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    /// The parent believes the hospital birth-registration form included the
    /// SSN request, but nothing has arrived yet.
    case requestedAtHospital = "requested_at_hospital"
    /// Applied directly with the SSA (Form SS-5) rather than at the hospital.
    case appliedDirectly = "applied_directly"
    case cardReceived = "card_received"

    var label: String {
        switch self {
        case .unknown: return "Not sure"
        case .requestedAtHospital: return "Requested at the hospital"
        case .appliedDirectly: return "Applied at an SSA office"
        case .cardReceived: return "Card received"
        }
    }
}

/// Where the family's health coverage comes from, which decides the special
/// enrollment deadline and therefore the single hardest date in the app.
enum InsuranceKind: String, Codable, CaseIterable, Sendable {
    case unknown
    /// A plan through an employer. Job-based plans must offer at least a 30-day
    /// special enrollment period after a birth.
    case employer
    /// HealthCare.gov or a state marketplace. Generally 60 days.
    case marketplace
    /// Medicaid or CHIP, which accept applications at any time.
    case medicaidCHIP = "medicaid_chip"
    case none

    var label: String {
        switch self {
        case .unknown: return "Not sure yet"
        case .employer: return "Through a job"
        case .marketplace: return "Marketplace (HealthCare.gov or a state site)"
        case .medicaidCHIP: return "Medicaid or CHIP"
        case .none: return "No coverage right now"
        }
    }
}

/// Which Marketplace a family actually uses, which decides where they have to
/// go rather than how long they have.
///
/// Roughly a third of the country does not use HealthCare.gov: their state runs
/// its own exchange, on its own site, with its own account and its own
/// documents. Sending one of those families to HealthCare.gov inside a closing
/// window is the single most expensive wrong link this app could hand out, and a
/// caveat in small print under a red date does not undo it.
///
/// Deliberately asked rather than derived from the residence state. A generated
/// list of which states run their own exchange is exactly the "specific but
/// guessed" answer `StateVitalRecords` exists to refuse: the list moves, and
/// being wrong about one state costs that family the window. The family knows
/// which site they log in to, so the app asks.
enum MarketplaceKind: String, Codable, CaseIterable, Sendable {
    case unknown
    /// HealthCare.gov, which serves most states.
    case federal
    /// A state-run exchange with its own site.
    case state

    var label: String {
        switch self {
        case .unknown: return "Not sure which"
        case .federal: return "HealthCare.gov"
        case .state: return "My state runs its own site"
        }
    }
}

/// Which parents are taking leave after the birth.
///
/// A boolean was the wrong shape and it hid a real fact: leave is not a
/// household arrangement, it is a claim, and each parent files their own with
/// their own employer, on their own state's programme, inside their own window.
/// One task for "someone is taking parental leave" left the second parent's
/// claim as a thing the app had silently decided did not exist.
enum ParentalLeaveTakers: String, Codable, CaseIterable, Sendable {
    case nobody
    case oneParent = "one_parent"
    case bothParents = "both_parents"

    var label: String {
        switch self {
        case .nobody: return "Nobody is taking leave"
        case .oneParent: return "One parent"
        case .bothParents: return "Both parents"
        }
    }
}

/// The legal relationship between the parents at the time of birth. In most
/// states marriage creates a presumption of parentage and an unmarried second
/// parent has to establish it deliberately, which is why this question exists.
enum ParentageSituation: String, Codable, CaseIterable, Sendable {
    case unknown
    case married
    case unmarriedBothParents = "unmarried_both"
    case singleParent = "single_parent"

    var label: String {
        switch self {
        case .unknown: return "Prefer not to say"
        case .married: return "Married to the other parent"
        case .unmarriedBothParents: return "Not married, both parents involved"
        case .singleParent: return "Single parent"
        }
    }
}

/// How hard the date is. Drives colour, sort order and whether a reminder is
/// scheduled, and is never softened in copy: a 30-day insurance window that is
/// presented as a suggestion is worse than no date at all.
enum DeadlineKind: String, Codable, Sendable {
    /// Missing it forecloses the option until the next open window.
    case hard
    /// Nothing is lost immediately, but delay costs money or compounds.
    case recommended
    /// A useful ordering, not a date anyone is held to.
    case none
}

enum RequirementCategory: String, Codable, CaseIterable, Sendable {
    case identity
    case insurance
    case parentage
    case money
    case travel
    case work
    case household

    var label: String {
        switch self {
        case .identity: return "Identity"
        case .insurance: return "Insurance"
        case .parentage: return "Parentage"
        case .money: return "Money"
        case .travel: return "Travel"
        case .work: return "Work & leave"
        case .household: return "Household"
        }
    }

    var symbol: String {
        switch self {
        case .identity: return "person.text.rectangle.fill"
        case .insurance: return "cross.case.fill"
        case .parentage: return "figure.2.and.child.holdinghands"
        case .money: return "dollarsign.circle.fill"
        case .travel: return "airplane"
        case .work: return "briefcase.fill"
        case .household: return "house.fill"
        }
    }

    /// Ordered to match `AppTheme.categoryColors`.
    var colorIndex: Int {
        switch self {
        case .identity: return 0
        case .insurance: return 1
        case .parentage: return 2
        case .money: return 3
        case .travel: return 4
        case .work: return 5
        case .household: return 6
        }
    }
}

// MARK: - Child

/// One baby. Everything the rules engine needs about the child itself, and
/// nothing it does not: this app is a paperwork tracker, so there is no weight,
/// no feed log and no growth chart to drift into.
@Model
final class Child {
    var id: UUID = UUID()
    var name: String = ""
    var birthDate: Date = Date()
    /// Where the birth was registered, which is not always where the family
    /// lives, and is what decides who issues the birth certificate.
    var birthStateCode: String = ""
    var birthCounty: String = ""
    /// Eligibility for the $1,000 federal newborn account turns on this.
    /// Defaulted true because the overwhelming majority of births this app sees
    /// are to US citizens, and a wrong default here only ever shows one extra
    /// task.
    var isUSCitizen: Bool = true
    var ssnStatusRaw: String = SSNStatus.unknown.rawValue
    /// When the SSN card actually arrived, so the follow-up reminder can be
    /// retired rather than nagging forever.
    var ssnReceivedAt: Date?
    /// Set once a certified copy is physically in hand. Several downstream
    /// tasks (passport, some bank accounts) are blocked until it is.
    var birthCertificateReceivedAt: Date?
    var certifiedCopiesOnHand: Int = 0
    var colorIndex: Int = 0
    var notes: String = ""

    var updatedAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \RequirementTask.child)
    var tasks: [RequirementTask]? = []

    @Relationship(deleteRule: .cascade, inverse: \ChildNote.child)
    var notesList: [ChildNote]? = []

    @Relationship(deleteRule: .cascade, inverse: \VaultDocument.child)
    var vaultDocuments: [VaultDocument]? = []

    init(name: String = "", birthDate: Date = Date(), birthStateCode: String = "") {
        self.id = UUID()
        self.name = name
        self.birthDate = birthDate
        self.birthStateCode = birthStateCode
        self.updatedAt = Date()
    }

    var ssnStatus: SSNStatus {
        get { SSNStatus(rawValue: ssnStatusRaw) ?? .unknown }
        set { ssnStatusRaw = newValue.rawValue }
    }

    var hasSSN: Bool { ssnStatus == .cardReceived }

    /// Reads skip tombstoned rows. Every list in the UI goes through these
    /// rather than the raw relationship, because `tombstone` soft-deletes: the
    /// row stays in the store so a mis-swipe is recoverable.
    var liveTasks: [RequirementTask] {
        (tasks ?? []).filter { $0.deletedAt == nil }
    }

    var liveNotes: [ChildNote] {
        (notesList ?? []).filter { $0.deletedAt == nil }
    }

    var liveVaultDocuments: [VaultDocument] {
        (vaultDocuments ?? [])
            .filter { $0.deletedAt == nil }
            .sorted {
                $0.kind.sortWeight == $1.kind.sortWeight
                    ? $0.addedAt < $1.addedAt
                    : $0.kind.sortWeight < $1.kind.sortWeight
            }
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Your baby" : name
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: birthDate, to: Date()).day ?? 0
    }
}

// MARK: - Family profile

/// The household answers, which apply to every child in the family: where they
/// live, how they are covered, whether the parents are married.
///
/// One row per family. Split off `Child` rather than duplicated onto it so that
/// a second baby inherits the answers instead of asking for them again, and so
/// that changing "we moved to Oregon" fixes every child's plan at once.
@Model
final class FamilyProfile {
    var id: UUID = UUID()
    var residenceStateCode: String = ""
    var parentageRaw: String = ParentageSituation.unknown.rawValue
    /// Whether the second parent is already named on the birth record. For
    /// unmarried parents this is normally done by signing a voluntary
    /// acknowledgment of parentage at the hospital.
    var secondParentOnRecord: Bool = false
    var insuranceKindRaw: String = InsuranceKind.unknown.rawValue
    /// Only read when `insuranceKind` is `.marketplace`. Decides which page the
    /// Marketplace task sends the family to.
    var marketplaceKindRaw: String = MarketplaceKind.unknown.rawValue
    /// A dependent-care FSA election is a separate qualifying-life-event window
    /// from the medical plan, and is missed far more often.
    var hasDependentCareFSA: Bool = false
    var wantsPassport: Bool = false
    var wants529: Bool = false
    var wantsNewbornAccount: Bool = true
    /// Legacy storage. Kept because builds already in the field wrote it, and
    /// it is still the answer to "is anyone taking leave at all". Everything
    /// reads `parentalLeaveTakers`, which is the question that actually forks a
    /// rule, and writing that keeps this in step.
    var takingParentalLeave: Bool = true
    /// Empty means the family answered the old yes/no question and has not seen
    /// the new one, so the getter reads the boolean rather than inventing an
    /// answer nobody gave.
    var parentalLeaveTakersRaw: String = ""
    /// The employer or plan name, used to make the hardest task in the app say
    /// *which* plan rather than "the job-based health plan". Optional, and the
    /// deadline does not depend on it.
    var employerPlanName: String = ""
    /// What the benefits administrator is reachable on. A phone number is what
    /// the 30-day window actually turns on, and it is never to hand at the
    /// moment it is needed.
    var benefitsContactNote: String = ""

    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(id: UUID = UUID()) {
        self.id = id
        self.updatedAt = Date()
    }

    var parentage: ParentageSituation {
        get { ParentageSituation(rawValue: parentageRaw) ?? .unknown }
        set { parentageRaw = newValue.rawValue }
    }

    var insuranceKind: InsuranceKind {
        get { InsuranceKind(rawValue: insuranceKindRaw) ?? .unknown }
        set { insuranceKindRaw = newValue.rawValue }
    }

    var marketplaceKind: MarketplaceKind {
        get { MarketplaceKind(rawValue: marketplaceKindRaw) ?? .unknown }
        set { marketplaceKindRaw = newValue.rawValue }
    }

    var parentalLeaveTakers: ParentalLeaveTakers {
        get {
            ParentalLeaveTakers(rawValue: parentalLeaveTakersRaw)
                ?? (takingParentalLeave ? .oneParent : .nobody)
        }
        set {
            parentalLeaveTakersRaw = newValue.rawValue
            takingParentalLeave = newValue != .nobody
        }
    }

    /// True once the intake has enough to generate a plan that is worth showing.
    /// Deliberately low: a residence state and a coverage answer already produce
    /// the two hard deadlines, and holding the plan back until every optional
    /// question is answered is how an intake wizard becomes the product.
    var isComplete: Bool {
        !residenceStateCode.isEmpty && insuranceKind != .unknown
    }
}

// MARK: - Requirement task

/// One thing the family has to do, whether the catalog generated it or a parent
/// typed it in.
///
/// Generated tasks are materialised as rows rather than computed on the fly, for
/// three reasons: a task has to be assignable to one parent, it has to carry the
/// confirmation number that came back, and both of those have to survive a
/// catalog update. `catalogKey` is what lets the engine recognise its own row
/// later; an empty key means a parent created it by hand and the engine will
/// never touch it.
@Model
final class RequirementTask {
    var id: UUID = UUID()
    var child: Child?
    /// Stable identifier from `RequirementCatalog`, or empty for a custom task.
    var catalogKey: String = ""
    var title: String = ""
    /// Why this applies to *this* family, in one sentence. Not generic help
    /// text: the whole promise of the app is that the list is personalised, and
    /// a task that cannot say why it is there reads as a generic checklist.
    var detail: String = ""
    var categoryRaw: String = RequirementCategory.identity.rawValue
    var dueAt: Date?
    var deadlineKindRaw: String = DeadlineKind.none.rawValue
    /// Where the deadline comes from, phrased for a person ("job-based plans
    /// must allow at least 30 days"). Shown next to the date.
    var deadlineBasis: String = ""
    /// The official page this task sends the parent to. Never a third-party
    /// aggregator and never a form this app submits on their behalf.
    var officialURLString: String = ""
    var officialLinkLabel: String = ""
    /// The citation behind the rule, plus the date it was last checked. This is
    /// the app's whole defensibility: a paperwork concierge whose rules quietly
    /// go stale is worse than no app.
    var sourceURLString: String = ""
    var sourceVerifiedOn: Date?

    var assigneeName: String = ""
    var completedAt: Date?
    var completedByName: String = ""
    /// Engine-owned. Whether this task is a thing you send away and wait for,
    /// which is what puts the follow-up controls on its detail screen.
    var isPostedAway: Bool = false
    /// When the family actually sent this off. Set by hand, because only they
    /// know: the app never files anything, so it cannot observe a submission.
    var submittedAt: Date?
    /// When it should have come back, from the office's own published
    /// turnaround. This is the whole point of tracking a submission: a birth
    /// certificate that has not arrived in six weeks is not slow, it is lost,
    /// and nobody finds out because nothing was ever going to tell them.
    var expectedByAt: Date?
    /// Set when a parent says this one does not apply to them. Dismissed tasks
    /// stay in the store so the engine does not resurrect them on the next pass.
    var dismissedAt: Date?
    var parentNotes: String = ""
    /// Lower sorts first within a due-date bucket.
    var sortWeight: Int = 100
    var isCustom: Bool = false

    var updatedAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \DocumentItem.task)
    var documents: [DocumentItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \Receipt.task)
    var receipts: [Receipt]? = []

    init(title: String = "") {
        self.id = UUID()
        self.title = title
        self.updatedAt = Date()
    }

    var category: RequirementCategory {
        get { RequirementCategory(rawValue: categoryRaw) ?? .identity }
        set { categoryRaw = newValue.rawValue }
    }

    var deadlineKind: DeadlineKind {
        get { DeadlineKind(rawValue: deadlineKindRaw) ?? .none }
        set { deadlineKindRaw = newValue.rawValue }
    }

    var officialURL: URL? {
        officialURLString.isEmpty ? nil : URL(string: officialURLString)
    }

    var sourceURL: URL? {
        sourceURLString.isEmpty ? nil : URL(string: sourceURLString)
    }

    var isDone: Bool { completedAt != nil }
    var isDismissed: Bool { dismissedAt != nil }
    var isOpen: Bool { !isDone && !isDismissed }

    /// Sent, past the date it should have come back, and still not ticked off.
    /// The one state the old checklist could not represent, and the reason
    /// someone opens this app in week eight.
    func isLate(from now: Date = Date()) -> Bool {
        guard isOpen, submittedAt != nil, let expectedByAt else { return false }
        return expectedByAt < now
    }

    var liveDocuments: [DocumentItem] {
        (documents ?? []).filter { $0.deletedAt == nil }.sorted { $0.sortWeight < $1.sortWeight }
    }

    var liveReceipts: [Receipt] {
        (receipts ?? []).filter { $0.deletedAt == nil }.sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Whole days from now until the deadline. Negative once it has passed.
    func daysRemaining(from now: Date = Date()) -> Int? {
        guard let dueAt else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: dueAt)
        ).day
    }
}

// MARK: - Documents

/// One item on a task's "bring these" list.
///
/// Kept as its own row rather than a string array because "have you got it" is
/// the state the family actually shares: one parent finds the certified copy,
/// and the other needs to see that without a phone call.
@Model
final class DocumentItem {
    var id: UUID = UUID()
    var task: RequirementTask?
    /// Stable key within the task, so a catalog update re-finds the row the
    /// family has already ticked off.
    var catalogKey: String = ""
    var title: String = ""
    var detail: String = ""
    var isOnHand: Bool = false
    var markedOnHandAt: Date?
    var sortWeight: Int = 100

    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(title: String = "") {
        self.id = UUID()
        self.title = title
        self.updatedAt = Date()
    }
}

// MARK: - Receipts

enum ReceiptKind: String, Codable, CaseIterable, Sendable {
    case submitted
    case confirmationNumber = "confirmation_number"
    case tracking
    case received
    case note

    var label: String {
        switch self {
        case .submitted: return "Submitted"
        case .confirmationNumber: return "Confirmation number"
        case .tracking: return "Tracking number"
        case .received: return "Received"
        case .note: return "Note"
        }
    }
}

/// Proof that something was filed, and what came back.
///
/// An event, not a state. A task carries a list of the moments something
/// happened to it, which is what the follow-up tracker reads to decide whether
/// a thing that was posted three weeks ago should have arrived by now.
@Model
final class Receipt {
    var id: UUID = UUID()
    var task: RequirementTask?
    var kindRaw: String = ReceiptKind.note.rawValue
    var value: String = ""
    var recordedAt: Date = Date()
    var recordedByName: String = ""

    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(kind: ReceiptKind = .note, value: String = "", recordedAt: Date = Date()) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.value = value
        self.recordedAt = recordedAt
        self.updatedAt = Date()
    }

    var kind: ReceiptKind {
        get { ReceiptKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Notes

/// A deliberately unstructured note against one child.
///
/// It is **not** a credential store and must never become one by drift. No field
/// is typed as a password, no copy invites one, and the body is plaintext on
/// disk. The editor says so at the point of entry, which is the only place the
/// boundary is any use.
@Model
final class ChildNote {
    var id: UUID = UUID()
    var child: Child?
    var title: String = ""
    var body: String = ""
    var isPinned: Bool = false
    var createdByName: String = ""

    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(title: String = "", body: String = "") {
        self.id = UUID()
        self.title = title
        self.body = body
        self.updatedAt = Date()
    }
}

// MARK: - Document vault

/// What a vault entry is a copy of.
///
/// A fixed list rather than free text because the point of the vault is finding
/// one thing quickly while a receptionist waits, and a list someone typed
/// themselves at 3am sorts alphabetically into nonsense.
enum VaultDocumentKind: String, Codable, CaseIterable, Sendable {
    case birthCertificate = "birth_certificate"
    case socialSecurityCard = "social_security_card"
    case dischargePapers = "discharge_papers"
    case insuranceCard = "insurance_card"
    case immunizationRecord = "immunization_record"
    case passport
    case parentageForm = "parentage_form"
    case other

    var label: String {
        switch self {
        case .birthCertificate: return "Birth certificate"
        case .socialSecurityCard: return "Social Security card"
        case .dischargePapers: return "Hospital discharge papers"
        case .insuranceCard: return "Insurance card"
        case .immunizationRecord: return "Immunization record"
        case .passport: return "Passport"
        case .parentageForm: return "Parentage acknowledgment"
        case .other: return "Something else"
        }
    }

    var symbol: String {
        switch self {
        case .birthCertificate: return "doc.text.fill"
        case .socialSecurityCard: return "person.text.rectangle.fill"
        case .dischargePapers: return "cross.case.fill"
        case .insuranceCard: return "creditcard.fill"
        case .immunizationRecord: return "syringe.fill"
        case .passport: return "airplane"
        case .parentageForm: return "figure.2.and.child.holdinghands"
        case .other: return "doc.fill"
        }
    }

    /// Whether photographing this one warrants the one-time warning about what
    /// the app does and does not do with it. True for the two documents whose
    /// loss is expensive and whose contents are worth stealing.
    var isSensitive: Bool {
        self == .socialSecurityCard || self == .passport
    }

    var sortWeight: Int {
        switch self {
        case .birthCertificate: return 0
        case .socialSecurityCard: return 10
        case .insuranceCard: return 20
        case .dischargePapers: return 30
        case .immunizationRecord: return 40
        case .parentageForm: return 50
        case .passport: return 60
        case .other: return 90
        }
    }
}

/// A photograph of a document the family already owns.
///
/// **The image files are never in this row.** Only their filenames are, and the
/// files themselves live in the app container with complete file protection and
/// an exclusion from every backup. That split is deliberate: it means no export,
/// summary or share sheet in this app can reach an image by touching the model
/// layer, because the model layer does not hold one.
///
/// A vault entry is a convenience copy, never the record. The certificate in the
/// drawer is the record. The copy is what you show a receptionist so you do not
/// have to go home.
@Model
final class VaultDocument {
    var id: UUID = UUID()
    var child: Child?
    var kindRaw: String = VaultDocumentKind.other.rawValue
    /// Only used when `kind` is `.other`.
    var customTitle: String = ""
    /// Filenames within the vault directory, in page order. Not paths: the
    /// container URL changes between installs and an absolute path stored here
    /// would break on every restore.
    var pageFileNames: [String] = []
    var addedAt: Date = Date()
    var notes: String = ""

    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(kind: VaultDocumentKind = .other, child: Child? = nil) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.child = child
        self.addedAt = Date()
        self.updatedAt = Date()
    }

    var kind: VaultDocumentKind {
        get { VaultDocumentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var displayTitle: String {
        if kind == .other {
            let trimmed = customTitle.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? VaultDocumentKind.other.label : trimmed
        }
        return kind.label
    }

    var pageCount: Int { pageFileNames.count }
}
