import Foundation
import SwiftData

/// Owns the SwiftData container.
///
/// This store is the app's only copy of anything, by design. The scenario the
/// app is built around is a parent standing at a records office counter with one
/// bar of signal who needs to know which three documents the clerk is about to
/// ask for, and nothing in that scenario is improved by a round trip.
///
/// Vault images are the one thing that does **not** live here. They are files in
/// the container under `VaultStore`, held to a stricter protection class than
/// this store can use, and referenced from `VaultDocument` only by name.
///
/// The file is explicitly marked `completeUntilFirstUserAuthentication`:
/// encrypted at rest until the first unlock after boot, and readable thereafter
/// so background sync and notification handling still work. `complete` would be
/// stronger but would make the store unreadable whenever the phone is locked,
/// which breaks exactly the background paths deadline reminders depend on.
enum BabyModelStore {
    static let schema = Schema([
        Child.self,
        FamilyProfile.self,
        RequirementTask.self,
        DocumentItem.self,
        Receipt.self,
        ChildNote.self,
        VaultDocument.self
    ])

    /// Set when the store on disk could not be opened and was moved aside. The
    /// plan on screen is then empty for a reason the parent has to be told
    /// about: an app that silently reopens as a blank household looks like it
    /// deleted the baby, and the parent's real work is still on the disk.
    @MainActor private(set) static var recoveredStoreURL: URL?

    static let sharedModelContainer: ModelContainer = {
        let url = storeURL

        if let container = makeContainer(url: url) {
            return container
        }

        // An unreadable store used to be deleted here and retried. That is
        // survivable while a schema is still moving in development and
        // indefensible in a shipped build: it is a parent's whole plan, and the
        // failure that reaches this line is as likely to be a bad migration or a
        // full disk as a corrupt file. So it is moved aside, never removed, and
        // the app says so.
        let archived = archiveStoreFiles(at: url)

        if let container = makeContainer(url: url) {
            if let archived {
                Task { @MainActor in recoveredStoreURL = archived }
            }
            return container
        }

        let inMemory = ModelConfiguration(
            "BabyDocs",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            fatalError("BabyModelStore could not initialize: \(error)")
        }
    }()

    /// Moves an unreadable store and its sidecars out of the way, keeping every
    /// byte, and returns where they went. Nothing in this app deletes a store
    /// file outside a DEBUG test flag.
    private static func archiveStoreFiles(at url: URL) -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = url
            .deletingLastPathComponent()
            .appendingPathComponent("BabyDocs-unreadable-\(stamp).store")

        var moved: URL?
        for suffix in ["", "wal", "shm"] {
            let source = suffix.isEmpty ? url : url.appendingPathExtension(suffix)
            let target = suffix.isEmpty ? destination : destination.appendingPathExtension(suffix)
            guard manager.fileExists(atPath: source.path) else { continue }
            do {
                try manager.moveItem(at: source, to: target)
                if suffix.isEmpty { moved = target }
            } catch {
                // If it cannot even be moved, leave it alone. A container that
                // fails to build is recoverable; a file destroyed on the way to
                // recovery is not.
                return moved
            }
        }
        return moved
    }

    /// Deletes the store from disk. DEBUG-only, and called from exactly one
    /// place: the `-uitest-wipe-store` launch flag, before the container is
    /// first built. Nothing in a shipped app may reach this.
    #if DEBUG
    static func wipeStoreFilesForTesting() {
        let url = storeURL
        for file in [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")] {
            try? FileManager.default.removeItem(at: file)
        }
    }
    #endif

    /// In-memory container for tests and previews.
    static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(
            "BabyDocsPreview",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not build in-memory container: \(error)")
        }
    }

    private static func makeContainer(url: URL) -> ModelContainer? {
        let config = ModelConfiguration(
            "BabyDocs",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            return nil
        }
        applyFileProtection(to: url)
        return container
    }

    /// Applied to the store and its write-ahead log. Set explicitly rather than
    /// relying on the platform default, and re-applied on every container build
    /// so the wipe-and-retry path above cannot silently recreate the file
    /// without it.
    private static func applyFileProtection(to url: URL) {
        let manager = FileManager.default
        for file in [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")]
        where manager.fileExists(atPath: file.path) {
            try? manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: file.path
            )
        }
    }

    private static var storeURL: URL {
        let manager = FileManager.default
        guard let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return manager.temporaryDirectory.appendingPathComponent("BabyDocs.store")
        }

        // Application Support does not exist on first launch, and CoreData will
        // not create it. Without this the first run logs a wall of sandbox
        // errors and silently falls through to the in-memory store, losing
        // everything the parent enters in that session.
        if !manager.fileExists(atPath: base.path) {
            try? manager.createDirectory(at: base, withIntermediateDirectories: true)
        }

        return base.appendingPathComponent("BabyDocs.store")
    }
}
