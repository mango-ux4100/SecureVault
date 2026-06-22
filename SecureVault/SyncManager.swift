import Foundation
import SwiftUI

/// Coordinates syncing VaultStore's entries with a remote SyncProvider.
/// Conflict strategy: last-write-wins, decided per-record by comparing
/// `dateModified`. This is the same approach CloudKit's own default
/// conflict resolution uses — simple, predictable, and appropriate for
/// single-user data where two "users" are really just the same person's
/// two devices, not concurrent collaborators.
@Observable
class SyncManager {
    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var syncError: String?

    private let provider: SyncProvider

    init(provider: SyncProvider = MockCloudProvider()) {
        self.provider = provider
    }

    /// Full sync cycle: pull remote changes, merge with local, push the
    /// merged result back up. Returns the merged record set so VaultStore
    /// can update its in-memory entries.
    func sync(localRecords: [SyncRecord]) async -> [SyncRecord] {
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let remoteRecords = try await provider.fetchRemoteRecords()
            let merged = mergeRecords(local: localRecords, remote: remoteRecords)

            // Push the merged result back up so both "sides" converge,
            // not just our local copy.
            try await provider.upload(merged)

            lastSyncDate = Date()
            return merged.filter { !$0.isDeleted }
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
            return localRecords // fall back to local-only on failure
        }
    }

    /// Merges two record sets by id, keeping whichever version of each
    /// record has the more recent `dateModified`. Records that exist on
    /// only one side are kept as-is (nothing to conflict with).
    private func mergeRecords(local: [SyncRecord], remote: [SyncRecord]) -> [SyncRecord] {
        var merged: [UUID: SyncRecord] = [:]

        for record in local {
            merged[record.id] = record
        }

        for remoteRecord in remote {
            if let localRecord = merged[remoteRecord.id] {
                // Conflict: same record exists on both sides — keep newer.
                merged[remoteRecord.id] = remoteRecord.dateModified > localRecord.dateModified
                    ? remoteRecord
                    : localRecord
            } else {
                // Only exists remotely — adopt it.
                merged[remoteRecord.id] = remoteRecord
            }
        }

        return Array(merged.values)
    }

    #if DEBUG
    /// DEBUG ONLY — writes a record straight to the remote, bypassing
    /// local state entirely. Used to simulate "what a second device
    /// would have pushed" for testing merge logic on one device.
    func debugPushDirectlyToRemote(_ record: SyncRecord) async throws {
        var existing = try await provider.fetchRemoteRecords()
        existing.append(record)
        try await provider.upload(existing)
    }
    #endif
}
