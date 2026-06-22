
import Foundation

/// A single vault entry as it travels over sync — same encrypted shape
/// as VaultEntry, plus metadata needed to resolve conflicts between
/// two devices that changed things independently.
struct SyncRecord: Codable, Identifiable {
    var id: UUID
    var title: String
    var encryptedValue: String
    var dateModified: Date
    var isDeleted: Bool = false  // tombstone, so deletes can sync too
}

/// Abstraction over "wherever the encrypted vault data is synced."
/// VaultStore/SyncManager talk to this protocol only — they never know
/// if they're hitting a local mock, CloudKit, or anything else. This is
/// what makes swapping in real CloudKit later a contained change instead
/// of a rewrite.
protocol SyncProvider {
    /// Push local records up to the remote store.
    func upload(_ records: [SyncRecord]) async throws

    /// Pull whatever the remote store currently has.
    func fetchRemoteRecords() async throws -> [SyncRecord]
}
