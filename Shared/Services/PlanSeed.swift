import Foundation

/// The answers that generate a plan, small enough to travel in a link.
///
/// This is what replaced an entire sync backend, and the reason it can is that
/// almost nothing in this app is data. A plan is a pure function of about a dozen
/// household answers, so the other parent does not need a copy of the first
/// parent's rows: they need the twelve answers, and their own phone rebuilds an
/// identical plan from the same catalog, offline, in a millisecond.
///
/// What deliberately does **not** travel: anything the family did. No completions,
/// no assignments, no receipts, no ticked documents, and above all no vault
/// filenames. Two phones then diverge on the work, which is correct and honest —
/// they are two people doing separate errands — and the app never claims
/// otherwise.
///
/// What **does** travel is worth naming exactly, because a link forwarded on to
/// a grandparent carries all of it and anyone holding the link can read it: the
/// baby's first name, the birth date, the state and county of the birth, the
/// state you live in, and the household answers. That is a page of a form, not a
/// record of a family's affairs, and every screen that offers to send it says so
/// in those words rather than in a softer summary that leaves the name out.
struct PlanSeed: Codable, Equatable, Sendable {
    /// Bumped only if a future version cannot read this shape. A link sits in an
    /// inbox for months, so a build that cannot recognise its own old format has
    /// to say so rather than silently build the wrong plan.
    var version: Int = 1

    var name: String
    var birthDate: Date
    var birthStateCode: String
    var birthCounty: String
    var isUSCitizen: Bool

    var residenceStateCode: String
    var parentage: String
    var secondParentOnRecord: Bool
    var insuranceKind: String
    /// Optional so that a link sent by an older build still decodes: a missing
    /// value reads as "not sure which marketplace", which is exactly what an
    /// older build knew. A link sits in an inbox for months and has to keep
    /// working when it is finally tapped.
    var marketplaceKind: String?
    var hasDependentCareFSA: Bool
    var wantsPassport: Bool
    var wants529: Bool
    var wantsNewbornAccount: Bool
    var takingParentalLeave: Bool

    static let currentVersion = 1

    // MARK: - Building one

    @MainActor
    static func make(child: Child, profile: FamilyProfile) -> PlanSeed {
        PlanSeed(
            name: child.name,
            birthDate: child.birthDate,
            birthStateCode: child.birthStateCode,
            birthCounty: child.birthCounty,
            isUSCitizen: child.isUSCitizen,
            residenceStateCode: profile.residenceStateCode,
            parentage: profile.parentageRaw,
            secondParentOnRecord: profile.secondParentOnRecord,
            insuranceKind: profile.insuranceKindRaw,
            marketplaceKind: profile.marketplaceKindRaw,
            hasDependentCareFSA: profile.hasDependentCareFSA,
            wantsPassport: profile.wantsPassport,
            wants529: profile.wants529,
            wantsNewbornAccount: profile.wantsNewbornAccount,
            takingParentalLeave: profile.takingParentalLeave
        )
    }

    // MARK: - Links

    /// Where a link points when the other parent does not have the app yet.
    ///
    /// The payload rides in the URL **fragment**, not the query. A fragment is
    /// never sent to the server, so the birth date and state stay on the two
    /// phones even though the link resolves through a web page. That page is
    /// static and does nothing but hand the fragment back to the app.
    static let webBase = "https://jackwallner.com/ios/babydocs/plan.html"

    /// The custom scheme, for a phone that already has the app. Both forms carry
    /// the identical payload, so whichever one the recipient's phone picks up
    /// produces the same plan.
    static let scheme = "babydocs"

    func shareURL() -> URL? {
        guard let payload = encoded() else { return nil }
        return URL(string: "\(Self.webBase)#\(payload)")
    }

    func encoded() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return data.base64URLEncodedString()
    }

    /// Reads a payload out of either link shape, or out of a bare payload the
    /// user pasted. Returns nil rather than throwing: a malformed link is not an
    /// error condition, it is somebody's message app having mangled a URL, and
    /// the only useful response is to say the link did not work.
    static func decode(from url: URL) -> PlanSeed? {
        var payload = url.fragment ?? ""
        if payload.isEmpty, url.scheme == scheme {
            payload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "d" })?.value ?? ""
        }
        guard !payload.isEmpty else { return nil }
        return decode(payload: payload)
    }

    static func decode(payload: String) -> PlanSeed? {
        guard let data = Data(base64URLEncoded: payload) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let seed = try? decoder.decode(PlanSeed.self, from: data) else { return nil }
        guard seed.version <= currentVersion else { return nil }
        return seed
    }
}

// MARK: - base64url

/// Plain base64 uses `+`, `/` and `=`, all of which get percent-escaped,
/// line-wrapped or eaten outright somewhere between a message app, a mail
/// client and a browser address bar. base64url survives that trip.
extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        self = data
    }
}
