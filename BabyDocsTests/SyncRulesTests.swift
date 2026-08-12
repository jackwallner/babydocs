import Foundation
import Testing

@testable import BabyDocs

/// The merge rule, the invite parser and the deterministic id, all of which are
/// pure and none of which can be exercised against a live backend in any
/// deterministic way.
struct SyncRulesTests {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    // MARK: - Task merge

    @Test("A clean local row always takes the server copy")
    func cleanRowTakesServer() {
        #expect(RequirementTaskMerge.resolve(
            localDirty: false, localUpdated: later, localCompletedAt: nil,
            serverUpdated: earlier, serverCompletedAt: nil
        ) == .takeServer)
    }

    @Test("An unsent local edit with nothing to compare against stands")
    func unsentEditWins() {
        #expect(RequirementTaskMerge.resolve(
            localDirty: true, localUpdated: later, localCompletedAt: nil,
            serverUpdated: nil, serverCompletedAt: nil
        ) == .keepLocal)
    }

    @Test("Both parents ticking the same task off is agreement, not conflict")
    func doubleCompletionIsNotAConflict() {
        // The likeliest collision in the whole app. Flagging it would train
        // people to ignore the flag.
        #expect(RequirementTaskMerge.resolve(
            localDirty: true, localUpdated: earlier, localCompletedAt: earlier,
            serverUpdated: later, serverCompletedAt: later
        ) == .takeServer)
    }

    @Test("Two people editing the same task in different directions is a conflict")
    func genuineDisagreementConflicts() {
        #expect(RequirementTaskMerge.resolve(
            localDirty: true, localUpdated: earlier, localCompletedAt: nil,
            serverUpdated: later, serverCompletedAt: nil
        ) == .conflict)
    }

    @Test("A newer local edit beats an older server row")
    func newerLocalWins() {
        #expect(RequirementTaskMerge.resolve(
            localDirty: true, localUpdated: later, localCompletedAt: nil,
            serverUpdated: earlier, serverCompletedAt: nil
        ) == .keepLocal)
    }

    // MARK: - Child merge

    @Test("A stale server child never overwrites a newer local edit")
    func staleServerChildLoses() {
        // The bug: the old rule only asked whether the *server* was newer, and
        // wrote the server row in every other branch. A birth date corrected
        // offline was replaced by the stale copy on the next pull, before the
        // correction had ever been pushed.
        #expect(ChildMerge.resolve(
            localDirty: true, localUpdated: later, serverUpdated: earlier
        ) == .keepLocal)
    }

    @Test("A newer server child lands on a clean local row")
    func cleanChildTakesServer() {
        #expect(ChildMerge.resolve(
            localDirty: false, localUpdated: earlier, serverUpdated: later
        ) == .takeServer)
        // Including when the server row is older: a clean row has nothing to
        // lose, and the server is where both phones agree.
        #expect(ChildMerge.resolve(
            localDirty: false, localUpdated: later, serverUpdated: earlier
        ) == .takeServer)
    }

    @Test("A newer server edit against an unsent local edit goes to a human")
    func childDisagreementConflicts() {
        #expect(ChildMerge.resolve(
            localDirty: true, localUpdated: earlier, serverUpdated: later
        ) == .conflict)
    }

    @Test("Two dirty copies with the same timestamp are not agreement")
    func childTiesConflict() {
        #expect(ChildMerge.resolve(
            localDirty: true, localUpdated: earlier, serverUpdated: earlier
        ) == .conflict)
    }

    @Test("An unsent local child with nothing to compare against stands")
    func unsentChildWins() {
        #expect(ChildMerge.resolve(
            localDirty: true, localUpdated: earlier, serverUpdated: nil
        ) == .keepLocal)
    }

    @Test("A server tombstone cannot delete a newer local child")
    func tombstoneCannotBeatANewerEdit() {
        // A deletion arrives as a row with `deleted_at` set, so it is subject to
        // the same comparison. `keepLocal` is what stops `modelContext.delete`
        // from being reached at all.
        #expect(ChildMerge.resolve(
            localDirty: true, localUpdated: later, serverUpdated: earlier
        ) != .takeServer)
    }

    // MARK: - Deterministic ids

    @Test("The same namespace and name always give the same id")
    func v5IsStable() {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let first = DeterministicID.v5(namespace: namespace, name: "task:ssn_card")
        let second = DeterministicID.v5(namespace: namespace, name: "task:ssn_card")
        #expect(first == second)
    }

    @Test("A v5 id is well formed")
    func v5IsRFC4122() {
        let id = DeterministicID.v5(namespace: UUID(), name: "anything")
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        #expect(bytes[6] & 0xF0 == 0x50)
        #expect(bytes[8] & 0xC0 == 0x80)
    }

    // MARK: - Invite links

    @Test("A dictated code survives spaces, dashes and lower case")
    func normalizationIsForgiving() {
        #expect(InviteLink.normalized("h7k-2m 9qb") == "H7K2M9QB")
        #expect(InviteLink.normalized("H7K2M9QB") == "H7K2M9QB")
        #expect(InviteLink.normalized("short") == nil)
        #expect(InviteLink.normalized("waytoolongacode") == nil)
    }

    @Test("A code is read back out of either address")
    func codeRoundTrips() {
        let code = "H7K2M9QB"
        let web = InviteLink.webURL(code: code)!
        let app = InviteLink.appURL(code: code)!
        #expect(InviteLink.code(from: web) == code)
        #expect(InviteLink.code(from: app) == code)
    }

    @Test("An unrelated link carries no code")
    func unrelatedLinksAreIgnored() {
        #expect(InviteLink.code(from: URL(string: "https://example.com/?code=H7K2M9QB")!) == nil)
        #expect(InviteLink.code(from: URL(string: "babydocs://settings?code=H7K2M9QB")!) == nil)
    }

    @Test("The invitation message carries a web link, not only the app scheme")
    func messageLeadsWithTheWebLink() {
        // A phone without the app cannot open babydocs://, and a desktop mail
        // client will not even draw it as a link. The person most likely to be
        // invited is exactly the one who has installed nothing.
        let text = InviteMessage.text(code: "H7K2M9QB", role: .parent, childName: "Rosa")
        #expect(text.contains("https://"))
        #expect(!text.contains("babydocs://"))
        #expect(text.contains("H7K2M9QB"))
    }

    @Test("A mail URL escapes the body's own query string")
    func mailtoEscapesTheBody() {
        let url = InviteMessage.emailURL(
            address: "sam+baby@example.com",
            code: "H7K2M9QB",
            role: .parent,
            childName: "Rosa"
        )
        #expect(url != nil)
        // The body contains a URL with its own `?` and `=`, and the address
        // contains a `+`. A mail client is entitled to read any of them as a
        // delimiter unless they are escaped.
        let string = url!.absoluteString
        #expect(string.contains("sam%2Bbaby%40example.com"))
        #expect(!string.dropFirst("mailto:".count).contains("?code="))
    }

    @Test("An invalid address produces no mail URL")
    func invalidEmailIsRefused() {
        #expect(InviteMessage.emailURL(address: "not an address", code: "H7K2M9QB", role: .parent, childName: nil) == nil)
        #expect(!InviteLink.isValidEmail(""))
        #expect(InviteLink.isValidEmail("sam@example.com"))
    }

    // MARK: - Sync coordinator reporting

    @MainActor
    @Test("A failed cycle never reports itself as synced")
    func failedCycleIsNotSynced() {
        // The rule most likely to hide a dead sync: advancing `lastSyncedAt` on
        // anything that was not an outright network failure makes a totally
        // broken sync read "Last synced: just now" on every pass forever.
        let coordinator = SyncCoordinator.shared
        var outcome = SyncEngine.Outcome()
        outcome.failure = "The server refused the change."
        coordinator.apply(outcome, now: Date())
        #expect(coordinator.lastSyncedAt == nil)
        #expect(coordinator.lastError != nil)
    }
}
