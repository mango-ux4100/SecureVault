import Foundation
import CryptoKit
import SwiftUI

@Observable
class VaultStore {
    var entries: [VaultEntry] = []
    var syncManager = SyncManager()

    private var masterKey: SymmetricKey?

    private let entriesFileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("vault_entries.json")
    }()

    /// Call this right after successful PIN unlock — it derives the keys
    /// and loads + decrypts entries into memory.
    func unlock(withPIN pin: String) -> Bool {
        let pinDerivedKey = CryptoManager.shared.deriveKey(fromPIN: pin)
        guard let key = CryptoManager.shared.getMasterKey(pinDerivedKey: pinDerivedKey) else {
            return false // wrong PIN
        }
        masterKey = key
        loadEntries()
        return true
    }

    /// Clears the key from memory — call this on lock/background.
    func lock() {
        masterKey = nil
        entries = []
    }

    func addEntry(title: String, secretValue: String) {
        guard let key = masterKey else { return }
        guard let encrypted = CryptoManager.shared.encrypt(secretValue, using: key) else { return }

        let entry = VaultEntry(title: title, encryptedValue: encrypted)
        entries.append(entry)
        saveEntries()
    }

    func decryptedValue(for entry: VaultEntry) -> String {
        guard let key = masterKey else { return "🔒 Locked" }
        return CryptoManager.shared.decrypt(entry.encryptedValue, using: key) ?? "⚠️ Decryption failed"
    }

    func deleteEntry(_ entry: VaultEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    // MARK: - Persistence (entries are stored encrypted, safe to keep as a file)

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: entriesFileURL)
    }

    private func loadEntries() {
        guard let data = try? Data(contentsOf: entriesFileURL),
              let decoded = try? JSONDecoder().decode([VaultEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    // MARK: - Sync

    /// Pushes local entries to the remote store, pulls + merges remote
    /// changes, and updates `entries` with the reconciled result.
    /// Entries are already encrypted at rest, so this never sends
    /// plaintext anywhere — the "remote" only ever sees ciphertext.
    func performSync() async {
        let records = entries.map { entry in
            SyncRecord(
                id: entry.id,
                title: entry.title,
                encryptedValue: entry.encryptedValue,
                dateModified: entry.dateCreated
            )
        }

        let mergedRecords = await syncManager.sync(localRecords: records)

        let mergedEntries = mergedRecords.map { record in
            VaultEntry(
                id: record.id,
                title: record.title,
                encryptedValue: record.encryptedValue,
                dateCreated: record.dateModified
            )
        }

        await MainActor.run {
            self.entries = mergedEntries
            self.saveEntries()
        }
    }

    #if DEBUG
    /// DEBUG ONLY — simulates a second device pushing a new record
    /// directly to the mock cloud, without touching local entries.
    /// Lets you test merge/conflict logic on a single device by writing
    /// straight to whatever container the app is CURRENTLY running in —
    /// no path-hunting in Finder/Terminal required, since hardcoded
    /// paths break every time Xcode reinstalls into a new container.
    func debugSimulateRemoteEntry(title: String = "FakeRemoteEntry") async {
        let fakeRecord = SyncRecord(
            id: UUID(),
            title: title,
            encryptedValue: "debug-fake-not-real-ciphertext",
            dateModified: Date(), // "now" — always newer than existing local entries
            isDeleted: false
        )
        try? await syncManager.debugPushDirectlyToRemote(fakeRecord)
        print("🧪 DEBUG: pushed fake remote record '\(title)' directly to mock cloud")
    }

    /// DEBUG ONLY — simulates a SECOND DEVICE editing one of your EXISTING
    /// entries with a newer timestamp. This is the actual conflict case:
    /// same id on both sides, different content, different dateModified.
    /// After calling this, tap sync — the entry's title in your vault
    /// should change to the "(edited remotely)" version, proving
    /// last-write-wins picked the newer record correctly.
    func debugSimulateConflictingEdit() async {
        guard let firstEntry = entries.first else {
            print("🧪 DEBUG: no existing entry to conflict with — add one first")
            return
        }

        let conflictingRecord = SyncRecord(
            id: firstEntry.id, // SAME id — this is what makes it a conflict
            title: firstEntry.title + " (edited remotely)",
            encryptedValue: firstEntry.encryptedValue, // unchanged ciphertext is fine for this test
            dateModified: Date().addingTimeInterval(60), // 60s in the future — guaranteed newer
            isDeleted: false
        )
        try? await syncManager.debugPushDirectlyToRemote(conflictingRecord)
        print("🧪 DEBUG: pushed conflicting edit for '\(firstEntry.title)' with a newer timestamp")
    }
    #endif
}
