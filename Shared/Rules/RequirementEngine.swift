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
/// 2. **Row ids are derived, not random.** Both parents' phones generate the
///    same plan offline and then meet on the server, so a random id would
///    produce two rows for one task and an argument about which is real.
///    `DeterministicID` makes the second device's write an idempotent upsert.
/// 3. **A pass that changes nothing writes nothing.** Reconciliation runs on
///    every launch and every profile edit. Bumping `updatedAt` unconditionally
///    would put the whole plan in the outbox each time, and sync would spend
///    its life pushing rows nobody edited.
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
        let existing = Dictionary(
            grouping: child.liveTasks.filter { !$0.catalogKey.isEmpty },
            by: \.catalogKey
        ).compactMapValues(\.first)

        for rule in RequirementCatalog.all {
            let applies = rule.applies(input)
            let row = existing[rule.key]

            switch (applies, row) {
            case (true, .some(let task)):
                if update(task, from: rule, input: input, in: context) { result.updated += 1 }
                result.total += 1

            case (true, .none):
                let task = make(rule: rule, input: input, child: child, in: context)
                context.insert(task)
                task.recordLocalChange(in: context)
                syncDocuments(of: task, to: rule.documents, in: context)
                result.created += 1
                result.total += 1

            case (false, .some(let task)):
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
            wantsTrumpAccount: profile.wantsTrumpAccount,
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
        task.groupID = child.groupID
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
        task.sourceURLString = rule.source.urlString
        task.sourceVerifiedOn = rule.source.verifiedOn
    }

    /// Only the engine-owned fields. Deliberately excludes everything a parent
    /// can edit, so a family's own note never counts as a rule change.
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
        let existing = Dictionary(
            grouping: task.liveDocuments.filter { !$0.catalogKey.isEmpty },
            by: \.catalogKey
        ).compactMapValues(\.first)

        for (index, spec) in specs.enumerated() {
            if let item = existing[spec.key] {
                if item.title != spec.title || item.detail != spec.detail {
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
            item.groupID = task.groupID
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
