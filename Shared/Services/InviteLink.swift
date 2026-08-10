import Foundation

/// One place for the shape of an invitation: what a code looks like, what link
/// carries it, what the message around it says, and how a link is read back.
///
/// The message leads with an https address, never `babydocs://`. A custom
/// scheme is only meaningful on a phone that already has the app: Mail on a
/// phone without it offers "Safari cannot open the page", and a desktop client
/// will not draw it as a link at all, so the person most likely to be invited
/// (the partner who has installed nothing) is handed the one address that
/// cannot help them. The scheme is reached from that page by a tap.
enum InviteLink {
    /// Codes are eight characters from an alphabet that already excludes
    /// look-alikes, because reading one out loud across a room is the realistic
    /// delivery mechanism in the first fortnight after a birth.
    static let codeLength = 8

    /// Canonical. See the hosting note in CLAUDE.md before changing it: this
    /// string ends up in messages that outlive the build that sent them.
    static let webBase = "https://jackwallner.com/ios/babydocs/join.html"

    static let downloadPage = "https://jackwallner.com/ios/babydocs/"

    /// Upper-cases and drops anything that is not a letter or a number, so a
    /// code dictated as "H, 7, K" and typed with spaces or dashes still lands.
    /// Returns nil unless what is left is exactly a code.
    static func normalized(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return cleaned.count == codeLength ? cleaned : nil
    }

    static func webURL(code: String) -> URL? {
        URL(string: "\(webBase)?code=\(code)")
    }

    static func appURL(code: String) -> URL? {
        URL(string: "babydocs://invite?code=\(code)")
    }

    /// Reads a code back out of either address. The https form is here so that
    /// adding an associated domain later needs no second parser, and so the
    /// same function can be tested against the exact string the message
    /// contains.
    static func code(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let carriesCode: Bool
        switch url.scheme?.lowercased() {
        case "babydocs":
            carriesCode = url.host?.lowercased() == "invite"
        case "https", "http":
            carriesCode = url.path.hasSuffix("/join.html")
        default:
            carriesCode = false
        }
        guard carriesCode else { return nil }
        guard let raw = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        return normalized(raw)
    }

    /// The server's own check, so a client-side "looks fine" and a server-side
    /// rejection cannot disagree.
    static func isValidEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$",
            options: [.regularExpression]
        ) != nil
    }
}

enum InviteMessage {
    static func text(code: String, role: GroupRole, childName: String?) -> String {
        let access = role == .viewer
            ? "As a helper you will be able to see the plan and what is still outstanding, but not change it."
            : "As a parent you will be able to add children, take tasks on and record confirmations."
        let subject = childName.map { "the paperwork for \($0)" } ?? "our newborn paperwork"
        let link = InviteLink.webURL(code: code)?.absoluteString ?? InviteLink.downloadPage
        return """
        I am tracking \(subject) in Baby Docs and I would like you on it too.

        \(access)

        Your invitation code is \(code)

        Open this link on your iPhone to join:
        \(link)

        That page shows the code and opens Baby Docs for you. If you already \
        have the app, choose "I have an invitation" on the first screen and type \
        the code in.

        The invitation works once and expires after 48 hours.
        """
    }

    /// Built by hand rather than with `URLComponents.queryItems`, which leaves
    /// `?`, `&`, `+` and `/` unescaped in a query value. The body contains a URL
    /// with its own query string and the address may contain a `+` tag, and a
    /// mail client is entitled to read either as a delimiter.
    static func emailURL(
        address: String,
        code: String,
        role: GroupRole,
        childName: String?
    ) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard InviteLink.isValidEmail(trimmed) else { return nil }
        guard
            let to = escape(trimmed),
            let subject = escape("Join me on Baby Docs"),
            let body = escape(text(code: code, role: role, childName: childName))
        else { return nil }
        return URL(string: "mailto:\(to)?subject=\(subject)&body=\(body)")
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func escape(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: unreserved)
    }
}
