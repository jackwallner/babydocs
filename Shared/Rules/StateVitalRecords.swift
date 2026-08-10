import Foundation

/// Who issues a birth certificate, per state.
///
/// Birth records are issued by state or local vital-records offices, and the
/// cost, the accepted ID and the ordering channel differ in every one of them.
/// That variation is the actual moat of this app, and it is also the thing most
/// likely to go quietly stale, so a state is only ever presented as *verified*
/// when someone has read that state's own page and written the date down.
///
/// Everything else falls back to the federal directory, which carries a state
/// picker and is maintained by somebody else. A generic-but-correct link beats a
/// specific-but-guessed one: a parent who follows a wrong link to a wrong office
/// loses a fortnight, and the app's whole promise is that they do not.
struct VitalRecordsOffice: Sendable, Equatable {
    let stateCode: String
    let officeName: String
    let urlString: String
    /// One or two sentences of what is actually different here. Empty for the
    /// fallback, because inventing detail is the failure mode this guards.
    let orderingNote: String
    /// The day a human last read the linked page. `nil` means this entry is the
    /// federal fallback and the app says so in the UI.
    let verifiedOn: Date?

    var url: URL? { URL(string: urlString) }
    var isVerified: Bool { verifiedOn != nil }
}

enum StateVitalRecords {
    /// `usa.gov`'s birth-certificate page, which carries a state-by-state picker.
    static let federalDirectoryURL = "https://www.usa.gov/birth-certificate"

    /// Verified states. Adding one means reading that state's own page, writing
    /// the note from what it actually says, and stamping the date. Never bulk
    /// import a list of URLs into here.
    private static let verified: [String: VitalRecordsOffice] = [
        "CA": VitalRecordsOffice(
            stateCode: "CA",
            officeName: "California Department of Public Health, Vital Records",
            urlString: "https://www.cdph.ca.gov/Programs/CHSI/Pages/Vital-Records.aspx",
            orderingNote: """
            California issues both authorized certified copies and informational \
            copies. Only the authorized copy establishes identity, and only a \
            parent named on the record (or a short list of other relatives) may \
            request one. The request has to carry a notarized sworn statement \
            unless it is made in person. County recorders in the county of birth \
            are usually faster than the state office for a recent birth.
            """,
            verifiedOn: date(2026, 8, 9)
        )
    ]

    static func office(for stateCode: String) -> VitalRecordsOffice {
        let code = stateCode.uppercased()
        if let entry = verified[code] { return entry }
        return VitalRecordsOffice(
            stateCode: code,
            officeName: code.isEmpty
                ? "Your state's vital records office"
                : "\(USState.displayName(for: code)) vital records office",
            urlString: federalDirectoryURL,
            orderingNote: "",
            verifiedOn: nil
        )
    }

    static var verifiedStateCodes: [String] {
        verified.keys.sorted()
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
