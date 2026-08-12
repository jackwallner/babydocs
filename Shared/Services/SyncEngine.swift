import Foundation
import OSLog
import SwiftData

/// Two-way sync between the local SwiftData store and Postgres.
///
/// The store is the source of truth for *reading*. Sync writes into it and never
/// sits in front of it, so every screen renders from local data whether or not
/// the network is there. That ordering is the whole reason the document
/// checklist works at a records office counter.
///
/// A `@ModelActor` because `ModelContext` is not `Sendable` and must not be
/// touched from more than one isolation domain. Everything crossing in or out of
/// this actor is a plain `Sendable` DTO, never a `@Model` instance.
@ModelActor
actor SyncEngine {
    private var log: Logger { Logger(subsystem: "com.jackwallner.babydocs", category: "sync") }

    private static let pageSize = 200
    private static let maxAttempts = 6

    /// Result of one full cycle, for the UI to report without needing details.
    struct Outcome: Sendable, Equatable {
        var pulled = 0
        var pushed = 0
        var conflicts = 0
        var needsReview = 0
        var wasOffline = false
        /// The first thing that went wrong, already phrased for a person. Nil
        /// means the cycle actually completed, which is the only condition under
        /// which anything may claim the app is synced.
        var failure: String?

        var isComplete: Bool { failure == nil }
    }

    // MARK: - Entry point

    func sync(remote: any SyncRemote, groupID: UUID) async -> Outcome {
        var outcome = Outcome()

        // Pull and push are two independent halves, not a sequence. Sharing one
        // `do` means a single failing table throws out of the pull and the push
        // is never attempted at all, so a document ticked at a counter sits in
        // the outbox forever because an unrelated table was having a bad day. A
        // queued write has to leave the phone regardless.
        let pull = await pullAll(remote: remote)
        outcome.pulled = pull.applied
        record(pull.failure, into: &outcome)

        do {
            let pushResult = try await pushOutbox(remote: remote, groupID: groupID)
            outcome.pushed = pushResult.pushed
            outcome.needsReview = pushResult.needsReview
            // A queue where every entry was refused is not a completed cycle,
            // however calmly `pushOutbox` returned from it.
            if outcome.failure == nil { outcome.failure = pushResult.failure }
        } catch {
            record(error, into: &outcome)
        }

        outcome.conflicts = conflictCount()
        return outcome
    }

    /// Folds a failure into the outcome, keeping the first one. Logging here
    /// rather than at each call site so no failure path can forget to.
    private func record(_ error: Error?, into outcome: inout Outcome) {
        guard let error else { return }
        if let syncError = error as? SyncError {
            if case .offline = syncError { outcome.wasOffline = true }
            log.notice("Sync stopped: \(String(describing: syncError))")
        } else {
            log.error("Sync failed: \(error.localizedDescription)")
        }
        if outcome.failure == nil { outcome.failure = Self.describe(error) }
    }

    private static func describe(_ error: Error) -> String {
        guard let syncError = error as? SyncError else { return error.localizedDescription }
        switch syncError {
        case .offline: return "No connection."
        case .rejected(let message), .server(let message):
            return message.isEmpty ? "The server refused the change." : message
        }
    }

    // MARK: - Pull

    private struct PullResult {
        var applied = 0
        var failure: Error?
    }

    private func pullAll(remote: any SyncRemote) async -> PullResult {
        var result = PullResult()
        for entity in SyncEntity.pullOrder {
            do {
                result.applied += try await pull(entity: entity, remote: remote)
            } catch {
                // Caught per entity, deliberately. One table the server is
                // refusing today must not stop the others from arriving, and
                // must not take the push down with it. The failure is still
                // carried out so nothing reports a healthy sync.
                if result.failure == nil { result.failure = error }
                log.error("Pull failed for \(entity.rawValue): \(String(describing: error))")
            }
        }
        try? modelContext.save()
        return result
    }

    private func pull(entity: SyncEntity, remote: any SyncRemote) async throws -> Int {
        var applied = 0
        var page = cursorPage(for: entity)

        // Keep asking until a short page proves we reached the end. A full page
        // never means "done", even if the next one turns out empty.
        while true {
            let batch: [any SyncDTO]
            switch entity {
            case .familyProfile:
                batch = try await remote.pull(FamilyProfileDTO.self, after: page, limit: Self.pageSize)
            case .child:
                batch = try await remote.pull(ChildDTO.self, after: page, limit: Self.pageSize)
            case .task:
                batch = try await remote.pull(RequirementTaskDTO.self, after: page, limit: Self.pageSize)
            case .document:
                batch = try await remote.pull(DocumentItemDTO.self, after: page, limit: Self.pageSize)
            case .receipt:
                batch = try await remote.pull(ReceiptDTO.self, after: page, limit: Self.pageSize)
            case .note:
                batch = try await remote.pull(ChildNoteDTO.self, after: page, limit: Self.pageSize)
            }

            if batch.isEmpty { break }

            for dto in batch {
                apply(dto)
                applied += 1
            }

            if let last = batch.last, let updatedAt = last.updated_at {
                page = SyncPage(updatedAt: updatedAt, id: last.id)
                // Advanced only from the server's own `updated_at`. Using the
                // device clock here would let a phone that is a few minutes
                // fast write a cursor into the future and stop seeing the other
                // parent's changes, silently and permanently.
                setCursor(entity: entity, page: page)
            }

            if batch.count < Self.pageSize { break }
        }

        return applied
    }

    // MARK: - Applying a pulled row

    private func apply(_ dto: any SyncDTO) {
        switch dto {
        case let dto as FamilyProfileDTO: applyProfile(dto)
        case let dto as ChildDTO: applyChild(dto)
        case let dto as RequirementTaskDTO: applyTask(dto)
        case let dto as DocumentItemDTO: applyDocument(dto)
        case let dto as ReceiptDTO: applyReceipt(dto)
        case let dto as ChildNoteDTO: applyNote(dto)
        default: break
        }
    }

    /// The conflict rule for records where two people can plausibly disagree.
    ///
    /// If this device has unsent changes and the server has newer ones, keep the
    /// local copy, leave it dirty, and flag it, so a human decides. Silently
    /// discarding either side is never acceptable for something a parent typed.
    private func isRealConflict(localDirty: Bool, localUpdated: Date, serverUpdated: Date?) -> Bool {
        guard let serverUpdated else { return false }
        return localDirty && serverUpdated > localUpdated
    }

    /// The conflict rule for records where the later write is simply the right
    /// answer.
    ///
    /// Last-writer-wins is only last-writer-wins if the two writes are actually
    /// compared. Taking the pulled row unconditionally is pull-clobbers-local,
    /// not LWW: because a cycle pulls before it pushes, an edit made a minute
    /// ago would be discarded the moment any older row for that id came down.
    private func shouldKeepLocal(localDirty: Bool, localUpdated: Date, serverUpdated: Date?) -> Bool {
        guard localDirty else { return false }
        // An unsent local edit with nothing to compare against is the only write
        // we know about, so it stands and the outbox pushes it.
        guard let serverUpdated else { return true }
        return localUpdated > serverUpdated
    }

    /// The household answers. A state, not an event, so the later write wins:
    /// the only realistic collision is both parents completing the same intake
    /// on the same evening, and they are answering the same questions.
    private func applyProfile(_ dto: FamilyProfileDTO) {
        var descriptor = FetchDescriptor<FamilyProfile>()
        descriptor.fetchLimit = 1
        let existing = (try? modelContext.fetch(descriptor))?.first

        let profile = existing ?? {
            let new = FamilyProfile(id: dto.id)
            modelContext.insert(new)
            return new
        }()

        if shouldKeepLocal(localDirty: profile.isDirty,
                           localUpdated: profile.updatedAt,
                           serverUpdated: dto.updated_at) { return }

        profile.id = dto.id
        profile.groupID = dto.family_id
        profile.residenceStateCode = dto.residence_state
        profile.parentageRaw = dto.parentage
        profile.secondParentOnRecord = dto.second_parent_on_record
        profile.insuranceKindRaw = dto.insurance_kind
        profile.employerPlanName = dto.employer_plan_name
        profile.hasDependentCareFSA = dto.has_dependent_care_fsa
        profile.wantsPassport = dto.wants_passport
        profile.wants529 = dto.wants_529
        profile.wantsTrumpAccount = dto.wants_trump_account
        profile.takingParentalLeave = dto.taking_parental_leave
        profile.updatedAt = dto.updated_at ?? Date()
        profile.isDirty = false
    }

    /// The child's own facts drive every generated deadline, so a silent
    /// overwrite here would silently move dates. Flagged, not merged.
    private func applyChild(_ dto: ChildDTO) {
        let id = dto.id
        let existing = fetchOne(Child.self, #Predicate { $0.id == id })

        if let existing {
            switch ChildMerge.resolve(
                localDirty: existing.isDirty,
                localUpdated: existing.updatedAt,
                serverUpdated: dto.updated_at
            ) {
            case .keepLocal:
                // An unsent local edit that is newer than what came down. The
                // row stays dirty and its outbox entry stays queued.
                return
            case .conflict:
                flagConflict(entity: .child, id: dto.id)
                return
            case .takeServer:
                break
            }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            write(dto, into: existing)
        } else {
            guard dto.deleted_at == nil else { return }
            let child = Child(name: dto.name, birthDate: dto.birth_date)
            child.id = dto.id
            write(dto, into: child)
            modelContext.insert(child)
        }
    }

    private func write(_ dto: ChildDTO, into child: Child) {
        child.name = dto.name
        child.birthDate = dto.birth_date
        child.birthStateCode = dto.birth_state
        child.birthCounty = dto.birth_county
        child.isUSCitizen = dto.is_us_citizen
        child.ssnStatusRaw = dto.ssn_status
        child.ssnReceivedAt = dto.ssn_received_at
        child.birthCertificateReceivedAt = dto.birth_certificate_received_at
        child.certifiedCopiesOnHand = dto.certified_copies_on_hand
        child.colorIndex = dto.color_index
        child.notes = dto.notes
        child.groupID = dto.family_id
        child.updatedAt = dto.updated_at ?? Date()
        child.isDirty = false
    }

    /// Tasks use `RequirementTaskMerge`, not flat LWW. Both parents ticking off
    /// the same errand is agreement rather than conflict, while two people
    /// editing the same task's notes in different directions is a real
    /// disagreement and goes to a human.
    private func applyTask(_ dto: RequirementTaskDTO) {
        let id = dto.id
        let existing = fetchOne(RequirementTask.self, #Predicate { $0.id == id })

        if let existing {
            switch RequirementTaskMerge.resolve(
                localDirty: existing.isDirty,
                localUpdated: existing.updatedAt,
                localCompletedAt: existing.completedAt,
                serverUpdated: dto.updated_at,
                serverCompletedAt: dto.completed_at
            ) {
            case .keepLocal:
                return
            case .conflict:
                flagConflict(entity: .task, id: dto.id)
                return
            case .takeServer:
                break
            }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            write(dto, into: existing)
        } else {
            guard dto.deleted_at == nil else { return }
            let task = RequirementTask(title: dto.title)
            task.id = dto.id
            write(dto, into: task)
            let childID = dto.child_id
            task.child = fetchOne(Child.self, #Predicate { $0.id == childID })
            modelContext.insert(task)
        }
    }

    private func write(_ dto: RequirementTaskDTO, into task: RequirementTask) {
        task.catalogKey = dto.catalog_key
        task.title = dto.title
        task.detail = dto.detail
        task.categoryRaw = dto.category
        task.dueAt = dto.due_at
        task.deadlineKindRaw = dto.deadline_kind
        task.deadlineBasis = dto.deadline_basis
        task.officialURLString = dto.official_url
        task.officialLinkLabel = dto.official_link_label
        task.sourceURLString = dto.source_url
        task.sourceVerifiedOn = dto.source_verified_on
        task.assigneeUserID = dto.assignee_user_id
        task.assigneeName = dto.assignee_name
        task.completedAt = dto.completed_at
        task.completedByName = dto.completed_by_name
        task.dismissedAt = dto.dismissed_at
        task.parentNotes = dto.parent_notes
        task.sortWeight = dto.sort_weight
        task.isCustom = dto.is_custom
        task.groupID = dto.family_id
        task.updatedAt = dto.updated_at ?? Date()
        task.isDirty = false
    }

    /// A ticked document is the same shape of agreement a completed task is:
    /// two parents finding the same certificate is not a disagreement. Flat LWW
    /// with a real comparison.
    private func applyDocument(_ dto: DocumentItemDTO) {
        let id = dto.id
        let existing = fetchOne(DocumentItem.self, #Predicate { $0.id == id })
        if let existing, shouldKeepLocal(localDirty: existing.isDirty,
                                         localUpdated: existing.updatedAt,
                                         serverUpdated: dto.updated_at) { return }
        if let existing, dto.deleted_at != nil {
            modelContext.delete(existing)
            return
        }
        guard dto.deleted_at == nil else { return }
        let item = existing ?? {
            let new = DocumentItem(title: dto.title)
            new.id = dto.id
            let taskID = dto.task_id
            new.task = fetchOne(RequirementTask.self, #Predicate { $0.id == taskID })
            modelContext.insert(new)
            return new
        }()
        item.catalogKey = dto.catalog_key
        item.title = dto.title
        item.detail = dto.detail
        item.isOnHand = dto.is_on_hand
        item.markedOnHandAt = dto.marked_on_hand_at
        item.sortWeight = dto.sort_weight
        item.groupID = dto.family_id
        item.updatedAt = dto.updated_at ?? Date()
        item.isDirty = false
    }

    /// A receipt is an event, not a state. Two devices recording the same
    /// submission is a duplicate to collapse, not a conflict to resolve, and
    /// there is deliberately no conflict flag here.
    private func applyReceipt(_ dto: ReceiptDTO) {
        let id = dto.id
        if let existing = fetchOne(Receipt.self, #Predicate { $0.id == id }) {
            if shouldKeepLocal(localDirty: existing.isDirty,
                               localUpdated: existing.updatedAt,
                               serverUpdated: dto.updated_at) { return }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            existing.kindRaw = dto.kind
            existing.value = dto.value
            existing.recordedByName = dto.recorded_by_name
            existing.groupID = dto.family_id
            existing.updatedAt = dto.updated_at ?? Date()
            existing.isDirty = false
        } else {
            guard dto.deleted_at == nil else { return }
            let receipt = Receipt(value: dto.value, recordedAt: dto.recorded_at)
            receipt.id = dto.id
            receipt.kindRaw = dto.kind
            receipt.recordedByName = dto.recorded_by_name
            receipt.groupID = dto.family_id
            receipt.updatedAt = dto.updated_at ?? Date()
            receipt.isDirty = false
            let taskID = dto.task_id
            receipt.task = fetchOne(RequirementTask.self, #Predicate { $0.id == taskID })
            modelContext.insert(receipt)
        }
    }

    /// Free text two people can plausibly disagree about, so this flags rather
    /// than merges. A note is one field end to end: silently taking the server
    /// copy does not lose a detail, it loses the whole thing someone typed.
    private func applyNote(_ dto: ChildNoteDTO) {
        let id = dto.id
        let existing = fetchOne(ChildNote.self, #Predicate { $0.id == id })

        if let existing {
            if isRealConflict(localDirty: existing.isDirty,
                              localUpdated: existing.updatedAt,
                              serverUpdated: dto.updated_at) {
                flagConflict(entity: .note, id: dto.id)
                return
            }
            if shouldKeepLocal(localDirty: existing.isDirty,
                               localUpdated: existing.updatedAt,
                               serverUpdated: dto.updated_at) { return }
            if dto.deleted_at != nil {
                modelContext.delete(existing)
                return
            }
            write(dto, into: existing)
        } else {
            guard dto.deleted_at == nil else { return }
            let note = ChildNote()
            note.id = dto.id
            write(dto, into: note)
            let childID = dto.child_id
            note.child = fetchOne(Child.self, #Predicate { $0.id == childID })
            modelContext.insert(note)
        }
    }

    private func write(_ dto: ChildNoteDTO, into note: ChildNote) {
        note.title = dto.title
        note.body = dto.body
        note.isPinned = dto.is_pinned
        note.createdByName = dto.created_by_name
        note.groupID = dto.family_id
        note.updatedAt = dto.updated_at ?? Date()
        note.isDirty = false
    }

    // MARK: - Push

    struct PushResult: Sendable {
        var pushed = 0
        var needsReview = 0
        /// The first entry-level rejection. `pushOutbox` swallows these by
        /// design, because one bad row must not stop the rest of the queue, but
        /// swallowing them silently is how a cycle where nothing was accepted
        /// still reports itself as a successful sync.
        var failure: String?
    }

    private func pushOutbox(remote: any SyncRemote, groupID: UUID) async throws -> PushResult {
        var result = PushResult()
        let now = Date()
        let entries = (try? modelContext.fetch(FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.statusRaw != "needsReview" && $0.notBefore <= now },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []

        // Coalesce. Several queued edits to the same task collapse into one
        // upsert because only the final state reaches the server anyway.
        // Receipts never collapse: each is a separate thing that happened, and
        // merging them would erase a confirmation number from the record.
        var seen = Set<String>()
        var work: [OutboxEntry] = []
        for entry in entries {
            let key = "\(entry.entityTypeRaw):\(entry.entityID)"
            if entry.entityType.isCoalescable {
                if seen.contains(key) {
                    modelContext.delete(entry)
                    continue
                }
                seen.insert(key)
            }
            work.append(entry)
        }

        for entry in work {
            do {
                try await push(entry: entry, remote: remote, groupID: groupID)
                markSynced(entry)
                modelContext.delete(entry)
                result.pushed += 1
            } catch let error as SyncError {
                switch error {
                case .offline:
                    // Leave it queued exactly as it is and stop: the rest will
                    // fail the same way and hammering a dead network wastes
                    // battery on a phone that may be someone's only one.
                    try? modelContext.save()
                    throw error
                case .rejected(let message), .server(let message):
                    entry.attempts += 1
                    entry.lastError = message
                    if result.failure == nil { result.failure = Self.describe(error) }
                    if case .rejected = error {
                        // Almost always a role that changed while this device
                        // was offline. Retrying would never succeed and would
                        // hide the reason, so a person is told instead.
                        entry.status = .needsReview
                        result.needsReview += 1
                    } else if entry.attempts >= Self.maxAttempts {
                        entry.status = .needsReview
                        result.needsReview += 1
                    } else {
                        entry.status = .retrying
                        entry.notBefore = Date().addingTimeInterval(
                            pow(2, Double(entry.attempts)) * 5
                        )
                    }
                }
            }
        }

        try? modelContext.save()
        return result
    }

    private func push(entry: OutboxEntry, remote: any SyncRemote, groupID: UUID) async throws {
        let id = entry.entityID
        // An entry queued under a different family than the one signed in now
        // must never be written under this one. The way a device reaches this is
        // ordinary: queue a write offline, leave the family, join another, come
        // back online. Refused rather than retried, because retrying cannot make
        // it right and the row would land in the wrong household.
        if let queued = entry.groupID, queued != groupID {
            throw SyncError.rejected(
                "This change was made in a different family and was not sent."
            )
        }
        switch entry.entityType {
        case .familyProfile:
            guard let profile = fetchOne(FamilyProfile.self, #Predicate { $0.id == id }) else { return }
            try requireOwnership(of: profile, by: groupID)
            try await remote.push([FamilyProfileDTO(
                id: profile.id, family_id: groupID,
                residence_state: profile.residenceStateCode,
                parentage: profile.parentageRaw,
                second_parent_on_record: profile.secondParentOnRecord,
                insurance_kind: profile.insuranceKindRaw,
                employer_plan_name: profile.employerPlanName,
                has_dependent_care_fsa: profile.hasDependentCareFSA,
                wants_passport: profile.wantsPassport,
                wants_529: profile.wants529,
                wants_trump_account: profile.wantsTrumpAccount,
                taking_parental_leave: profile.takingParentalLeave,
                updated_at: nil, deleted_at: profile.deletedAt
            )])

        case .child:
            guard let child = fetchOne(Child.self, #Predicate { $0.id == id }) else { return }
            try requireOwnership(of: child, by: groupID)
            try await remote.push([ChildDTO(
                id: child.id, family_id: groupID, name: child.name,
                birth_date: child.birthDate, birth_state: child.birthStateCode,
                birth_county: child.birthCounty, is_us_citizen: child.isUSCitizen,
                ssn_status: child.ssnStatusRaw, ssn_received_at: child.ssnReceivedAt,
                birth_certificate_received_at: child.birthCertificateReceivedAt,
                certified_copies_on_hand: child.certifiedCopiesOnHand,
                color_index: child.colorIndex, notes: child.notes,
                updated_at: nil, deleted_at: child.deletedAt
            )])

        case .task:
            guard let task = fetchOne(RequirementTask.self, #Predicate { $0.id == id }),
                  let childID = task.child?.id else { return }
            try requireOwnership(of: task, by: groupID)
            try await remote.push([RequirementTaskDTO(
                id: task.id, family_id: groupID, child_id: childID,
                catalog_key: task.catalogKey, title: task.title, detail: task.detail,
                category: task.categoryRaw, due_at: task.dueAt,
                deadline_kind: task.deadlineKindRaw, deadline_basis: task.deadlineBasis,
                official_url: task.officialURLString,
                official_link_label: task.officialLinkLabel,
                source_url: task.sourceURLString, source_verified_on: task.sourceVerifiedOn,
                assignee_user_id: task.assigneeUserID, assignee_name: task.assigneeName,
                completed_at: task.completedAt, completed_by_name: task.completedByName,
                dismissed_at: task.dismissedAt, parent_notes: task.parentNotes,
                sort_weight: task.sortWeight, is_custom: task.isCustom,
                updated_at: nil, deleted_at: task.deletedAt
            )])

        case .document:
            guard let item = fetchOne(DocumentItem.self, #Predicate { $0.id == id }),
                  let taskID = item.task?.id else { return }
            try requireOwnership(of: item, by: groupID)
            try await remote.push([DocumentItemDTO(
                id: item.id, family_id: groupID, task_id: taskID,
                catalog_key: item.catalogKey, title: item.title, detail: item.detail,
                is_on_hand: item.isOnHand, marked_on_hand_at: item.markedOnHandAt,
                sort_weight: item.sortWeight,
                updated_at: nil, deleted_at: item.deletedAt
            )])

        case .receipt:
            guard let receipt = fetchOne(Receipt.self, #Predicate { $0.id == id }),
                  let taskID = receipt.task?.id else { return }
            try requireOwnership(of: receipt, by: groupID)
            try await remote.push([ReceiptDTO(
                id: receipt.id, family_id: groupID, task_id: taskID,
                kind: receipt.kindRaw, value: receipt.value,
                recorded_at: receipt.recordedAt, recorded_by_name: receipt.recordedByName,
                updated_at: nil, deleted_at: receipt.deletedAt
            )])

        case .note:
            guard let note = fetchOne(ChildNote.self, #Predicate { $0.id == id }),
                  let childID = note.child?.id else { return }
            try requireOwnership(of: note, by: groupID)
            try await remote.push([ChildNoteDTO(
                id: note.id, family_id: groupID, child_id: childID,
                title: note.title, body: note.body, is_pinned: note.isPinned,
                created_by_name: note.createdByName,
                updated_at: nil, deleted_at: note.deletedAt
            )])
        }
    }

    /// Refuses to send a row that belongs to another family.
    ///
    /// The DTO's family id used to come from whichever family happened to be
    /// active, never from the row, so a row retained across a family switch
    /// would have been rewritten into the new household on its way out.
    private func requireOwnership<T: SyncableRecord>(of row: T, by groupID: UUID) throws {
        // A nil owner is a local-only row that has not been adopted yet, which
        // is the ordinary state before a family exists. Adoption stamps it.
        guard let owner = row.groupID, owner != groupID else { return }
        throw SyncError.rejected("This change belongs to a different family and was not sent.")
    }

    private func markSynced(_ entry: OutboxEntry) {
        let id = entry.entityID
        switch entry.entityType {
        case .familyProfile: settle(fetchOne(FamilyProfile.self, #Predicate { $0.id == id }))
        case .child: settle(fetchOne(Child.self, #Predicate { $0.id == id }))
        case .task: settle(fetchOne(RequirementTask.self, #Predicate { $0.id == id }))
        case .document: settle(fetchOne(DocumentItem.self, #Predicate { $0.id == id }))
        case .receipt: settle(fetchOne(Receipt.self, #Predicate { $0.id == id }))
        case .note: settle(fetchOne(ChildNote.self, #Predicate { $0.id == id }))
        }
    }

    /// Clears the dirty flag, and clears the row itself out once a tombstone has
    /// reached the server. Local deletes keep the row alive only so the push has
    /// something to read (`SyncableRecord.tombstone`); holding it any longer
    /// would grow the store forever with rows nothing renders.
    private func settle<T: PersistentModel & SyncableRecord>(_ record: T?) {
        guard let record else { return }
        record.isDirty = false
        if record.deletedAt != nil { modelContext.delete(record) }
    }

    // MARK: - Queueing

    /// Called by the UI layer after any local change.
    func enqueue(entity: SyncEntity, id: UUID, groupID: UUID?) {
        modelContext.insert(OutboxEntry(entityType: entity, entityID: id, groupID: groupID))
        try? modelContext.save()
    }

    /// Adoption of a local-only install into a freshly created family: stamp the
    /// family onto every existing row and queue it. No dedicated server RPC,
    /// because the client UUIDs are already the server primary keys, so this is
    /// just the ordinary write path and inherits its idempotency and its
    /// resumability for free.
    func adoptLocalData(into groupID: UUID) {
        // Every syncable table. A receipt or a note left behind here is
        // invisibly local forever: nothing later marks it dirty, so it never
        // reaches the parent who just joined.
        func adopt<T: PersistentModel & SyncableRecord>(_ type: T.Type) {
            let rows = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
            for row in rows {
                if row.groupID == nil {
                    row.groupID = groupID
                    row.isDirty = true
                }
                modelContext.insert(
                    OutboxEntry(entityType: T.syncEntity, entityID: row.id, groupID: groupID)
                )
            }
        }

        adopt(FamilyProfile.self)
        adopt(Child.self)
        adopt(RequirementTask.self)
        adopt(DocumentItem.self)
        adopt(Receipt.self)
        adopt(ChildNote.self)

        try? modelContext.save()
    }

    // MARK: - Conflicts

    func conflictCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.statusRaw == "needsReview" }
        ))) ?? 0
    }

    private func flagConflict(entity: SyncEntity, id: UUID) {
        let existing = (try? modelContext.fetch(FetchDescriptor<OutboxEntry>(
            predicate: #Predicate { $0.entityID == id }
        ))) ?? []
        if let first = existing.first {
            first.status = .needsReview
            first.lastError = "Someone else changed this while you were offline."
        } else {
            let entry = OutboxEntry(entityType: entity, entityID: id, groupID: nil)
            entry.status = .needsReview
            entry.lastError = "Someone else changed this while you were offline."
            modelContext.insert(entry)
        }
    }

    // MARK: - Cursors

    private func cursorPage(for entity: SyncEntity) -> SyncPage? {
        guard let cursor = cursor(for: entity),
              let updatedAt = cursor.lastUpdatedAt,
              let id = cursor.lastID else { return nil }
        return SyncPage(updatedAt: updatedAt, id: id)
    }

    private func setCursor(entity: SyncEntity, page: SyncPage?) {
        let record = cursor(for: entity) ?? {
            let new = SyncCursor(entityType: entity)
            modelContext.insert(new)
            return new
        }()
        record.lastUpdatedAt = page?.updatedAt
        record.lastID = page?.id
        record.lastSyncedAt = Date()
    }

    private func cursor(for entity: SyncEntity) -> SyncCursor? {
        let raw = entity.rawValue
        return (try? modelContext.fetch(FetchDescriptor<SyncCursor>(
            predicate: #Predicate { $0.entityTypeRaw == raw }
        )))?.first
    }

    // MARK: - Helpers

    private func fetchOne<T: PersistentModel>(
        _ type: T.Type,
        _ predicate: Predicate<T>
    ) -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}

// MARK: - Child merge rule

/// The merge rule for the row every deadline in the app is computed from.
///
/// The bug this type exists to make impossible: a pull used to treat "the server
/// is not newer" as "no conflict" and then write the server row anyway, so a name
/// or a birth date corrected offline five minutes ago was silently replaced by
/// the stale copy that came down on the next cycle. Because the cycle pulls
/// before it pushes, the correction never left the phone at all.
///
/// Every timestamp relation is now named, and only one of them writes.
enum ChildMerge {
    enum Resolution: Equatable {
        case takeServer
        case keepLocal
        case conflict
    }

    static func resolve(
        localDirty: Bool,
        localUpdated: Date,
        serverUpdated: Date?
    ) -> Resolution {
        // Nothing unsent here: the server row is simply the newer truth, and
        // that includes a tombstone.
        guard localDirty else { return .takeServer }
        // An unsent edit with nothing to compare against is the only write we
        // know about.
        guard let serverUpdated else { return .keepLocal }
        if localUpdated > serverUpdated { return .keepLocal }
        // Equal timestamps with two dirty copies is not agreement, it is two
        // writes we cannot order. A person decides.
        return .conflict
    }
}

// MARK: - Task merge rule

/// The merge rule for the one entity where "done" is the field two people race
/// on.
///
/// Both parents ticking off the same errand is agreement, not conflict, and
/// flagging it would train them to ignore the flag. Two people editing the same
/// task's notes in opposite directions is a real disagreement and goes to a
/// human. Kept out of `SyncEngine` and free of SwiftData so the whole rule is a
/// table of one-line tests.
enum RequirementTaskMerge {
    enum Resolution: Equatable {
        case takeServer
        case keepLocal
        case conflict
    }

    static func resolve(
        localDirty: Bool,
        localUpdated: Date,
        localCompletedAt: Date?,
        serverUpdated: Date?,
        serverCompletedAt: Date?
    ) -> Resolution {
        guard localDirty else { return .takeServer }
        guard let serverUpdated else { return .keepLocal }

        // Both sides say it is done. That is two people agreeing, whatever
        // order the writes landed in, so the family converges on the server's
        // copy rather than being asked to resolve a disagreement they did not
        // have. Which of the two completion timestamps survives does not
        // matter: the task is done either way.
        if localCompletedAt != nil && serverCompletedAt != nil { return .takeServer }

        if localUpdated > serverUpdated { return .keepLocal }
        return .conflict
    }
}
