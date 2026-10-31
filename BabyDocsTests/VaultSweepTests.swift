import Foundation
import Testing

@testable import BabyDocs

/// A photograph no vault entry names may only be swept up when the vault entries
/// are the whole story.
///
/// The sweep ran on every launch against whatever the live store held. When the
/// store on disk cannot be opened it is moved aside and a blank one takes its
/// place, so every photograph looked orphaned and the launch sweep removed the
/// lot, on the same launch whose screen says "Nothing was deleted". The photos
/// are excluded from every backup, so they were not coming back.
@MainActor
struct VaultSweepTests {
    /// A scratch Application Support folder with a vault folder in it.
    private struct Scratch {
        let root: URL
        let vault: URL

        init(photos: [String]) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("vault-sweep-\(UUID().uuidString)", isDirectory: true)
            vault = root.appendingPathComponent("Vault", isDirectory: true)
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            for name in photos {
                try Data("jpeg".utf8).write(to: vault.appendingPathComponent(name))
            }
        }

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: vault.appendingPathComponent(name).path)
        }

        /// What `BabyModelStore` leaves behind when it moves an unreadable store
        /// out of the way.
        func moveStoreAside() throws {
            let name = "\(BabyModelStore.unreadableArchivePrefix)2026-10-31T00-00-00Z.store"
            try Data("sqlite".utf8).write(to: root.appendingPathComponent(name))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("A store that was moved aside leaves the photographs it names alone")
    func recoveredStoreKeepsThePhotographs() throws {
        let scratch = try Scratch(photos: ["front.jpg", "back.jpg"])
        defer { scratch.remove() }
        try scratch.moveStoreAside()

        // The blank store that replaced the unreadable one names nothing.
        let removed = VaultStore(storageRoot: scratch.root).removeOrphanedPages(referencedNames: [])

        #expect(removed == 0, "The launch sweep removed photographs the moved-aside store still names")
        #expect(scratch.exists("front.jpg"))
        #expect(scratch.exists("back.jpg"))
    }

    @Test("The protection outlasts the launch that moved the store aside")
    func archiveStillProtectsOnLaterLaunches() throws {
        // Nothing but the archive file remembers the recovery on the next launch:
        // `recoveredStoreURL` is only set during the launch that did the move.
        let scratch = try Scratch(photos: ["front.jpg"])
        defer { scratch.remove() }
        try scratch.moveStoreAside()
        let store = VaultStore(storageRoot: scratch.root)

        _ = store.removeOrphanedPages(referencedNames: [])
        _ = store.removeOrphanedPages(referencedNames: [])

        #expect(scratch.exists("front.jpg"))
    }

    @Test("A launch that ran on a memory-only store leaves the photographs alone")
    func memoryOnlyStoreKeepsThePhotographs() throws {
        let scratch = try Scratch(photos: ["front.jpg"])
        defer { scratch.remove() }
        BabyModelStore.setInMemoryFallbackForTesting(true)
        defer { BabyModelStore.setInMemoryFallbackForTesting(false) }

        let removed = VaultStore(storageRoot: scratch.root).removeOrphanedPages(referencedNames: [])

        #expect(removed == 0, "The launch sweep ran against a store that was never the family's")
        #expect(scratch.exists("front.jpg"))
    }

    @Test("With a healthy store a photograph no entry names is still removed")
    func healthyStoreStillRemovesOrphans() throws {
        // The sweep exists for a crash between writing a photograph and saving
        // its row. Guarding it must not turn it off.
        let scratch = try Scratch(photos: ["kept.jpg", "orphan.jpg"])
        defer { scratch.remove() }

        let removed = VaultStore(storageRoot: scratch.root).removeOrphanedPages(referencedNames: ["kept.jpg"])

        #expect(removed == 1)
        #expect(scratch.exists("kept.jpg"))
        #expect(!scratch.exists("orphan.jpg"))
    }
}
