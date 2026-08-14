import Foundation
import SwiftData

/// The two columns every editable row carries, and the two calls that keep them
/// honest.
///
/// This is what is left of a much larger sync protocol. The app used to push
/// every row to a server, which meant a local write had to set a dirty flag,
/// bump a timestamp and queue an outbox entry, and getting one of the three
/// wrong left a row that looked saved and never left the phone. None of that
/// applies now: the store is the only copy there will ever be.
///
/// The two calls survive because they still earn their place. `updatedAt` orders
/// a child's notes and tells the follow-up tracker how long something has been
/// sitting, and deleting by tombstone means an accidental swipe on a task with
/// six months of receipts attached is recoverable rather than final.
protocol LocalRecord: AnyObject {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

extension FamilyProfile: LocalRecord {}
extension Child: LocalRecord {}
extension RequirementTask: LocalRecord {}
extension DocumentItem: LocalRecord {}
extension Receipt: LocalRecord {}
extension ChildNote: LocalRecord {}
extension VaultDocument: LocalRecord {}

@MainActor
extension LocalRecord {
    /// Call after any local create or edit.
    func recordLocalChange(in context: ModelContext) {
        updatedAt = Date()
        try? context.save()
    }

    /// Deletes by tombstone, never by removing the row.
    ///
    /// Reads go through `liveTasks` and friends, so a tombstoned row is gone
    /// from every list the moment this is called. It stays in the store because
    /// the alternative is that a mis-swipe at 3am destroys the confirmation
    /// number for a birth certificate that took a fortnight to arrive.
    func tombstone(in context: ModelContext) {
        deletedAt = Date()
        recordLocalChange(in: context)
    }
}
