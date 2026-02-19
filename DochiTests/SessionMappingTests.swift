import XCTest
@testable import Dochi

final class SessionMappingTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionMappingTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - SessionMapping Model

    func testSessionMappingCodableRoundTrip() throws {
        let mapping = SessionMapping(
            sessionId: "s-1",
            sdkSessionId: "sdk-1",
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            deviceId: "dev-1",
            status: .active,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            lastActiveAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(mapping)
        let decoded = try decoder.decode(SessionMapping.self, from: data)

        XCTAssertEqual(decoded.sessionId, "s-1")
        XCTAssertEqual(decoded.sdkSessionId, "sdk-1")
        XCTAssertEqual(decoded.workspaceId, "ws-1")
        XCTAssertEqual(decoded.agentId, "agent-1")
        XCTAssertEqual(decoded.conversationId, "conv-1")
        XCTAssertEqual(decoded.deviceId, "dev-1")
        XCTAssertEqual(decoded.status, .active)
    }

    func testSessionMappingLookupKey() {
        let mapping = SessionMapping(
            sessionId: "s-1", sdkSessionId: "sdk-1",
            workspaceId: "ws-1", agentId: "a-1",
            conversationId: "c-1", deviceId: "d-1",
            status: .active,
            createdAt: Date(), lastActiveAt: Date()
        )
        let key = mapping.lookupKey
        XCTAssertEqual(key.workspaceId, "ws-1")
        XCTAssertEqual(key.agentId, "a-1")
        XCTAssertEqual(key.conversationId, "c-1")
        XCTAssertEqual(key.deviceId, "d-1")
    }

    func testSessionMappingStatusValues() {
        XCTAssertEqual(SessionMappingStatus.active.rawValue, "active")
        XCTAssertEqual(SessionMappingStatus.closed.rawValue, "closed")
        XCTAssertEqual(SessionMappingStatus.interrupted.rawValue, "interrupted")
    }

    func testLookupKeyHashEquality() {
        let key1 = SessionLookupKey(workspaceId: "ws", agentId: "a", conversationId: "c", deviceId: "d")
        let key2 = SessionLookupKey(workspaceId: "ws", agentId: "a", conversationId: "c", deviceId: "d")
        let key3 = SessionLookupKey(workspaceId: "ws", agentId: "a", conversationId: "c", deviceId: "other")

        XCTAssertEqual(key1, key2)
        XCTAssertEqual(key1.hashValue, key2.hashValue)
        XCTAssertNotEqual(key1, key3)
    }

    // MARK: - SessionMappingStore Model

    func testStoreModelCodableRoundTrip() throws {
        let mapping = SessionMapping(
            sessionId: "s-1", sdkSessionId: "sdk-1",
            workspaceId: "ws-1", agentId: "a-1",
            conversationId: "c-1", deviceId: "d-1",
            status: .active,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            lastActiveAt: Date(timeIntervalSince1970: 1700000000)
        )
        let store = SessionMappingStore(mappings: [mapping], version: 1)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(store)
        let decoded = try decoder.decode(SessionMappingStore.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.mappings.count, 1)
        XCTAssertEqual(decoded.mappings[0].sessionId, "s-1")
    }

    // MARK: - SessionMappingService CRUD

    @MainActor
    func testInsertAndFind() {
        let service = SessionMappingService(baseURL: tempDir)

        let mapping = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1")
        service.insert(mapping)

        let found = service.findActive(
            workspaceId: "ws-1", agentId: "a-1",
            conversationId: "c-1", deviceId: "d-1"
        )
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.sessionId, "s-1")
        XCTAssertEqual(found?.sdkSessionId, "sdk-1")
    }

    @MainActor
    func testFindBySessionId() {
        let service = SessionMappingService(baseURL: tempDir)
        service.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))

        XCTAssertNotNil(service.findBySessionId("s-1"))
        XCTAssertNil(service.findBySessionId("nonexistent"))
    }

    @MainActor
    func testFindActiveReturnsNilForClosed() {
        let service = SessionMappingService(baseURL: tempDir)
        service.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))
        service.updateStatus(sessionId: "s-1", status: .closed)

        let found = service.findActive(
            workspaceId: "ws-1", agentId: "a-1",
            conversationId: "c-1", deviceId: "d-1"
        )
        XCTAssertNil(found)
    }

    @MainActor
    func testUpdateStatus() {
        let service = SessionMappingService(baseURL: tempDir)
        service.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))

        service.updateStatus(sessionId: "s-1", status: .interrupted)
        let mapping = service.findBySessionId("s-1")
        XCTAssertEqual(mapping?.status, .interrupted)
    }

    @MainActor
    func testTouch() {
        let service = SessionMappingService(baseURL: tempDir)
        let original = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1")
        service.insert(original)

        // Touch updates lastActiveAt
        service.touch(sessionId: "s-1")
        let updated = service.findBySessionId("s-1")
        XCTAssertNotNil(updated)
        XCTAssertGreaterThanOrEqual(updated!.lastActiveAt, original.lastActiveAt)
    }

    @MainActor
    func testAllMappings() {
        let service = SessionMappingService(baseURL: tempDir)
        service.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))
        service.insert(makeMapping(sessionId: "s-2", sdkSessionId: "sdk-2",
                                   conversationId: "c-2"))

        XCTAssertEqual(service.allMappings.count, 2)
    }

    @MainActor
    func testActiveMappings() {
        let service = SessionMappingService(baseURL: tempDir)
        service.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))
        service.insert(makeMapping(sessionId: "s-2", sdkSessionId: "sdk-2",
                                   conversationId: "c-2"))
        service.updateStatus(sessionId: "s-2", status: .closed)

        XCTAssertEqual(service.activeMappings.count, 1)
        XCTAssertEqual(service.activeMappings[0].sessionId, "s-1")
    }

    // MARK: - Persistence

    @MainActor
    func testPersistenceRoundTrip() {
        // Insert with first service instance
        let service1 = SessionMappingService(baseURL: tempDir)
        service1.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))
        service1.insert(makeMapping(sessionId: "s-2", sdkSessionId: "sdk-2",
                                    conversationId: "c-2"))

        // Create second instance — should load from file
        let service2 = SessionMappingService(baseURL: tempDir)
        XCTAssertEqual(service2.allMappings.count, 2)
        XCTAssertNotNil(service2.findBySessionId("s-1"))
        XCTAssertNotNil(service2.findBySessionId("s-2"))
    }

    @MainActor
    func testPersistenceAfterStatusUpdate() {
        let service1 = SessionMappingService(baseURL: tempDir)
        service1.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))
        service1.updateStatus(sessionId: "s-1", status: .closed)

        let service2 = SessionMappingService(baseURL: tempDir)
        let mapping = service2.findBySessionId("s-1")
        XCTAssertEqual(mapping?.status, .closed)
    }

    // MARK: - Session Reuse Logic

    @MainActor
    func testSameKeyReusesExistingSession() {
        let service = SessionMappingService(baseURL: tempDir)
        service.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))

        // Same composite key should find the existing active session
        let found = service.findActive(
            workspaceId: "ws-1", agentId: "a-1",
            conversationId: "c-1", deviceId: "d-1"
        )
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.sessionId, "s-1")
    }

    @MainActor
    func testDifferentKeyDoesNotReuse() {
        let service = SessionMappingService(baseURL: tempDir)
        service.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))

        // Different conversation ID
        let found = service.findActive(
            workspaceId: "ws-1", agentId: "a-1",
            conversationId: "other-conv", deviceId: "d-1"
        )
        XCTAssertNil(found)
    }

    @MainActor
    func testClosedSessionNotReused() {
        let service = SessionMappingService(baseURL: tempDir)
        service.insert(makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1"))
        service.updateStatus(sessionId: "s-1", status: .closed)

        // Same key but session is closed — should not reuse
        let found = service.findActive(
            workspaceId: "ws-1", agentId: "a-1",
            conversationId: "c-1", deviceId: "d-1"
        )
        XCTAssertNil(found)
    }

    // MARK: - Prune

    @MainActor
    func testPruneStaleRemovesOldClosed() {
        let service = SessionMappingService(baseURL: tempDir)
        var oldMapping = makeMapping(sessionId: "s-old", sdkSessionId: "sdk-old")
        oldMapping.status = .closed
        oldMapping.lastActiveAt = Date(timeIntervalSinceNow: -100000)
        service.insert(oldMapping)

        service.insert(makeMapping(sessionId: "s-new", sdkSessionId: "sdk-new",
                                   conversationId: "c-2"))

        service.pruneStale(olderThan: 86400)

        XCTAssertEqual(service.allMappings.count, 1)
        XCTAssertEqual(service.allMappings[0].sessionId, "s-new")
    }

    @MainActor
    func testPruneDoesNotRemoveActive() {
        let service = SessionMappingService(baseURL: tempDir)
        var oldActiveMapping = makeMapping(sessionId: "s-old", sdkSessionId: "sdk-old")
        oldActiveMapping.lastActiveAt = Date(timeIntervalSinceNow: -100000)
        service.insert(oldActiveMapping)

        service.pruneStale(olderThan: 86400)

        // Active sessions are never pruned
        XCTAssertEqual(service.allMappings.count, 1)
    }

    // MARK: - Helpers

    private func makeMapping(
        sessionId: String,
        sdkSessionId: String,
        workspaceId: String = "ws-1",
        agentId: String = "a-1",
        conversationId: String = "c-1",
        deviceId: String = "d-1"
    ) -> SessionMapping {
        SessionMapping(
            sessionId: sessionId,
            sdkSessionId: sdkSessionId,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            deviceId: deviceId,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
    }
}
