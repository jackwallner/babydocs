import Foundation
import Supabase

// MARK: - DTOs

/// Everything that crosses the wire is a plain `Sendable` struct. SwiftData's
/// `@Model` classes are not `Sendable` and must never leave the actor that owns
/// their `ModelContext`, so the sync engine converts at the boundary.
protocol SyncDTO: Codable, Sendable, Identifiable {
    static var entity: SyncEntity { get }
    /// The primary-key column, which is not always called `id`.
    static var idColumn: String { get }
    var id: UUID { get }
    var updated_at: Date? { get }
    var deleted_at: Date? { get }
}

extension SyncDTO {
    static var idColumn: String { "id" }
}

/// Where a pull left off. Compound because a timestamp alone is not a stable
/// cursor: several rows written in the same transaction share `updated_at` to
/// the microsecond, and a page boundary landing in the middle of them would
/// either skip rows or loop on them forever.
struct SyncPage: Sendable, Equatable {
    var updatedAt: Date
    var id: UUID
}

struct FamilyProfileDTO: SyncDTO {
    static let entity = SyncEntity.familyProfile
    var id: UUID
    var family_id: UUID
    var residence_state: String
    var parentage: String
    var second_parent_on_record: Bool
    var insurance_kind: String
    var employer_plan_name: String
    var has_dependent_care_fsa: Bool
    var wants_passport: Bool
    var wants_529: Bool
    var wants_trump_account: Bool
    var taking_parental_leave: Bool
    var updated_at: Date?
    var deleted_at: Date?
}

struct ChildDTO: SyncDTO {
    static let entity = SyncEntity.child
    var id: UUID
    var family_id: UUID
    var name: String
    var birth_date: Date
    var birth_state: String
    var birth_county: String
    var is_us_citizen: Bool
    var ssn_status: String
    var ssn_received_at: Date?
    var birth_certificate_received_at: Date?
    var certified_copies_on_hand: Int
    var color_index: Int
    var notes: String
    var updated_at: Date?
    var deleted_at: Date?
}

/// The plan itself. `assignee_name` and `completed_by_name` are carried as names
/// rather than only ids for the same reason the receipts are: the sentence the
/// family needs ("Sam still has the passport appointment") has to render from
/// the local store with no lookup and no network.
struct RequirementTaskDTO: SyncDTO {
    static let entity = SyncEntity.task
    var id: UUID
    var family_id: UUID
    var child_id: UUID
    var catalog_key: String
    var title: String
    var detail: String
    var category: String
    var due_at: Date?
    var deadline_kind: String
    var deadline_basis: String
    var official_url: String
    var official_link_label: String
    var source_url: String
    var source_verified_on: Date?
    var assignee_user_id: UUID?
    var assignee_name: String
    var completed_at: Date?
    var completed_by_name: String
    var dismissed_at: Date?
    var parent_notes: String
    var sort_weight: Int
    var is_custom: Bool
    var updated_at: Date?
    var deleted_at: Date?
}

struct DocumentItemDTO: SyncDTO {
    static let entity = SyncEntity.document
    var id: UUID
    var family_id: UUID
    var task_id: UUID
    var catalog_key: String
    var title: String
    var detail: String
    var is_on_hand: Bool
    var marked_on_hand_at: Date?
    var sort_weight: Int
    var updated_at: Date?
    var deleted_at: Date?
}

struct ReceiptDTO: SyncDTO {
    static let entity = SyncEntity.receipt
    var id: UUID
    var family_id: UUID
    var task_id: UUID
    var kind: String
    var value: String
    var recorded_at: Date
    var recorded_by_name: String
    var updated_at: Date?
    var deleted_at: Date?
}

/// A free-form note. The body crosses the wire as ordinary text, like every
/// other free-text column in this schema, and is protected by exactly the same
/// row-level security as the plan. Nothing in the UI asks for credentials, and
/// if that ever changes this DTO is where the encryption would have to go in.
struct ChildNoteDTO: SyncDTO {
    static let entity = SyncEntity.note
    var id: UUID
    var family_id: UUID
    var child_id: UUID
    var title: String
    var body: String
    var is_pinned: Bool
    var created_by_name: String
    var updated_at: Date?
    var deleted_at: Date?
}

// MARK: - Remote

/// Fronted by a protocol so the engine can be tested without a backend. Cursor
/// pagination, version conflicts and role-changed rejections are all
/// deterministic against a fake and effectively untestable against a live one.
protocol SyncRemote: Sendable {
    func pull<T: SyncDTO>(_ type: T.Type, after page: SyncPage?, limit: Int) async throws -> [T]
    func push<T: SyncDTO>(_ rows: [T]) async throws
}

/// Why a push failed, which decides whether the outbox retries or gives up.
enum SyncError: Error, Equatable {
    /// Network. Keep the entry queued and try again later.
    case offline
    /// The server refused on authorization grounds. Retrying cannot fix this:
    /// the most likely cause is a helper being demoted while their phone was
    /// offline, and their queued edits are no longer allowed.
    case rejected(String)
    case server(String)
}

struct SupabaseSyncRemote: SyncRemote {
    let client: SupabaseClient
    let groupID: UUID

    func pull<T: SyncDTO>(_ type: T.Type, after page: SyncPage?, limit: Int) async throws -> [T] {
        do {
            var query = client
                .from(T.entity.table)
                .select()
                .eq("family_id", value: groupID)

            if let page {
                // Strictly after (updated_at, id) in lexicographic order. `or`
                // is how PostgREST expresses the compound comparison.
                query = query.or(
                    "updated_at.gt.\(Self.iso(page.updatedAt))," +
                    "and(updated_at.eq.\(Self.iso(page.updatedAt))," +
                    "\(T.idColumn).gt.\(page.id.uuidString))"
                )
            }

            return try await query
                .order("updated_at", ascending: true)
                .order(T.idColumn, ascending: true)
                .limit(limit)
                .execute()
                .value
        } catch {
            throw Self.classify(error)
        }
    }

    func push<T: SyncDTO>(_ rows: [T]) async throws {
        guard !rows.isEmpty else { return }
        do {
            // Upsert on the primary key. Because the client generated these
            // UUIDs in the first place, re-sending a row the server already has
            // is a no-op rather than a duplicate, which is what makes retrying
            // safe after a timeout where we never learned the outcome.
            try await client
                .from(T.entity.table)
                .upsert(rows, onConflict: T.idColumn)
                .execute()
        } catch {
            throw Self.classify(error)
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func classify(_ error: Error) -> SyncError {
        if error is URLError { return .offline }
        if (error as NSError).domain == NSURLErrorDomain { return .offline }

        // A row the client cannot decode is a schema disagreement, not a bad
        // network, and calling it `.offline` would report the app as offline
        // while it sits on five bars. Named explicitly so it reaches
        // `lastError` and a person sees it.
        if error is DecodingError { return .server("This app is out of date for the server's data.") }

        if let postgrest = error as? PostgrestError {
            // 42501 is insufficient_privilege, which is what an RLS policy
            // returns when this user is no longer allowed to write this row.
            if postgrest.code == "42501" || postgrest.code == "PGRST301" {
                return .rejected(postgrest.message)
            }
            // Everything else, including PGRST204 (no such column) and PGRST205
            // (no such table). Both are fixed by a deploy rather than by the
            // user, so they stay retryable `.server` failures rather than
            // becoming a "needs a look" the family is asked to resolve and
            // cannot.
            return .server(postgrest.message)
        }

        return .offline
    }
}
