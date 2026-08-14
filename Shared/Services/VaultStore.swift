import Foundation
import LocalAuthentication
import OSLog
import UIKit

/// Where photographs of a family's documents live, and the only code in this app
/// allowed to read one.
///
/// Three properties hold the whole promise on the App Store page, and each is
/// enforced here rather than by convention:
///
/// 1. **Complete file protection.** Every image is written with
///    `.completeFileProtection`, so the bytes are unreadable while the phone is
///    locked. That is stronger than the SwiftData store, which has to stay
///    readable for background reminder scheduling. Nothing in the vault runs in
///    the background, so nothing needs the weaker class.
/// 2. **Excluded from every backup.** The vault directory is marked
///    `isExcludedFromBackup`, so the images never enter an iCloud or Finder
///    backup. This is the one real cost to the user, and the app says so out
///    loud before the first sensitive photo rather than in a settings screen
///    nobody opens: a new phone starts with an empty vault.
/// 3. **No path leaves this type.** Callers get a `UIImage` or nothing. There is
///    deliberately no API here that returns a `URL`, because a URL is the thing
///    a share sheet, an exporter or a future well-meaning feature would need in
///    order to put a Social Security card somewhere it must never go.
///    `PlanExporter` cannot reach an image even by accident, and a test asserts
///    the export never mentions a vault filename.
@MainActor
@Observable
final class VaultStore {
    static let shared = VaultStore()

    /// Whether the vault has been unlocked in this session. Reset when the app
    /// leaves the foreground, so handing the phone over between two
    /// appointments does not hand the documents over with it.
    private(set) var isUnlocked = false
    private(set) var lastError: String?

    private let log = Logger(subsystem: "com.jackwallner.babydocs", category: "vault")

    private init() {}

    // MARK: - Unlocking

    /// Whether the device can do biometrics or a passcode at all. False on a
    /// phone with no passcode set, where the honest answer is to let the vault
    /// open: there is nothing to gate against that the device itself is not
    /// already giving away.
    var canAuthenticate: Bool {
        var error: NSError?
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// `.deviceOwnerAuthentication`, not `.deviceOwnerAuthenticationWithBiometrics`,
    /// so a passcode works when Face ID fails. That happens constantly in the
    /// situation this app is built for: lying sideways in a dark nursery, or
    /// wearing a mask in a paediatrician's waiting room. A vault that cannot be
    /// opened at the counter is a vault nobody puts anything in.
    func unlock(reason: String = "Unlock your document vault") async -> Bool {
        if isUnlocked { return true }
        guard canAuthenticate else {
            isUnlocked = true
            return true
        }
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isUnlocked = ok
            lastError = nil
            return ok
        } catch {
            log.info("vault unlock declined")
            return false
        }
    }

    func lock() {
        isUnlocked = false
    }

    // MARK: - Reading and writing

    /// Writes a photograph and returns the filename to store on the model.
    ///
    /// JPEG at 0.8 rather than the original data: a document photo is read, not
    /// enlarged, and an unbounded burst of 12-megapixel HEICs in a directory
    /// excluded from backups is a way to fill a phone with something the user
    /// cannot find. The long edge is capped for the same reason.
    func addPage(_ image: UIImage) throws -> String {
        let scaled = Self.downscaled(image, maxEdge: 2400)
        guard let data = scaled.jpegData(compressionQuality: 0.8) else {
            throw VaultError.couldNotEncode
        }
        let name = "\(UUID().uuidString).jpg"
        let url = try directory().appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return name
    }

    func image(named name: String) -> UIImage? {
        guard let url = try? directory().appendingPathComponent(name),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func removePage(named name: String) {
        guard let url = try? directory().appendingPathComponent(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes the files behind a tombstoned document. Called explicitly rather
    /// than on a schedule: a tombstone in this app is recoverable, and a sweeper
    /// that removed the images would make it recoverable in name only.
    func removePages(named names: [String]) {
        for name in names { removePage(named: name) }
    }

    /// Total bytes on disk, for the line in Settings. A vault is the one part of
    /// this app that can grow without the user noticing.
    func totalBytes() -> Int64 {
        guard let dir = try? directory(),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey]
              ) else { return 0 }
        return contents.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }

    // MARK: - Location on disk

    private func directory() throws -> URL {
        let manager = FileManager.default
        let base = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var dir = base.appendingPathComponent("Vault", isDirectory: true)
        if !manager.fileExists(atPath: dir.path) {
            try manager.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        // Re-applied every time rather than only at creation. A directory that
        // loses this flag starts riding along in every backup silently, and the
        // only symptom is a promise on the App Store page quietly becoming
        // untrue.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

enum VaultError: LocalizedError {
    case couldNotEncode

    var errorDescription: String? {
        switch self {
        case .couldNotEncode: return "That photo could not be saved."
        }
    }
}
