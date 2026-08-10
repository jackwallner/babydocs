import Foundation
import SwiftData

// MARK: - Family membership

enum GroupRole: String, Codable, CaseIterable, Sendable {
    case owner, parent, viewer

    /// The line the database draws too: owner and parent share every read and
    /// write, and the split that matters is against `viewer`. A grandparent
    /// helping with the passport appointment does not get to edit the plan.
    var isStaff: Bool { self == .owner || self == .parent }

    var label: String {
        switch self {
        case .owner: return "Organizer"
        case .parent: return "Parent"
        case .viewer: return "Helper"
        }
    }

    var blurb: String {
        switch self {
        case .owner: return "Can do everything, including billing and removing people."
        case .parent: return "Can add children, complete tasks and record confirmations."
        case .viewer: return "Can see the plan and what is left, but cannot change it."
        }
    }
}

/// Local mirror of `families` plus this device's row in `family_members`.
///
/// Cached rather than fetched because role gating has to work offline: an app
/// that cannot tell whether you may edit until the network answers has to
/// either block or guess, and both are wrong when a parent is standing at a
/// Social Security office counter with one bar.
@Model
final class Family {
    var id: UUID = UUID()
    var name: String = ""
    var roleRaw: String = GroupRole.owner.rawValue
    var joinedAt: Date = Date()
    /// Family-scoped entitlement, mirrored from `family_billing`. One parent
    /// pays and the other is covered; charging the second parent to see the
    /// same deadline is the fastest way to make the app useless.
    var entitlement: String = "free"
    var entitlementExpiresAt: Date?
    var isLifetime: Bool = false
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), name: String, role: GroupRole) {
        self.id = id
        self.name = name
        self.roleRaw = role.rawValue
        self.joinedAt = Date()
        self.updatedAt = Date()
    }

    var role: GroupRole {
        get { GroupRole(rawValue: roleRaw) ?? .viewer }
        set { roleRaw = newValue.rawValue }
    }

    var hasPlus: Bool {
        guard entitlement == "plus" else { return false }
        if isLifetime { return true }
        guard let entitlementExpiresAt else { return false }
        return entitlementExpiresAt > Date()
    }
}

// MARK: - Outbox

enum OutboxStatus: String, Codable, Sendable {
    case pending
    /// Retrying with backoff after a transient failure.
    case retrying
    /// The server refused it for a reason retrying cannot fix, most often a
    /// role that changed while this device was offline. Surfaced to the user
    /// rather than retried forever.
    case needsReview
}

/// A local write waiting to reach the server.
///
/// Writes queue here rather than going straight out so that ticking off "got
/// the certified copy" in a records office basement still works, and so a
/// failed push is a queued row rather than lost data. Coalescing is per entity
/// kind, decided by the engine: two edits to the same task collapse into one
/// upsert because only the final state matters, while two receipts never
/// collapse because each is a distinct thing that happened.
@Model
final class OutboxEntry {
    var id: UUID = UUID()
    var entityTypeRaw: String = ""
    var entityID: UUID = UUID()
    var groupID: UUID?
    var createdAt: Date = Date()
    var attempts: Int = 0
    var statusRaw: String = OutboxStatus.pending.rawValue
    var lastError: String = ""
    var notBefore: Date = Date()

    init(entityType: SyncEntity, entityID: UUID, groupID: UUID?) {
        self.id = UUID()
        self.entityTypeRaw = entityType.rawValue
        self.entityID = entityID
        self.groupID = groupID
        self.createdAt = Date()
        self.notBefore = Date()
    }

    var entityType: SyncEntity {
        get { SyncEntity(rawValue: entityTypeRaw) ?? .child }
        set { entityTypeRaw = newValue.rawValue }
    }

