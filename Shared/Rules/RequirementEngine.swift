import Foundation
import OSLog
import SwiftData

/// Turns the catalog into the rows the family actually works from.
///
/// Three rules govern everything in here, and all three are load-bearing:
///
/// 1. **The engine owns the rule, the family owns the work.** Title, detail,
///    deadline and links are rewritten on every pass. `completedAt`, the
///    assignee, the receipts, the ticked documents and anything typed by a
///    parent are never touched. A catalog update must be able to fix a wrong
///    deadline without unticking a box someone drove to an office for.
/// 2. **Row ids are derived, not random.** A generated task's id is a hash of
///    (child, catalog key), so one logical task is one row forever. It is what
///    lets a rule that stops applying be *retired* and later restored with the
///    family's ticked documents still attached, rather than reinserted as a
///    duplicate under an id the store already holds.
/// 3. **A pass that changes nothing writes nothing.** Reconciliation runs on
///    every launch and every profile edit, so an unconditional `updatedAt` bump
///    would rewrite the entire plan each time and destroy the ordering that the
///    follow-up tracker and the notes list read.
@MainActor
enum RequirementEngine {
    private static let log = Logger(subsystem: "com.jackwallner.babydocs", category: "rules")

    /// What one pass did. Returned rather than logged only, so the intake flow
    /// can say "18 tasks, 2 with hard deadlines" instead of just appearing.
    struct Result: Equatable {
        var created = 0
        var updated = 0
        var retired = 0
        var total = 0
    }

    // MARK: - Entry point

    @discardableResult
    static func reconcile(
        child: Child,
        profile: FamilyProfile,
        in context: ModelContext,
        now: Date = Date()
    ) -> Result {
        var result = Result()
        let input = makeInput(child: child, profile: profile)
        // Tombstoned rows are included deliberately. The id of a generated task
        // is derived from (child, catalog key), so a rule that becomes
        // inapplicable, is retired, and then applies again would otherwise be
        // inserted a second time under an id the store already holds. One
        // logical task, one row, forever: a retired row is *restored*, never
        // recreated. Insurance switching from employer to Marketplace and back
        // is the ordinary way a family reaches this.
        let existing = Dictionary(
            grouping: (child.tasks ?? []).filter { !$0.catalogKey.isEmpty },
            by: \.catalogKey
        ).compactMapValues { rows in
            rows.first { $0.deletedAt == nil } ?? rows.first
        }

        for rule in RequirementCatalog.all {
            let applies = rule.applies(input)
            let row = existing[rule.key]

            switch (applies, row) {
            case (true, .some(let task)):
                let wasRetired = task.deletedAt != nil
                if wasRetired { restore(task, in: context) }
                if update(task, from: rule, input: input, in: context) || wasRetired {
                    result.updated += 1
                }
                result.total += 1

            case (true, .none):
                let task = make(rule: rule, input: input, child: child, in: context)
                context.insert(task)
                task.recordLocalChange(in: context)
                syncDocuments(of: task, to: rule.documents, in: context)
                result.created += 1
                result.total += 1

            case (false, .some(let task)):
                // Already retired: leave it exactly as it is. Tombstoning a
                // tombstone would rewrite the row on every launch.
                if task.deletedAt != nil { continue }
                // Only retire what the family has not touched. Someone who
                // ticked a document and then corrected an intake answer has
                // still done that work, and silently deleting it is worse than
                // leaving one stale row they can dismiss themselves.
                if hasFamilyWork(task) {
                    result.total += 1
                } else {
                    task.tombstone(in: context)
                    result.retired += 1
                }

            case (false, .none):
                continue
            }
        }

        log.info("Reconciled \(child.displayName): \(result.created) new, \(result.updated) changed, \(result.retired) retired")
        return result
    }

    /// Runs a pass for every child in the store. Called at launch and after any
    /// profile edit, because a household answer ("we moved to Oregon") changes
    /// every child's plan, not just the one on screen.
    @discardableResult
    static func reconcileAll(in context: ModelContext, now: Date = Date()) -> Result {
        let profile = FamilyProfileStore.current(in: context)
        let children = ((try? context.fetch(FetchDescriptor<Child>())) ?? [])
            .filter { $0.deletedAt == nil }

        var combined = Result()
        for child in children {
            let one = reconcile(child: child, profile: profile, in: context, now: now)
            combined.created += one.created
            combined.updated += one.updated
            combined.retired += one.retired
            combined.total += one.total
        }
        return combined
    }

    static func makeInput(child: Child, profile: FamilyProfile) -> RuleInput {
        RuleInput(
            childName: child.name,
            birthDate: child.birthDate,
            birthStateCode: child.birthStateCode,
            isUSCitizen: child.isUSCitizen,
            hasSSN: child.hasSSN,
            ssnStatus: child.ssnStatus,
            hasBirthCertificate: child.birthCertificateReceivedAt != nil,
            residenceStateCode: profile.residenceStateCode,
            parentage: profile.parentage,
            secondParentOnRecord: profile.secondParentOnRecord,
            insuranceKind: profile.insuranceKind,
            hasDependentCareFSA: profile.hasDependentCareFSA,
            wantsPassport: profile.wantsPassport,
            wants529: profile.wants529,
            wantsNewbornAccount: profile.wantsNewbornAccount,
            takingParentalLeave: profile.takingParentalLeave
        )
    }

    // MARK: - Row construction

    static func taskID(childID: UUID, catalogKey: String) -> UUID {
        DeterministicID.v5(namespace: childID, name: "task:\(catalogKey)")
    }

    static func documentID(taskID: UUID, catalogKey: String) -> UUID {
        DeterministicID.v5(namespace: taskID, name: "doc:\(catalogKey)")
    }

