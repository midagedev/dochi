import XCTest
@testable import Dochi

/// Tests for SessionMappingServiceProtocol extraction (Issue #297).
///
/// Validates:
/// - MockSessionMappingService correctly implements the protocol
/// - SessionResumeService accepts protocol-based DI (MockSessionMappingService)
/// - CrossDeviceResumeService accepts protocol-based DI (MockSessionMappingService)
/// - Mock call tracking works correctly for test assertions
final class SessionMappingProtocolTests: XCTestCase {

    // MARK: - MockSessionMappingService CRUD

    @MainActor
    func testMockInsertAndFindActive() {
        let mock = MockSessionMappingService()
        let mapping = makeMapping(sessionId: "s-1")
        mock.insert(mapping)

        XCTAssertEqual(mock.insertCallCount, 1)
        XCTAssertEqual(mock.lastInsertedMapping?.sessionId, "s-1")

        let found = mock.findActive(
            workspaceId: "ws-1",
            agentId: "a-1",
            conversationId: "c-1"
        )
        XCTAssertEqual(mock.findActiveCallCount, 1)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.sessionId, "s-1")
    }

    @MainActor
    func testMockFindBySessionId() {
        let mock = MockSessionMappingService()
        mock.insert(makeMapping(sessionId: "s-1"))

        let found = mock.findBySessionId("s-1")
        XCTAssertEqual(mock.findBySessionIdCallCount, 1)
        XCTAssertNotNil(found)

        let notFound = mock.findBySessionId("nonexistent")
        XCTAssertNil(notFound)
        XCTAssertEqual(mock.findBySessionIdCallCount, 2)
    }

    @MainActor
    func testMockUpdateStatus() {
        let mock = MockSessionMappingService()
        mock.insert(makeMapping(sessionId: "s-1"))

        mock.updateStatus(sessionId: "s-1", status: .closed)

        XCTAssertEqual(mock.updateStatusCallCount, 1)
        XCTAssertEqual(mock.lastUpdatedSessionId, "s-1")
        XCTAssertEqual(mock.lastUpdatedStatus, .closed)

        let mapping = mock.findBySessionId("s-1")
        XCTAssertEqual(mapping?.status, .closed)
    }

    @MainActor
    func testMockUpdateDeviceId() {
        let mock = MockSessionMappingService()
        mock.insert(makeMapping(sessionId: "s-1", deviceId: "device-A"))

        mock.updateDeviceId(sessionId: "s-1", newDeviceId: "device-B")

        XCTAssertEqual(mock.updateDeviceIdCallCount, 1)
        XCTAssertEqual(mock.lastUpdatedDeviceId, "device-B")

        let mapping = mock.findBySessionId("s-1")
        XCTAssertEqual(mapping?.deviceId, "device-B")
    }

    @MainActor
    func testMockTouch() {
        let mock = MockSessionMappingService()
        let original = makeMapping(sessionId: "s-1")
        mock.insert(original)

        mock.touch(sessionId: "s-1")

        XCTAssertEqual(mock.touchCallCount, 1)
        XCTAssertEqual(mock.lastTouchedSessionId, "s-1")

        let updated = mock.findBySessionId("s-1")
        XCTAssertNotNil(updated)
        XCTAssertGreaterThanOrEqual(updated!.lastActiveAt, original.lastActiveAt)
    }

    @MainActor
    func testMockAllAndActiveMappings() {
        let mock = MockSessionMappingService()
        mock.insert(makeMapping(sessionId: "s-1", conversationId: "c-1"))
        mock.insert(makeMapping(sessionId: "s-2", conversationId: "c-2"))
        mock.updateStatus(sessionId: "s-2", status: .closed)

        XCTAssertEqual(mock.allMappings.count, 2)
        XCTAssertEqual(mock.activeMappings.count, 1)
        XCTAssertEqual(mock.activeMappings[0].sessionId, "s-1")
    }

    @MainActor
    func testMockFindActiveReturnsNilForClosed() {
        let mock = MockSessionMappingService()
        mock.insert(makeMapping(sessionId: "s-1"))
        mock.updateStatus(sessionId: "s-1", status: .closed)

        let found = mock.findActive(
            workspaceId: "ws-1",
            agentId: "a-1",
            conversationId: "c-1"
        )
        XCTAssertNil(found)
    }

    @MainActor
    func testMockPruneStale() {
        let mock = MockSessionMappingService()
        var oldMapping = makeMapping(sessionId: "s-old", conversationId: "c-old")
        oldMapping.status = .closed
        oldMapping.lastActiveAt = Date(timeIntervalSinceNow: -100000)
        mock.insert(oldMapping)

        mock.insert(makeMapping(sessionId: "s-new", conversationId: "c-new"))

        mock.pruneStale(olderThan: 86400)

        XCTAssertEqual(mock.pruneStaleCallCount, 1)
        XCTAssertEqual(mock.lastPruneInterval, 86400)
        XCTAssertEqual(mock.allMappings.count, 1)
        XCTAssertEqual(mock.allMappings[0].sessionId, "s-new")
    }

    // MARK: - CrossDeviceResumeService with Mock DI

    @MainActor
    func testCrossDeviceResumeWithMockMapping() async {
        let mockMapping = MockSessionMappingService()
        let mockBridge = MockRuntimeBridgeService()
        mockBridge.runtimeState = .ready

        let service = CrossDeviceResumeService(
            sessionMappingService: mockMapping,
            bridge: mockBridge
        )

        // Insert an active mapping
        mockMapping.insert(makeMapping(sessionId: "s-1", deviceId: "mac-home"))

        let result = await service.resolveSession(
            workspaceId: "ws-1",
            agentId: "a-1",
            conversationId: "c-1",
            userId: "u-1",
            deviceId: "mac-office"
        )

        // Should resume cross-device
        if case .resumed(let sessionId, _, let previousDeviceId) = result {
            XCTAssertEqual(sessionId, "s-1")
            XCTAssertEqual(previousDeviceId, "mac-home")
        } else {
            XCTFail("Expected .resumed but got \(result)")
        }

        // Mock should track the calls
        XCTAssertEqual(mockMapping.findActiveCallCount, 1)
        XCTAssertEqual(mockMapping.updateDeviceIdCallCount, 1)
        XCTAssertEqual(mockMapping.lastUpdatedDeviceId, "mac-office")
        XCTAssertEqual(mockBridge.openCallCount, 0)
    }

    @MainActor
    func testCrossDeviceResumeCreatesNewSessionWithMockMapping() async {
        let mockMapping = MockSessionMappingService()
        let mockBridge = MockRuntimeBridgeService()
        mockBridge.runtimeState = .ready
        mockBridge.stubbedOpenResult = SessionOpenResult(
            sessionId: "new-s-1",
            sdkSessionId: "new-sdk-1",
            created: true
        )

        let service = CrossDeviceResumeService(
            sessionMappingService: mockMapping,
            bridge: mockBridge
        )

        // No existing mapping
        let result = await service.resolveSession(
            workspaceId: "ws-1",
            agentId: "a-1",
            conversationId: "c-1",
            userId: "u-1",
            deviceId: "mac-home"
        )

        if case .created(let sessionId, let sdkSessionId) = result {
            XCTAssertEqual(sessionId, "new-s-1")
            XCTAssertEqual(sdkSessionId, "new-sdk-1")
        } else {
            XCTFail("Expected .created but got \(result)")
        }

        // Mock should have been called to insert the new mapping
        XCTAssertEqual(mockMapping.insertCallCount, 1)
        XCTAssertEqual(mockMapping.lastInsertedMapping?.sessionId, "new-s-1")
        XCTAssertEqual(mockBridge.openCallCount, 1)
    }

    @MainActor
    func testCrossDeviceResumeSameDeviceWithMockMapping() async {
        let mockMapping = MockSessionMappingService()
        let mockBridge = MockRuntimeBridgeService()
        mockBridge.runtimeState = .ready

        let service = CrossDeviceResumeService(
            sessionMappingService: mockMapping,
            bridge: mockBridge
        )

        // Insert an active mapping from the same device
        mockMapping.insert(makeMapping(sessionId: "s-1", deviceId: "mac-home"))

        let result = await service.resolveSession(
            workspaceId: "ws-1",
            agentId: "a-1",
            conversationId: "c-1",
            userId: "u-1",
            deviceId: "mac-home"
        )

        // Should resume on same device
        if case .resumed(let sessionId, _, let previousDeviceId) = result {
            XCTAssertEqual(sessionId, "s-1")
            XCTAssertNil(previousDeviceId)
        } else {
            XCTFail("Expected .resumed but got \(result)")
        }

        // touch should have been called (same device)
        XCTAssertEqual(mockMapping.touchCallCount, 1)
        XCTAssertEqual(mockMapping.lastTouchedSessionId, "s-1")
        // updateDeviceId should NOT have been called (same device)
        XCTAssertEqual(mockMapping.updateDeviceIdCallCount, 0)
    }

    @MainActor
    func testCrossDeviceResumeUserIdMismatchWithMock() async {
        let mockMapping = MockSessionMappingService()
        let mockBridge = MockRuntimeBridgeService()
        mockBridge.runtimeState = .ready
        mockBridge.stubbedOpenResult = SessionOpenResult(
            sessionId: "new-s-1",
            sdkSessionId: "new-sdk-1",
            created: true
        )

        let service = CrossDeviceResumeService(
            sessionMappingService: mockMapping,
            bridge: mockBridge
        )

        // Insert mapping owned by user-1
        mockMapping.insert(makeMapping(sessionId: "s-1", userId: "user-1", deviceId: "mac-home"))

        // Different user tries to resume
        let result = await service.resolveSession(
            workspaceId: "ws-1",
            agentId: "a-1",
            conversationId: "c-1",
            userId: "user-2",
            deviceId: "attacker-device"
        )

        // Should create a new session (hijack prevention)
        if case .created(let sessionId, _) = result {
            XCTAssertEqual(sessionId, "new-s-1")
        } else {
            XCTFail("Expected .created (hijack prevention) but got \(result)")
        }

        // Original mapping should be untouched
        XCTAssertEqual(mockMapping.touchCallCount, 0)
        XCTAssertEqual(mockMapping.updateDeviceIdCallCount, 0)
    }

    // MARK: - SessionResumeService with Mock DI

    @MainActor
    func testSessionResumeServiceAcceptsMockMapping() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionMappingProtocolTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mockMapping = MockSessionMappingService()
        let mockLease = MockExecutionLeaseService()
        let channelMapper = ChannelSessionMapper(baseURL: tempDir)
        let deviceId = UUID()
        mockLease.setNextDeviceId(deviceId)

        let service = SessionResumeService(
            sessionMappingService: mockMapping,
            leaseService: mockLease,
            channelMapper: channelMapper
        )

        // No existing mapping -> should create new session
        let request = SessionResumeRequest(
            sourceChannel: .voice,
            workspaceId: UUID(),
            agentId: "a-1",
            conversationId: "c-1",
            userId: "u-1",
            requestingDeviceId: deviceId
        )

        let result = try await service.resumeSession(request)

        if case .newSession(_, _, let reason) = result {
            XCTAssertEqual(reason, .sessionNotFound)
        } else {
            XCTFail("Expected .newSession but got \(result)")
        }

        // Mock mapping should have been called to insert the new mapping
        XCTAssertEqual(mockMapping.insertCallCount, 1)
        XCTAssertEqual(mockLease.acquireCallCount, 1)
    }

    @MainActor
    func testSessionResumeCanResumeWithMockMapping() {
        let mockMapping = MockSessionMappingService()
        let mockLease = MockExecutionLeaseService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionMappingProtocolTests-canResume-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let channelMapper = ChannelSessionMapper(baseURL: tempDir)

        let service = SessionResumeService(
            sessionMappingService: mockMapping,
            leaseService: mockLease,
            channelMapper: channelMapper
        )

        // No mappings -> canResume should be false
        XCTAssertFalse(service.canResume(conversationId: "c-1"))

        // Insert a mapping -> canResume should be true
        mockMapping.insert(makeMapping(sessionId: "s-1", conversationId: "c-1"))
        XCTAssertTrue(service.canResume(conversationId: "c-1"))
    }

    // MARK: - Protocol Conformance Verification

    @MainActor
    func testConcreteServiceConformsToProtocol() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionMappingProtocolTests-conformance-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Verify that the concrete service can be assigned to the protocol type
        let concrete = SessionMappingService(baseURL: tempDir)
        let _: any SessionMappingServiceProtocol = concrete

        concrete.insert(makeMapping(sessionId: "s-1"))
        let found = concrete.findActive(
            workspaceId: "ws-1",
            agentId: "a-1",
            conversationId: "c-1"
        )
        XCTAssertNotNil(found)
    }

    // MARK: - Helpers

    private func makeMapping(
        sessionId: String,
        sdkSessionId: String = "sdk-1",
        workspaceId: String = "ws-1",
        agentId: String = "a-1",
        conversationId: String = "c-1",
        userId: String = "u-1",
        deviceId: String = "d-1"
    ) -> SessionMapping {
        SessionMapping(
            sessionId: sessionId,
            sdkSessionId: sdkSessionId,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: userId,
            deviceId: deviceId,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
    }
}
