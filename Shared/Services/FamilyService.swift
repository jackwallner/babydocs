import Foundation
import OSLog
import SwiftData
import Supabase

// MARK: - Wire types

/// A member as the family sees them. Deliberately not the `family_members` row:
/// the UI needs the display name, which lives on `profiles`.
struct FamilyMember: Identifiable, Sendable, Equatable {
    var id: UUID
    var displayName: String
    var role: GroupRole
    var joinedAt: Date
    var isSelf: Bool

    var resolvedName: String {
        if isSelf { return displayName.isEmpty ? "You" : "\(displayName) (you)" }
        return displayName.isEmpty ? "Family member" : displayName
    }
}

struct PendingInvite: Identifiable, Sendable, Equatable {
    var id: String { code }
    var code: String
    var email: String?
    var role: GroupRole
    var expiresAt: Date

    var isExpired: Bool { expiresAt <= Date() }
}

/// Why an invite code was refused. The server returns these as values rather
/// than raising, because a raised exception rolls back the rate-limit row that
/// the same call just wrote.
enum InviteFailure: String, Sendable {
    case invalidCode = "invalid_code"
    case rateLimited = "rate_limited"
    case alreadyInGroup = "already_in_group"

    var message: String {
        switch self {
        case .invalidCode:
            return "That code did not work. Codes expire after 48 hours, so ask for a fresh one."
        case .rateLimited:
            return "Too many tries. Wait an hour and then try again."
        case .alreadyInGroup:
            return "This account already belongs to a family. Add the new baby to that family instead, so one plan covers both."
        }
    }
}

enum FamilyServiceError: LocalizedError {
    case notSignedIn
    case noFamily
    case notConfigured
    case invite(InviteFailure)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in first."
        case .noFamily: return "You have not set up a shared family yet."
        case .notConfigured:
            return "Sharing is not available in this build yet. Everything else works on this device."
        case .invite(let failure): return failure.message
        case .server(let message): return message
        }
    }
}

// MARK: - Service

/// Everything about *who else is on this plan and what they may do*.
///
/// Membership is cached into a local `Family` row on every successful load, and
/// every read below prefers that cache. Role gating has to work with the network
/// down: an app that cannot decide whether you may tick something off until a
/// server answers must either block or guess, and at a government counter both
/// are the wrong answer.
///
/// Every mutation goes through a security-definer RPC rather than a table write.
/// `family_members` has no client insert or update policy at all, so there is no
/// second path that could drift from these.
@MainActor
@Observable
final class FamilyService {
    static let shared = FamilyService()

    private(set) var members: [FamilyMember] = []
    private(set) var pendingInvites: [PendingInvite] = []

    /// What to stamp on a row this device writes, so the other parent reading it
    /// later sees a name rather than "You" for someone who is not them.
    ///
    /// Empty until `loadMembers()` has run at least once, which is why every
    /// caller supplies its own fallback rather than blocking on it: naming the
    /// author is worth having and is never worth a spinner.
    var selfDisplayName: String {
        members.first(where: \.isSelf)?.displayName ?? ""
    }

    private(set) var isWorking = false
    private(set) var lastError: String?

    /// Mirrored from the cached `Family` so views can read it synchronously.
    private(set) var activeGroupID: UUID?
    private(set) var familyName: String = ""
    private(set) var role: GroupRole = .owner
    private(set) var hasPlus: Bool = false

    private let log = Logger(subsystem: "com.jackwallner.babydocs", category: "family")
    private var auth: AuthService { .shared }
    private var client: SupabaseClient { auth.client }

    private var context: ModelContext { BabyModelStore.sharedModelContainer.mainContext }

    private init() {}

    // MARK: Cache

    /// Reads the cached membership. Synchronous, network-free, safe before first
    /// paint, and the reason a helper's read-only UI is correct offline.
    func loadFromCache() {
        guard let family = cachedFamily() else {
            activeGroupID = nil
            familyName = ""
            hasPlus = false
            return
        }
        activeGroupID = family.id
        familyName = family.name
        role = family.role
        hasPlus = family.hasPlus
    }