    private static func make(
        rule: RequirementRule,
        input: RuleInput,
        child: Child,
        in context: ModelContext
    ) -> RequirementTask {
        let task = RequirementTask(title: rule.title)
        task.id = taskID(childID: child.id, catalogKey: rule.key)
        task.catalogKey = rule.key
        task.child = child
        task.isCustom = false
        applyRule(rule, input: input, to: task)
        return task
    }

    /// Rewrites the engine-owned fields, and returns whether anything moved. The
    /// return value is what keeps a no-op launch out of the outbox.
    @discardableResult
    private static func update(
        _ task: RequirementTask,
        from rule: RequirementRule,
        input: RuleInput,
        in context: ModelContext
    ) -> Bool {
        let before = fingerprint(task)
        applyRule(rule, input: input, to: task)
        let changed = fingerprint(task) != before

        let documentsChanged = syncDocuments(of: task, to: rule.documents, in: context)
        if changed { task.recordLocalChange(in: context) }
        return changed || documentsChanged
    }

    private static func applyRule(_ rule: RequirementRule, input: RuleInput, to task: RequirementTask) {
        let deadline = rule.deadline(input)
        let link = rule.link(input)

        task.title = rule.title
        task.detail = rule.detail(input)
        task.category = rule.category
        task.sortWeight = rule.sortWeight
        task.dueAt = deadline.date
        task.deadlineKind = deadline.kind
        task.deadlineBasis = deadline.basis
        task.officialURLString = link?.urlString ?? ""
        task.officialLinkLabel = link?.label ?? ""
        task.isPostedAway = rule.isPostedAway
        // Empty for a rule that deliberately cites nothing. The task screen says
        // why rather than showing a footnote that quietly is not there.
        task.sourceURLString = rule.source?.urlString ?? ""
        task.sourceVerifiedOn = rule.source?.reviewedOn
    }

    /// Brings a retired row back rather than inserting a second one under the
    /// same derived id. Everything the family did to it is still attached, which
    /// is the point: a parent who switched insurance twice should find their
    /// ticked documents where they left them.
    private static func restore(_ task: RequirementTask, in context: ModelContext) {
        task.deletedAt = nil
        for document in (task.documents ?? []) where document.deletedAt != nil {
            document.deletedAt = nil
            document.recordLocalChange(in: context)
        }
        task.recordLocalChange(in: context)
    }

    /// Only the engine-owned fields. Deliberately excludes everything a parent
    /// can edit, so a family's own note never counts as a rule change.
    ///
    /// `sourceVerifiedOn` is excluded on purpose, and that is a decision rather
    /// than an oversight. The review date is a property of the bundled catalog,
    /// not of the family's row: every device recomputes it from its own build,
    /// so syncing it would put twenty rows per child into the outbox on every
    /// release for a value the other phone already knows. The source *URL* is in
    /// the fingerprint, because that one genuinely changes what the task says.
    private static func fingerprint(_ task: RequirementTask) -> String {
        [
            task.title,
            task.detail,
            task.categoryRaw,
            String(task.sortWeight),
            task.dueAt.map { String($0.timeIntervalSince1970) } ?? "",
            task.deadlineKindRaw,
            task.deadlineBasis,
            task.officialURLString,
            task.officialLinkLabel,
            String(task.isPostedAway),
            task.sourceURLString
        ].joined(separator: "\u{1F}")
    }

    /// Adds any document the catalog gained. Never removes one: a spec that
    /// disappears from the catalog may still be the thing the family already
    /// ticked, and an unexpected extra line costs nothing next to losing that.
    @discardableResult
    private static func syncDocuments(
        of task: RequirementTask,
        to specs: [DocumentSpec],
        in context: ModelContext
    ) -> Bool {
        var changed = false
        // Tombstones included, for the same reason as the task lookup above: a
        // document id is derived from (task, spec key), so a retired row has to
        // be restored rather than inserted again under an id the store holds.
        let existing = Dictionary(
            grouping: (task.documents ?? []).filter { !$0.catalogKey.isEmpty },
            by: \.catalogKey
        ).compactMapValues { rows in
            rows.first { $0.deletedAt == nil } ?? rows.first
        }

        for (index, spec) in specs.enumerated() {
            if let item = existing[spec.key] {
                let wasRetired = item.deletedAt != nil
                if wasRetired { item.deletedAt = nil }
                if wasRetired || item.title != spec.title || item.detail != spec.detail {
                    item.title = spec.title
                    item.detail = spec.detail
                    item.recordLocalChange(in: context)
                    changed = true
                }
                continue
            }
            let item = DocumentItem(title: spec.title)
            item.id = documentID(taskID: task.id, catalogKey: spec.key)
            item.catalogKey = spec.key
            item.detail = spec.detail
            item.sortWeight = index
            item.task = task
            context.insert(item)
            item.recordLocalChange(in: context)
            changed = true
        }
        return changed
    }

    /// Has anyone actually done something with this task? Anything true here
    /// makes the row the family's rather than the engine's.
    private static func hasFamilyWork(_ task: RequirementTask) -> Bool {
        task.completedAt != nil
            || task.dismissedAt != nil
            || !task.assigneeName.isEmpty
            || !task.parentNotes.isEmpty
            || !task.liveReceipts.isEmpty
            || task.liveDocuments.contains(where: \.isOnHand)
    }
}

// MARK: - Profile store

/// The single `FamilyProfile` row, created on demand.
///
/// A separate type only so the "there is exactly one of these" rule lives in one
/// place. Every screen that reads household answers goes through it, so no view
/// has to decide what to do when the row does not exist yet.
@MainActor
enum FamilyProfileStore {
    static func current(in context: ModelContext) -> FamilyProfile {
        var descriptor = FetchDescriptor<FamilyProfile>()
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let profile = FamilyProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }
}
