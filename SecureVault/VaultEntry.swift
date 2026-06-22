import Foundation

/// A single vault entry. `value` is stored ENCRYPTED on disk —
/// only decrypted into plaintext when displayed in memory.
struct VaultEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String          // e.g. "Gmail" — not sensitive, shown in list
    var encryptedValue: String // the actual secret, encrypted
    var dateCreated: Date = Date()
}
