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
        log.error("Local save failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
        // The tick has already animated back out by the time the alert is drawn,
        // and a row that quietly un-ticks itself reads as the app losing the tap.
        // The buzz is what says "that failed" in the moment the finger is still
        // on the glass, before anybody has read a word of the alert.
        Haptics.failed()
        message = """
        Your last change could not be saved to this phone, so what you are \
        looking at may not survive closing the app. This is usually storage \
        being full. Free some space and make the change again.
        """
    }

    func reportSensitiveText() {
        log.error("Rejected sensitive text in a local record")
        Haptics.failed()
        message = "That text looks like a Social Security number. Baby Docs never needs the number, so it was not saved. Use the status or a non-sensitive reference instead."
    }

    func clear() { message = nil }
}

@MainActor
extension LocalRecord {
    /// Call after any local create or edit.
    @discardableResult
    func recordLocalChange(in context: ModelContext) -> Bool {
        updatedAt = Date()
        guard !containsSensitiveText else {
            redactSensitiveText()
            context.rollback()
            redactSensitiveText()
            SaveFailureReporter.shared.reportSensitiveText()
            return false
        }
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

    /// The shared persistence boundary uses the same check as an individual
    /// record save. Keeping it visible here prevents a bulk reconciliation from
    /// becoming a way around the rule.
    var containsSensitiveText: Bool {
        switch self {
        case let profile as FamilyProfile:
            return [profile.employerPlanName, profile.benefitsContactNote]
                .contains(where: PlanSeed.containsSocialSecurityNumber)
        case let child as Child:
            return [child.name, child.birthCounty, child.notes]
                .contains(where: PlanSeed.containsSocialSecurityNumber)
        case let task as RequirementTask:
            return [
                task.title, task.detail, task.deadlineBasis, task.assigneeName,
                task.completedByName, task.parentNotes
            ].contains(where: PlanSeed.containsSocialSecurityNumber)
        case let receipt as Receipt:
            return [receipt.value, receipt.recordedByName]
                .contains(where: PlanSeed.containsSocialSecurityNumber)
        case let note as ChildNote:
            return [note.title, note.body, note.createdByName]
                .contains(where: PlanSeed.containsSocialSecurityNumber)
        case let document as VaultDocument:
            return [document.customTitle, document.notes]
                .contains(where: PlanSeed.containsSocialSecurityNumber)
        default:
            return false
        }
    }

    /// Rollback does not reliably restore an edited SwiftData object in memory
    /// when the object was inserted or changed through a binding. Redact after
    /// the rollback as well, so a later unrelated save can never write the
    /// rejected value.
    func redactSensitiveText() {
        switch self {
        case let profile as FamilyProfile:
            profile.employerPlanName = PlanSeed.safeExternalText(profile.employerPlanName)
            profile.benefitsContactNote = PlanSeed.safeExternalText(profile.benefitsContactNote)
        case let child as Child:
            child.name = PlanSeed.safeExternalText(child.name)
            child.birthCounty = PlanSeed.safeExternalText(child.birthCounty)
            child.notes = PlanSeed.safeExternalText(child.notes)
        case let task as RequirementTask:
            task.title = PlanSeed.safeExternalText(task.title)
            task.detail = PlanSeed.safeExternalText(task.detail)
            task.deadlineBasis = PlanSeed.safeExternalText(task.deadlineBasis)
            task.assigneeName = PlanSeed.safeExternalText(task.assigneeName)
            task.completedByName = PlanSeed.safeExternalText(task.completedByName)
            task.parentNotes = PlanSeed.safeExternalText(task.parentNotes)
        case let document as DocumentItem:
            document.title = PlanSeed.safeExternalText(document.title)
            document.detail = PlanSeed.safeExternalText(document.detail)
        case let receipt as Receipt:
            receipt.value = PlanSeed.safeExternalText(receipt.value)
            receipt.recordedByName = PlanSeed.safeExternalText(receipt.recordedByName)
        case let note as ChildNote:
            note.title = PlanSeed.safeExternalText(note.title)
            note.body = PlanSeed.safeExternalText(note.body)
            note.createdByName = PlanSeed.safeExternalText(note.createdByName)
        case let document as VaultDocument:
            document.customTitle = PlanSeed.safeExternalText(document.customTitle)
            document.notes = PlanSeed.safeExternalText(document.notes)
        default:
            break
        }
    }

    /// Deletes by tombstone, never by removing the row.
    ///
    /// Reads go through `liveTasks` and friends, so a tombstoned row is gone
    /// from every list the moment this is called. It stays in the store because
    /// the alternative is that a mis-swipe at 3am destroys the confirmation
    /// number for a birth certificate that took a fortnight to arrive.
    @discardableResult
    func tombstone(in context: ModelContext) -> Bool {
        deletedAt = Date()
        return recordLocalChange(in: context)
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
            context.rollback()
            SaveFailureReporter.shared.report(error)
        }
    }
}
