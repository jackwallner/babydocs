import CryptoKit
import Foundation

/// Name-based UUIDs, for the rows two devices have to agree on without talking
/// to each other first.
///
/// Rows a person creates can use a random UUID, because only one device ever
/// creates them and the id then travels with the row. Generated rows cannot:
/// both parents' phones run `RequirementEngine` independently, often before
/// either has signed in, and with random ids that produces two copies of every
/// task in the plan the moment they join the same family. Deriving the id from
/// what actually makes a task unique (the child, plus the catalog key) makes the
/// second device's write an ordinary idempotent upsert instead.
enum DeterministicID {
    /// RFC 4122 §4.3, version 5 (SHA-1). Chosen over v3/MD5 for no reason
    /// beyond convention: nothing here is a security boundary, the hash only
    /// has to be stable across devices and OS versions, which SHA-1 is.
    static func v5(namespace: UUID, name: String) -> UUID {
        var input = Data()
        withUnsafeBytes(of: namespace.uuid) { input.append(contentsOf: $0) }
        input.append(contentsOf: Array(name.utf8))

        var digest = Array(Insecure.SHA1.hash(data: input).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50  // version 5
        digest[8] = (digest[8] & 0x3F) | 0x80  // RFC 4122 variant

        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
