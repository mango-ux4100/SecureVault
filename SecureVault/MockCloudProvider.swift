import Foundation

/// A local-file stand-in for a real cloud backend (e.g. CloudKit).
/// Lets us build and test sync logic — especially conflict resolution —
/// without needing a paid Apple Developer account or a second device.
///
/// Swapping this for a real CloudKitProvider later only requires writing
/// a new type that conforms to SyncProvider; SyncManager and VaultStore
/// don't change at all.
class MockCloudProvider: SyncProvider {
    private let remoteFileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Deliberately a different file than the local vault, so this
        // genuinely behaves like a separate remote store.
        return dir.appendingPathComponent("mock_cloud_remote.json")
    }()

    func upload(_ records: [SyncRecord]) async throws {
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        var remote = loadRemoteOrEmpty()

        for record in records {
            if let index = remote.firstIndex(where: { $0.id == record.id }) {
                remote[index] = record
            } else {
                remote.append(record)
            }
        }

        let data = try JSONEncoder().encode(remote)
        try data.write(to: remoteFileURL)
        print("☁️ Uploaded \(remote.count) records to mock cloud at \(remoteFileURL.path)")
    }

    func fetchRemoteRecords() async throws -> [SyncRecord] {
        try await Task.sleep(nanoseconds: 300_000_000)
        let records = loadRemoteOrEmpty()
        print("☁️ Fetched \(records.count) records from mock cloud: \(records.map { $0.title })")
        return records
    }

    /// Loads the remote file, but logs the actual error instead of
    /// silently swallowing it — a decode failure here would otherwise
    /// look identical to "no remote data yet," which made earlier
    /// debugging impossible.
    private func loadRemoteOrEmpty() -> [SyncRecord] {
        do {
            let data = try Data(contentsOf: remoteFileURL)
            return try JSONDecoder().decode([SyncRecord].self, from: data)
        } catch {
            print("⚠️ Failed to load/decode mock cloud file: \(error)")
            return []
        }
    }
}
