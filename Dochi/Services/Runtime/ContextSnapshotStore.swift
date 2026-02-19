import Foundation
import os

// MARK: - ContextSnapshotStore

/// In-memory store for context snapshots, keyed by snapshotRef.
///
/// Snapshots are stored after building and retrieved by the runtime
/// via `context.resolve` RPC or direct access. Entries expire after
/// a configurable TTL to prevent unbounded memory growth.
@MainActor
final class ContextSnapshotStore {

    /// Maximum number of snapshots to keep in memory.
    private let maxEntries: Int

    /// Time-to-live for each snapshot entry.
    private let ttl: TimeInterval

    /// Stored snapshots keyed by snapshotRef (= snapshotId).
    private var entries: [String: Entry] = [:]

    struct Entry {
        let snapshot: ContextSnapshot
        let storedAt: Date
    }

    init(maxEntries: Int = 50, ttl: TimeInterval = 3600) {
        self.maxEntries = maxEntries
        self.ttl = ttl
    }

    // MARK: - Store / Retrieve

    /// Store a snapshot, returning its snapshotRef.
    @discardableResult
    func store(_ snapshot: ContextSnapshot) -> String {
        evictExpired()

        // If at capacity, evict oldest
        if entries.count >= maxEntries {
            let oldest = entries.min(by: { $0.value.storedAt < $1.value.storedAt })
            if let key = oldest?.key {
                entries.removeValue(forKey: key)
                Log.runtime.debug("Snapshot store evicted oldest: \(key)")
            }
        }

        entries[snapshot.snapshotRef] = Entry(snapshot: snapshot, storedAt: Date())
        Log.runtime.debug("Snapshot stored: \(snapshot.snapshotRef)")
        return snapshot.snapshotRef
    }

    /// Retrieve a snapshot by its ref.
    func resolve(_ snapshotRef: String) -> ContextSnapshot? {
        guard let entry = entries[snapshotRef] else { return nil }

        // Check TTL
        if Date().timeIntervalSince(entry.storedAt) > ttl {
            entries.removeValue(forKey: snapshotRef)
            Log.runtime.debug("Snapshot expired: \(snapshotRef)")
            return nil
        }

        return entry.snapshot
    }

    /// Remove a specific snapshot.
    func remove(_ snapshotRef: String) {
        entries.removeValue(forKey: snapshotRef)
    }

    /// Remove all snapshots for a given workspace.
    func removeAll(workspaceId: String) {
        let keys = entries.filter { $0.value.snapshot.workspaceId == workspaceId }.map(\.key)
        for key in keys {
            entries.removeValue(forKey: key)
        }
    }

    /// Current number of stored snapshots.
    var count: Int { entries.count }

    /// All stored snapshot refs.
    var allRefs: [String] { Array(entries.keys) }

    // MARK: - Serialization (for runtime lazy loading)

    /// Serialize a snapshot to JSON data for transmission to the runtime.
    static func serialize(_ snapshot: ContextSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    /// Deserialize a snapshot from JSON data.
    static func deserialize(_ data: Data) throws -> ContextSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContextSnapshot.self, from: data)
    }

    // MARK: - Private

    private func evictExpired() {
        let now = Date()
        let expired = entries.filter { now.timeIntervalSince($0.value.storedAt) > ttl }
        for key in expired.keys {
            entries.removeValue(forKey: key)
        }
        if !expired.isEmpty {
            Log.runtime.debug("Evicted \(expired.count) expired snapshots")
        }
    }
}