    var status: OutboxStatus {
        get { OutboxStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - Cursor

/// Per-entity pull cursor.
///
/// The timestamp is always the server's `updated_at`, never the device clock. A
/// phone whose clock is fast would otherwise write a cursor into the future and
/// stop seeing the other parent's changes, with no error anywhere. `lastID`
/// breaks ties so rows sharing a timestamp across a page boundary are neither
/// skipped nor fetched twice.
@Model
final class SyncCursor {
    var entityTypeRaw: String = ""
    var lastUpdatedAt: Date?
    var lastID: UUID?
    var lastSyncedAt: Date?

    init(entityType: SyncEntity) {
        self.entityTypeRaw = entityType.rawValue
    }

    var entityType: SyncEntity {
        get { SyncEntity(rawValue: entityTypeRaw) ?? .child }
        set { entityTypeRaw = newValue.rawValue }
    }
}

// MARK: - Entity catalogue

enum SyncEntity: String, CaseIterable, Sendable {
    case familyProfile = "family_profiles"
    case child = "children"
    case task = "requirement_tasks"
    case document = "document_items"
    case receipt = "receipts"
    case note = "child_notes"

    var table: String { rawValue }

    /// Pull order. Parents before children, so a document never lands before
    /// the task it hangs off. The family profile leads because the rules engine
    /// reads it, and a plan generated from a half-arrived profile would be
    /// wrong for exactly as long as the pull took.
    static var pullOrder: [SyncEntity] {
        [.familyProfile, .child, .task, .document, .receipt, .note]
    }

    /// Whether two queued writes to the same row may collapse into one. False
    /// for anything that is a record of an event rather than a state.
    var isCoalescable: Bool {
        switch self {
        case .receipt: return false
        default: return true
        }
    }
}

// MARK: - Recording a local write

/// The four columns every syncable row carries, plus the table it belongs to.
///
/// Exists so that recording a local write is one call that cannot be got half
/// right. Repeating "set `isDirty`, bump `updatedAt`, queue the right
/// `SyncEntity`" at every call site is a silent failure mode: the row looks
/// saved, renders everywhere, and simply never leaves the phone.
protocol SyncableRecord: AnyObject {
    var id: UUID { get }
    var groupID: UUID? { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var isDirty: Bool { get set }
    static var syncEntity: SyncEntity { get }
}

extension FamilyProfile: SyncableRecord { static var syncEntity: SyncEntity { .familyProfile } }
extension Child: SyncableRecord { static var syncEntity: SyncEntity { .child } }
extension RequirementTask: SyncableRecord { static var syncEntity: SyncEntity { .task } }
extension DocumentItem: SyncableRecord { static var syncEntity: SyncEntity { .document } }
extension Receipt: SyncableRecord { static var syncEntity: SyncEntity { .receipt } }
extension ChildNote: SyncableRecord { static var syncEntity: SyncEntity { .note } }

@MainActor
extension SyncableRecord {
    /// Call after any local create or edit. Saves the row before queueing it so
    /// a fast sync cannot read the old value or miss a just-inserted row. Safe
    /// before the install has a family: the entry waits in the outbox and
    /// drains after adoption.
    ///
    /// `updatedAt` is bumped here even though the server owns the column on the
    /// way back in, because `isRealConflict` compares the two: without a local
    /// bump, the other parent's edit made *before* yours still reads as newer
    /// and flags a conflict that never happened.
    func recordLocalChange(in context: ModelContext) {
        updatedAt = Date()
        isDirty = true
        try? context.save()
        SyncCoordinator.shared.enqueue(Self.syncEntity, id: id)
    }

    /// Deletes by tombstone, never by removing the row.
    ///
    /// The row has to survive locally until the outbox pushes it: the push
    /// reads the row to build the DTO, so a row deleted outright can never be
    /// sent, and the delete would live and die on this one phone while the
    /// other parent keeps seeing a task that was dismissed. `markSynced` clears
    /// it out once the server has it.
    func tombstone(in context: ModelContext) {
        deletedAt = Date()
        recordLocalChange(in: context)
    }
}
