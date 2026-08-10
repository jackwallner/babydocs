import Foundation
import SwiftData

/// Owns the SwiftData container.
///
/// This store is the app's source of truth for reading, and that is a deliberate
/// architectural choice rather than a leftover from a local-only version. The
/// scenario the app is built around is a parent standing at a records office
/// counter with one bar of signal who needs to know which three documents the
/// clerk is about to ask for. Cloud sync writes into this store; it never sits
/// in front of it.
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
        Family.self,
        OutboxEntry.self,
        SyncCursor.self
    ])

    static let sharedModelContainer: ModelContainer = {
        let url = storeURL

        if let container = makeContainer(url: url) {
            return container
        }

        // A schema change during development can leave an unreadable store
        // behind. Drop it and retry once before falling back to memory.
        for file in [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")] {
            try? FileManager.default.removeItem(at: file)
        }

        if let container = makeContainer(url: url) {
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