    private func cachedFamily() -> Family? {
        var descriptor = FetchDescriptor<Family>(sortBy: [SortDescriptor(\.joinedAt)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func cache(id: UUID, name: String, role newRole: GroupRole) {
        let family = cachedFamily() ?? {
            let new = Family(id: id, name: name, role: newRole)
            context.insert(new)
            return new
        }()
        family.id = id
        family.name = name
        family.role = newRole
        family.updatedAt = Date()
        try? context.save()
        loadFromCache()
    }

    // MARK: Refresh

    /// Pulls the caller's membership row and the billing row. Failure is never
    /// escalated: the cache stays authoritative and the UI stays usable.
    func refresh() async {
        guard SupabaseConfig.isConfigured, let userID = auth.userID else { return }

        struct MembershipRow: Decodable {
            struct FamilyRow: Decodable { var id: UUID; var name: String }
            var role: String
            var joined_at: Date
            var families: FamilyRow
        }

        do {
            let rows: [MembershipRow] = try await client
                .from("family_members")
                .select("role, joined_at, families(id, name)")
                .eq("user_id", value: userID)
                .is("removed_at", value: nil)
                .order("joined_at", ascending: true)
                .execute()
                .value

            guard let row = rows.first else {
                // Signed in but in no family. Not an error: it is the state
                // between signing in and choosing a path.
                return
            }

            if rows.count > 1 {
                lastError = "This account belongs to more than one family. Contact support so the plans can be merged safely."
            }

            cache(
                id: row.families.id,
                name: row.families.name,
                role: GroupRole(rawValue: row.role) ?? .viewer
            )
            await refreshBilling()
        } catch {
            log.notice("Membership refresh failed, using cache: \(error.localizedDescription)")
        }
    }

    /// The family-scoped entitlement. Cached alongside membership so the parent
    /// who did not pay keeps Plus while offline.
    func refreshBilling() async {
        guard SupabaseConfig.isConfigured, let groupID = activeGroupID else { return }

        struct BillingRow: Decodable {
            var entitlement: String
            var expires_at: Date?
            var is_lifetime: Bool
        }

        do {
            let rows: [BillingRow] = try await client
                .from("family_billing")
                .select("entitlement, expires_at, is_lifetime")
                .eq("family_id", value: groupID)
                .limit(1)
                .execute()
                .value

            guard let family = cachedFamily() else { return }
            if let row = rows.first {
                family.entitlement = row.entitlement
                family.entitlementExpiresAt = row.expires_at
                family.isLifetime = row.is_lifetime
            } else {
                family.entitlement = "free"
                family.entitlementExpiresAt = nil
                family.isLifetime = false
            }
            family.updatedAt = Date()
            try? context.save()
            loadFromCache()
        } catch {
            log.notice("Billing refresh failed, using cache: \(error.localizedDescription)")
        }
    }

    func loadMembers() async {
        guard SupabaseConfig.isConfigured, let groupID = activeGroupID, let me = auth.userID else { return }

        struct MemberRow: Decodable {
            struct ProfileRow: Decodable { var display_name: String }
            var user_id: UUID
            var role: String
            var joined_at: Date
            var profiles: ProfileRow?
        }

        do {
            let rows: [MemberRow] = try await client
                .from("family_members")
                .select("user_id, role, joined_at, profiles(display_name)")
                .eq("family_id", value: groupID)
                .is("removed_at", value: nil)
                .order("joined_at", ascending: true)
                .execute()
                .value

            members = rows.map {
                FamilyMember(
                    id: $0.user_id,
                    displayName: $0.profiles?.display_name ?? "",
                    role: GroupRole(rawValue: $0.role) ?? .parent,
                    joinedAt: $0.joined_at,
                    isSelf: $0.user_id == me
                )
            }
        } catch {
            log.notice("Member list failed: \(error.localizedDescription)")
        }
    }

    func loadPendingInvites() async {
        guard SupabaseConfig.isConfigured, let groupID = activeGroupID else {
            pendingInvites = []
            return
        }

        struct InviteRow: Decodable {
            var code: String
            var intended_email: String?
            var role_to_grant: String
            var expires_at: Date
        }

        do {
            let rows: [InviteRow] = try await client
                .from("invite_codes")
                .select("code, intended_email, role_to_grant, expires_at")
                .eq("family_id", value: groupID)
                .is("used_at", value: nil)
                .is("revoked_at", value: nil)
                .order("created_at", ascending: false)
                .execute()
                .value

            pendingInvites = rows.map {
                PendingInvite(
                    code: $0.code,
                    email: $0.intended_email,
                    role: GroupRole(rawValue: $0.role_to_grant) ?? .parent,
                    expiresAt: $0.expires_at
                )
            }
        } catch {
            log.notice("Pending invite list failed: \(error.localizedDescription)")
        }
    }

    // MARK: Lifecycle

    /// Creates the family and adopts whatever is already on this device into it.
    ///
    /// Adoption is the ordinary write path, not a special one: the local UUIDs
    /// are already the server primary keys, so stamping the family id on and
    /// marking the rows dirty is enough, and it inherits idempotency and
    /// resumability for free.
    @discardableResult
    func createFamily(named name: String) async throws -> UUID {
        guard SupabaseConfig.isConfigured else { throw FamilyServiceError.notConfigured }
        guard auth.isSignedIn else { throw FamilyServiceError.notSignedIn }
        guard activeGroupID == nil else {
            throw FamilyServiceError.server("You already have a family. Add the new baby to it instead.")
        }
        isWorking = true
        defer { isWorking = false }

        do {
            let groupID: UUID = try await client
                .rpc("create_family", params: ["p_name": name])
                .execute()
                .value

            cache(id: groupID, name: name, role: .owner)
            return groupID
        } catch {
            throw FamilyServiceError.server(error.localizedDescription)
        }
    }

    func rename(to name: String) async throws {
        guard let groupID = activeGroupID else { throw FamilyServiceError.noFamily }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await client
                .from("families")
                .update(["name": trimmed])
                .eq("id", value: groupID)
                .execute()
            cache(id: groupID, name: trimmed, role: role)
        } catch {
            throw FamilyServiceError.server(error.localizedDescription)
        }
    }

    // MARK: Invites

    func generateInviteCode(
        role inviteRole: GroupRole,
        email: String? = nil,
        ttlHours: Int = 48
    ) async throws -> String {
        guard SupabaseConfig.isConfigured else { throw FamilyServiceError.notConfigured }
        guard let groupID = activeGroupID else { throw FamilyServiceError.noFamily }
        isWorking = true
        defer { isWorking = false }

        // Every RPC parameter is text and cast to uuid inside the function, so
        // PostgREST never has to choose between a (uuid) and a (text) overload.
        var params: [String: String] = [
            "p_family_id": groupID.uuidString,
            "p_role": inviteRole == .viewer ? "viewer" : "parent",
            "p_ttl_hours": String(ttlHours)
        ]
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalizedEmail, !normalizedEmail.isEmpty {
            params["p_email"] = normalizedEmail
        }

        do {
            let code: String = try await client
                .rpc("generate_invite_code", params: params)
                .execute()
                .value
            await loadPendingInvites()
            return code
        } catch {
            throw FamilyServiceError.server(error.localizedDescription)
        }
    }

    func revokeInviteCode(_ code: String) async throws {
        do {
            try await client
                .rpc("revoke_invite_code", params: ["p_code": code])
                .execute()
            await loadPendingInvites()
        } catch {
            throw FamilyServiceError.server(error.localizedDescription)
        }
    }

    @discardableResult
    func acceptInvite(code: String) async throws -> UUID {
        guard SupabaseConfig.isConfigured else { throw FamilyServiceError.notConfigured }
        guard auth.isSignedIn else { throw FamilyServiceError.notSignedIn }
        isWorking = true
        defer { isWorking = false }

        struct AcceptRow: Decodable {
            var ok: Bool
            var joined_family_id: UUID?
            var error_code: String?
        }

        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let rows: [AcceptRow] = try await client
                .rpc("accept_invite", params: ["p_code": normalized])
                .execute()
                .value

            guard let row = rows.first else {
                throw FamilyServiceError.invite(.invalidCode)
            }
            guard row.ok, let groupID = row.joined_family_id else {
                throw FamilyServiceError.invite(
                    InviteFailure(rawValue: row.error_code ?? "") ?? .invalidCode
                )
            }

            await refresh()
            return groupID
        } catch let error as FamilyServiceError {
            throw error
        } catch {
            throw FamilyServiceError.server(error.localizedDescription)
        }
    }

    // MARK: Membership mutations

    func changeRole(of userID: UUID, to newRole: GroupRole) async throws {
        guard let groupID = activeGroupID else { throw FamilyServiceError.noFamily }
        try await call("change_role", [
            "p_family_id": groupID.uuidString,
            "p_user_id": userID.uuidString,
            "p_role": newRole.rawValue
        ])
        await loadMembers()
    }

    func removeMember(_ userID: UUID) async throws {
        guard let groupID = activeGroupID else { throw FamilyServiceError.noFamily }
        try await call("remove_member", [
            "p_family_id": groupID.uuidString,
            "p_user_id": userID.uuidString
        ])
        await loadMembers()
    }

    func transferOwnership(to userID: UUID) async throws {
        guard let groupID = activeGroupID else { throw FamilyServiceError.noFamily }
        try await call("transfer_ownership", [
            "p_family_id": groupID.uuidString,
            "p_new_owner_id": userID.uuidString
        ])
        await refresh()
        await loadMembers()
    }

    func leaveFamily() async throws {
        guard let groupID = activeGroupID else { throw FamilyServiceError.noFamily }
        try await call("leave_family", ["p_family_id": groupID.uuidString])
        forgetFamilyLocally()
    }

    func deleteFamily() async throws {
        guard let groupID = activeGroupID else { throw FamilyServiceError.noFamily }
        try await call("delete_family", ["p_family_id": groupID.uuidString])
        forgetFamilyLocally()
    }

    /// Drops the membership cache and the shared record, leaving the device with
    /// nothing it is no longer entitled to hold. The one legitimate hard delete
    /// in the app: this is a wipe, not a sync delete, so it does not tombstone.
    func forgetFamilyLocally() {
        if let family = cachedFamily() { context.delete(family) }
        for child in ((try? context.fetch(FetchDescriptor<Child>())) ?? [])
        where child.groupID != nil {
            context.delete(child)
        }
        for cursor in (try? context.fetch(FetchDescriptor<SyncCursor>())) ?? [] {
            context.delete(cursor)
        }
        for entry in (try? context.fetch(FetchDescriptor<OutboxEntry>())) ?? [] {
            context.delete(entry)
        }
        try? context.save()
        members = []
        pendingInvites = []
        loadFromCache()
    }

    private func call(_ name: String, _ params: [String: String]) async throws {
        guard SupabaseConfig.isConfigured else { throw FamilyServiceError.notConfigured }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.rpc(name, params: params).execute()
        } catch {
            throw FamilyServiceError.server(error.localizedDescription)
        }
    }
}
