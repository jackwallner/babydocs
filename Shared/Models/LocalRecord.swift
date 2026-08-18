import Foundation
import OSLog
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

/// What a failed write is allowed to do, which is not "nothing".
///
/// Every save in this app was `try? context.save()`. On a local-only app that is
/// not a cache miss, it is the only copy: a parent ticks the birth certificate
/// off, watches the row move to Done, closes the app, and finds out weeks later
/// that the disk was full and the tick was never written. The UI had already
/// told them otherwise, which is the part that makes it a trust failure rather
/// than a bug.
///
/// One reporter, read by `RootView`, so the message arrives wherever the write
/// happened rather than needing an error path threaded through forty call sites.
@MainActor
@Observable
final class SaveFailureReporter {
    static let shared = SaveFailureReporter()

    /// The last write that did not land, phrased for a person. Nil when the
    /// store is behaving.
    private(set) var message: String?

    private let log = Logger(subsystem: "com.jackwallner.babydocs", category: "store")

    private init() {}

    /// Deliberately does not name the record. The message is shown in an alert,
    /// an alert can be screenshotted into a support email, and a child's name in
    /// a diagnostic is a small leak this app has no reason to take.
    func report(_ error: Error) {
        log.error("Local save failed: \(error.localizedDescription, privacy: .public)")
        message = """
        Your last change could not be saved to this phone, so what you are \
        looking at may not survive closing the app. This is usually storage \
        being full. Free some space and make the change again.
        """
    }

    func clear() { message = nil }
}

@MainActor
extension LocalRecord {
    /// Call after any local create or edit.
    @discardableResult
    func recordLocalChange(in context: ModelContext) -> Bool {
        updatedAt = Date()
        do {
            try context.save()
            return true
        } catch {
            // SwiftData can leave the object graph mutated after a failed save.
            // Roll back the unsaved graph before the alert appears, so the row
            // cannot look completed, deleted or edited when disk rejected it.
            context.rollback()
            SaveFailureReporter.shared.report(error)
            return false
        }
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

@MainActor
extension Child {
    /// Removes an unconfirmed draft that the app created as scaffolding. It is
    /// not family work yet, so retaining it as an archived record would create
    /// a false child the next time the app opened.
    func discardEphemeral(in context: ModelContext) {
        context.delete(self)
        do {
            try context.save()
        } catch {
            SaveFailureReporter.shared.report(error)
        }
    }
}
