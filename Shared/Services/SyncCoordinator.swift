import Foundation
import OSLog
import SwiftData
import Supabase

/// Drives the `SyncEngine` from the UI layer and owns the enqueue side of the
/// outbox.
///
/// Foreground-only by design. iOS grants background refresh unpredictably, so
/// anything that has to be reliable is a local notification scheduled ahead of
/// time (`DeadlineReminderScheduler`). Sync is neither: it is allowed to be
/// late, as long as it is never lossy.
@MainActor
@Observable
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    private(set) var lastOutcome: SyncEngine.Outcome?
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false
    private(set) var conflictCount = 0
    /// Why the last cycle did not finish, or nil if it did. Nothing reads this
    /// on the way to rendering the plan: it is reported after the fact, in
    /// Settings, and never sits in front of a deadline.
    private(set) var lastError: String?

    /// The network was the problem, rather than the server. Worth separating,
    /// because "you are offline" is a normal state this app is built for and
    /// "the server refused" is not.
    private(set) var isOffline = false

    private let log = Logger(subsystem: "com.jackwallner.babydocs", category: "sync")
    private let engine = SyncEngine(modelContainer: BabyModelStore.sharedModelContainer)

    private var auth: AuthService { .shared }
    private var families: FamilyService { .shared }

    private init() {}

    /// A local change that has to reach the other parent. Safe to call for rows
    /// that have no family yet: they queue, and the queue drains after adoption.
    func enqueue(_ entity: SyncEntity, id: UUID) {
        let groupID = families.activeGroupID
        Task { await engine.enqueue(entity: entity, id: id, groupID: groupID) }
    }

    func syncNow() async {
        guard !isSyncing else { return }
        guard SupabaseConfig.isConfigured else { return }
        guard auth.isSignedIn, let groupID = families.activeGroupID else { return }

        isSyncing = true
        defer { isSyncing = false }

        let remote = SupabaseSyncRemote(client: auth.client, groupID: groupID)
        let outcome = await engine.sync(remote: remote, groupID: groupID)
        apply(outcome)
    }

    /// Folds one cycle's result into the published state.
    ///
    /// Split out of `syncNow` and left non-private on purpose: this is the rule
    /// most likely to hide a total sync failure, and it needs to be testable
    /// without a container, a network or a signed-in user.
    func apply(_ outcome: SyncEngine.Outcome, now: Date = Date()) {
        lastOutcome = outcome
        conflictCount = outcome.conflicts
        lastError = outcome.failure
        isOffline = outcome.wasOffline

        // Only a cycle that actually completed. Advancing this on anything that
        // was not an outright network failure is how a dead sync reports "Last
        // synced: just now" on every pass, on every device, forever.
        if outcome.isComplete { lastSyncedAt = now }

        log.info("Sync: pulled \(outcome.pulled), pushed \(outcome.pushed), review \(outcome.needsReview), failure \(outcome.failure ?? "none")")
    }

    /// One-time adoption of a local-only install into a freshly created family.
    func adoptLocalData(into groupID: UUID) async {
        await engine.adoptLocalData(into: groupID)
        await syncNow()
    }
}
