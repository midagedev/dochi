import Foundation

/// File-based session mapping persistence.
///
/// Stores Dochi ↔ SDK session ID mappings so sessions can be resumed
/// after runtime restart. Data is stored as JSON at:
/// `~/Library/Application Support/Dochi/session_mappings.json`
@MainActor
final class SessionMappingService: SessionMappingServiceProtocol {
    private let fileURL: URL
    private var store: SessionMappingStore
    private var lookupIndex: [SessionLookupKey: Int] = [:]

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(baseURL: URL? = nil) {
        let base = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Dochi")
        self.fileURL = base.appendingPathComponent("session_mappings.json")
        self.store = SessionMappingStore()
        load()
    }

    // MARK: - CRUD

    /// Look up an existing active mapping by composite key (deviceId excluded for cross-device resume).
    func findActive(
        workspaceId: String,
        agentId: String,
        conversationId: String
    ) -> SessionMapping? {
        let key = SessionLookupKey(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId
        )
        guard let idx = lookupIndex[key],
              idx < store.mappings.count,
              store.mappings[idx].status == .active
        else { return nil }
        return store.mappings[idx]
    }

    /// Find a mapping by its Dochi session ID.
    func findBySessionId(_ sessionId: String) -> SessionMapping? {
        store.mappings.first { $0.sessionId == sessionId }
    }

    /// Insert a new mapping and persist.
    func insert(_ mapping: SessionMapping) {
        store.mappings.append(mapping)
        rebuildIndex()
        save()
    }

    /// Update the status of a mapping by session ID.
    func updateStatus(sessionId: String, status: SessionMappingStatus) {
        guard let idx = store.mappings.firstIndex(where: { $0.sessionId == sessionId }) else {
            return
        }
        store.mappings[idx].status = status
        store.mappings[idx].lastActiveAt = Date()
        rebuildIndex()
        save()
    }

    /// Update the device ID for a session mapping (cross-device resume).
    ///
    /// Called when a session is resumed from a different device so the mapping
    /// reflects the current device for audit and future lookups.
    func updateDeviceId(sessionId: String, newDeviceId: String) {
        guard let idx = store.mappings.firstIndex(where: { $0.sessionId == sessionId }) else {
            return
        }
        store.mappings[idx].deviceId = newDeviceId
        store.mappings[idx].lastActiveAt = Date()
        save()
    }

    /// Touch the last-active timestamp for a session.
    /// Does not call `rebuildIndex()` since status is unchanged.
    func touch(sessionId: String) {
        guard let idx = store.mappings.firstIndex(where: { $0.sessionId == sessionId }) else {
            return
        }
        store.mappings[idx].lastActiveAt = Date()
        save()
    }

    /// Return all mappings (for session.list).
    var allMappings: [SessionMapping] {
        store.mappings
    }

    /// Return only active mappings.
    var activeMappings: [SessionMapping] {
        store.mappings.filter { $0.status == .active }
    }

    /// Remove closed/interrupted mappings older than the given interval.
    func pruneStale(olderThan interval: TimeInterval = 86400) {
        let cutoff = Date().addingTimeInterval(-interval)
        store.mappings.removeAll { mapping in
            mapping.status != .active && mapping.lastActiveAt < cutoff
        }
        rebuildIndex()
        save()
    }

    // MARK: - Persistence

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            store = SessionMappingStore()
            rebuildIndex()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            store = try Self.decoder.decode(SessionMappingStore.self, from: data)
            Log.runtime.info("Loaded \(self.store.mappings.count) session mapping(s)")
        } catch {
            Log.runtime.error("Failed to load session mappings: \(error.localizedDescription)")
            store = SessionMappingStore()
        }
        rebuildIndex()
    }

    private func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(store)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.runtime.error("Failed to save session mappings: \(error.localizedDescription)")
        }
    }

    private func rebuildIndex() {
        lookupIndex.removeAll()
        for (idx, mapping) in store.mappings.enumerated() where mapping.status == .active {
            lookupIndex[mapping.lookupKey] = idx
        }
    }
}
