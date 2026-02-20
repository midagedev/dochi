import Foundation

/// Dedicated actor for session mapping file I/O.
///
/// Isolates all disk reads and writes to a background executor so that
/// `SessionMappingService` (which lives on `@MainActor`) never blocks the
/// main thread with file operations. Encoding and decoding are also performed
/// here because `JSONEncoder`/`JSONDecoder` can be non-trivial for large stores.
actor SessionMappingIO {

    private let fileURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Read and decode the session mapping store from disk.
    /// Returns `nil` if the file does not exist.
    func read() throws -> SessionMappingStore? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(SessionMappingStore.self, from: data)
    }

    /// Encode and write the session mapping store to disk atomically.
    func write(_ store: SessionMappingStore) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - SessionMappingService

/// File-based session mapping persistence with async I/O.
///
/// Stores Dochi <-> SDK session ID mappings so sessions can be resumed
/// after runtime restart. Data is stored as JSON at:
/// `~/Library/Application Support/Dochi/session_mappings.json`
///
/// ## Async I/O Architecture (Issue #298)
///
/// All file I/O is delegated to `SessionMappingIO`, a dedicated background
/// actor that keeps disk operations off the main thread:
///
/// - **Reads** are served from the in-memory `store` (synchronous, zero-cost).
/// - **Writes** are coalesced: each mutation schedules a background save via
///   `scheduleSave()`. If multiple mutations occur within a short window, only
///   the last snapshot is written, reducing unnecessary disk traffic.
/// - **Initial load** is `async` via the `create(baseURL:)` factory method,
///   which reads the file on the IO actor before returning a fully-initialized
///   service. A synchronous `init` is retained for backward compatibility
///   (tests that create ephemeral instances with small or empty stores).
@MainActor
final class SessionMappingService: SessionMappingServiceProtocol {
    private let io: SessionMappingIO
    private var store: SessionMappingStore
    private var lookupIndex: [SessionLookupKey: Int] = [:]

    /// The currently-scheduled coalesced save task, if any.
    private var pendingSaveTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Async factory: loads existing data from disk on a background actor,
    /// then returns a fully-initialized service on the main actor.
    ///
    /// Preferred for production use -- file I/O never touches the main thread.
    static func create(baseURL: URL? = nil) async -> SessionMappingService {
        let fileURL = Self.resolveFileURL(baseURL: baseURL)
        let io = SessionMappingIO(fileURL: fileURL)

        var store = SessionMappingStore()
        do {
            if let loaded = try await io.read() {
                store = loaded
                Log.runtime.info("Loaded \(store.mappings.count) session mapping(s)")
            }
        } catch {
            Log.runtime.error("Failed to load session mappings: \(error.localizedDescription)")
        }
        return SessionMappingService(io: io, store: store)
    }

    /// Synchronous initializer -- retained for backward compatibility and tests.
    ///
    /// Performs a **synchronous** file read on the calling thread. In production,
    /// prefer `SessionMappingService.create(baseURL:)` to keep the main thread free.
    init(baseURL: URL? = nil) {
        let fileURL = Self.resolveFileURL(baseURL: baseURL)
        self.io = SessionMappingIO(fileURL: fileURL)
        self.store = SessionMappingStore()
        loadSync(fileURL: fileURL)
    }

    /// Internal initializer used by the async factory.
    private init(io: SessionMappingIO, store: SessionMappingStore) {
        self.io = io
        self.store = store
        rebuildIndex()
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
        scheduleSave()
    }

    /// Update the status of a mapping by session ID.
    func updateStatus(sessionId: String, status: SessionMappingStatus) {
        guard let idx = store.mappings.firstIndex(where: { $0.sessionId == sessionId }) else {
            return
        }
        store.mappings[idx].status = status
        store.mappings[idx].lastActiveAt = Date()
        rebuildIndex()
        scheduleSave()
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
        scheduleSave()
    }

    /// Touch the last-active timestamp for a session.
    /// Does not call `rebuildIndex()` since status is unchanged.
    func touch(sessionId: String) {
        guard let idx = store.mappings.firstIndex(where: { $0.sessionId == sessionId }) else {
            return
        }
        store.mappings[idx].lastActiveAt = Date()
        scheduleSave()
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
        scheduleSave()
    }

    /// Wait for any pending background save to complete.
    ///
    /// Useful in tests to ensure persistence has flushed before asserting
    /// on-disk state, and during app shutdown to avoid data loss.
    func flushPendingSave() async {
        await pendingSaveTask?.value
    }

    // MARK: - Persistence (private)

    /// Resolve the JSON file URL from an optional base directory.
    private static func resolveFileURL(baseURL: URL?) -> URL {
        let base = baseURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Dochi")
        return base.appendingPathComponent("session_mappings.json")
    }

    /// Synchronous load for the backward-compatible `init(baseURL:)`.
    private func loadSync(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            store = SessionMappingStore()
            rebuildIndex()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            store = try decoder.decode(SessionMappingStore.self, from: data)
            Log.runtime.info("Loaded \(self.store.mappings.count) session mapping(s)")
        } catch {
            Log.runtime.error("Failed to load session mappings: \(error.localizedDescription)")
            store = SessionMappingStore()
        }
        rebuildIndex()
    }

    /// Schedule a coalesced background save.
    ///
    /// Cancels any previously-scheduled save and starts a new one after a
    /// brief yield, so rapid mutations (e.g. `insert` + `updateStatus` in
    /// the same run-loop tick) produce only a single disk write.
    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let snapshot = store
        let ioActor = io
        pendingSaveTask = Task {
            // Yield to allow further mutations in the same run-loop iteration
            // to coalesce before we actually write.
            await Task.yield()
            guard !Task.isCancelled else { return }

            do {
                try await ioActor.write(snapshot)
            } catch {
                Log.runtime.error("Failed to save session mappings: \(error.localizedDescription)")
            }
        }
    }

    private func rebuildIndex() {
        lookupIndex.removeAll()
        for (idx, mapping) in store.mappings.enumerated() where mapping.status == .active {
            lookupIndex[mapping.lookupKey] = idx
        }
    }
}
