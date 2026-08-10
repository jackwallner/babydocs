import Foundation

/// Where the backend lives. Values come from Info.plist so the simulator and CI
/// can override them with environment variables without a rebuild.
///
/// Only the publishable key ever ships in the binary. It is a public key by
/// design: every row it can reach is gated by row-level security, and the
/// service-role key (which bypasses RLS entirely) lives in
/// `~/.babydocs_credentials` and is never referenced from app code.
///
/// **Until a project is provisioned this returns `isConfigured == false`, and
/// the app is a complete local-only tracker.** That is not a degraded mode: the
/// plan, the deadlines, the documents and the receipts all work with no account
/// at all. Signing in adds the second parent, and nothing else.
enum SupabaseConfig {
    /// In DEBUG the environment wins over the Info.plist, so a UI test can aim
    /// the app at an unroutable host and hand it, from the app's own point of
    /// view, exactly what airplane mode does: every request failing at the
    /// transport layer. Release builds read only the Info.plist, so no shipped
    /// binary can be redirected this way.
    static let url: URL = {
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
            ?? ""
        #else
        let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        #endif
        return URL(string: raw) ?? URL(string: "https://placeholder.supabase.co")!
    }()

    static let anonKey: String = {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        if !fromPlist.isEmpty { return fromPlist }
        return ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? ""
    }()

    static var isConfigured: Bool {
        !anonKey.isEmpty && url.host?.contains("placeholder") == false
    }
}
