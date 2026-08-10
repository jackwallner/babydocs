import AuthenticationServices
import CryptoKit
import Foundation
import OSLog
import Supabase

/// Session ownership, built around one requirement that outranks everything
/// else here: a parent opening the app at a counter with no signal must land on
/// their plan, not on a sign-in screen.
///
/// Three things make that true, and all three are load-bearing:
///
/// 1. `bootstrap()` reads `client.auth.currentSession`, which is a synchronous,
///    non-throwing, network-free read of the Keychain-backed store. The async
///    `client.auth.session` property refreshes over the network and throws when
///    it cannot, which would put a login wall in front of a cached plan at the
///    worst possible moment.
/// 2. The client is configured with `emitLocalSessionAsInitialSession: true`,
///    so the SDK emits the stored session immediately regardless of expiry and
///    swallows a failed background refresh rather than reporting a sign-out.
/// 3. `classify(_:)` never treats a transport failure as a sign-out. Only a
///    definitive server rejection of the refresh token counts.
///
/// Point 3 is not redundant with point 2. The SDK's behaviour here has
/// regressed before; we own this guarantee, not the SDK.
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    enum State: Equatable {
        /// Before the first `bootstrap()`. Never rendered as signed out.
        case unknown
        case signedOut
        case signedIn(userID: UUID)
    }

    private(set) var state: State = .unknown
    /// True when the last network attempt failed for transport reasons. Drives
    /// a quiet "showing your saved copy" line, never a blocking screen.
    private(set) var isOffline = false
    private(set) var displayName: String = ""

    let client: SupabaseClient

    private let log = Logger(subsystem: "com.jackwallner.babydocs", category: "auth")
    private var currentNonce: String?

    var userID: UUID? {
        if case let .signedIn(id) = state { return id }
        return nil
    }

    var isSignedIn: Bool { userID != nil }

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    // Emit the stored session on launch even if it has expired,
                    // and refresh in the background. Without this the SDK awaits
                    // a network refresh before reporting the initial session,
                    // which is the offline-launch failure this app cannot have.
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // MARK: - Launch

    /// Synchronous, network-free. Safe to call before first paint.
    func bootstrap() {
        guard SupabaseConfig.isConfigured else {
            state = .signedOut
            return
        }
        if let session = client.auth.currentSession {
            state = .signedIn(userID: session.user.id)
            displayName = Self.name(from: session.user)
            log.info("Restored a local session; expired: \(session.isExpired)")
        } else {
            state = .signedOut
            log.info("No local session")
        }
    }

    /// Best-effort refresh, run after the UI is already on screen. Failure here
    /// is expected and must never be escalated into a sign-out.
    func refreshInBackground() async {
        guard SupabaseConfig.isConfigured, client.auth.currentSession != nil else { return }
        do {
            let session = try await client.auth.refreshSession()
            state = .signedIn(userID: session.user.id)
            displayName = Self.name(from: session.user)
            isOffline = false
        } catch {
            switch Self.classify(error) {
            case .offline:
                isOffline = true
                log.notice("Refresh failed, staying on the cached session: \(error.localizedDescription)")
            case .revoked:
                log.error("Refresh token was rejected by the server; signing out")
                forgetSession()
            }
        }
    }

    // MARK: - Error classification

    enum Failure {
        /// Transport, DNS, timeout, airplane mode. Keep the session and the cache.
        case offline
        /// The server definitively rejected the refresh token. Genuinely signed out.
        case revoked
    }

    /// Deliberately conservative: anything not recognised as a definitive
    /// rejection is treated as offline. Wrongly staying signed in shows a stale
    /// plan, which is recoverable. Wrongly signing out hides a deadline behind a
    /// login wall, which is not.
    static func classify(_ error: Error) -> Failure {
        if error is URLError { return .offline }

        guard let authError = error as? AuthError else { return .offline }

        switch authError {
        case .sessionMissing:
            return .revoked
        default:
            break
        }

        switch authError.errorCode {
        case .refreshTokenNotFound, .refreshTokenAlreadyUsed,
             .sessionNotFound, .sessionExpired,
             .userNotFound, .userBanned, .badJWT:
            return .revoked
        default:
            return .offline
        }
    }

    // MARK: - Sign in

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleSignIn(_ authorization: ASAuthorization) async throws {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            throw AuthServiceError.appleCredentialUnavailable
        }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        currentNonce = nil

        state = .signedIn(userID: session.user.id)
        isOffline = false

        // Apple only hands over the name on the very first authorization, so it
        // has to be captured now or never.
        let appleName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        if !appleName.isEmpty {
            try? await updateDisplayName(appleName)
        } else {
            displayName = Self.name(from: session.user)
        }
    }

    // MARK: - Profile

    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let userID else { return }

        try await client
            .from("profiles")
            .update(["display_name": trimmed])
            .eq("id", value: userID)
            .execute()

        displayName = trimmed
    }

    // MARK: - Leaving

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            log.error("Sign out call failed, clearing locally anyway: \(error.localizedDescription)")
        }
        forgetSession()
    }

    /// App Review 5.1.1(v). The RPC hands off or cleans up any family this user
    /// owns, but never deletes the other parent's plan: rows they authored keep
    /// a name snapshot so the record still reads "recorded by Sam" afterwards.
    func deleteAccount() async throws {
        try await client.rpc("delete_account").execute()
        forgetSession()
    }

    private func forgetSession() {
        state = .signedOut
        displayName = ""
    }

    // MARK: - Helpers

    private static func name(from user: User) -> String {
        if let value = user.userMetadata["display_name"]?.stringValue, !value.isEmpty {
            return value
        }
        if let value = user.userMetadata["full_name"]?.stringValue, !value.isEmpty {
            return value
        }
        return ""
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // The nonce only needs to be unguessable per attempt; UUIDs are an
            // acceptable fallback if the security framework refuses.
            return UUID().uuidString + UUID().uuidString
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum AuthServiceError: LocalizedError {
    case appleCredentialUnavailable
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .appleCredentialUnavailable:
            return "Apple did not return a sign-in token. Please try again."
        case .notConfigured:
            return "Sharing is not available in this build yet. Everything else works on this device."
        }
    }
}
