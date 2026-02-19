import XCTest
@testable import Dochi

/// Tests for cross-device session resume (Issue #291).
///
/// Covers:
/// - Same-device resume: existing session found, same deviceId
/// - Cross-device resume: existing session found, different deviceId
/// - New session creation: no active session exists
/// - Resume failure: runtime not ready, or session open fails
/// - SessionLookupKey deviceId exclusion verification
/// - Device transfer record audit trail
/// - Telegram channel resume scenario
final class CrossDeviceResumeTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrossDeviceResumeTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Create a standard set of services for each test.
    @MainActor
    private func makeServices(runtimeState: RuntimeState = .ready) -> (
        mappingService: SessionMappingService,
        mockBridge: MockRuntimeBridgeService,
        resumeService: CrossDeviceResumeService
    ) {
        let mappingService = SessionMappingService(baseURL: tempDir)
        let mockBridge = MockRuntimeBridgeService()
        mockBridge.runtimeState = runtimeState
        let resumeService = CrossDeviceResumeService(
            sessionMappingService: mappingService,
            bridge: mockBridge
        )
        return (mappingService, mockBridge, resumeService)
    }

    // MARK: - Same-device Resume

    @MainActor
    func testSameDeviceResume() async {
        let (mappingService, mockBridge, resumeService) = makeServices()

        // Insert an active session
        let mapping = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1", deviceId: "mac-home")
        mappingService.insert(mapping)

        let result = await resumeService.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "mac-home"
        )

        // Should resume with no previousDeviceId (same device)
        if case .resumed(let sessionId, let sdkSessionId, let previousDeviceId) = result {
            XCTAssertEqual(sessionId, "s-1")
            XCTAssertEqual(sdkSessionId, "sdk-1")
            XCTAssertNil(previousDeviceId)
        } else {
            XCTFail("Expected .resumed but got \(result)")
        }

        // No device transfer should be recorded
        XCTAssertEqual(resumeService.transferHistory.count, 0)
        // Bridge should NOT have been called to open a new session
        XCTAssertEqual(mockBridge.openCallCount, 0)
    }

    // MARK: - Cross-device Resume

    @MainActor
    func testCrossDeviceResume() async {
        let (mappingService, mockBridge, resumeService) = makeServices()

        // Session created on mac-home
        let mapping = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1", deviceId: "mac-home")
        mappingService.insert(mapping)

        // Now resume from mac-office
        let result = await resumeService.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "mac-office"
        )

        if case .resumed(let sessionId, let sdkSessionId, let previousDeviceId) = result {
            XCTAssertEqual(sessionId, "s-1")
            XCTAssertEqual(sdkSessionId, "sdk-1")
            XCTAssertEqual(previousDeviceId, "mac-home")
        } else {
            XCTFail("Expected .resumed with previousDeviceId but got \(result)")
        }

        // A device transfer record should be created
        XCTAssertEqual(resumeService.transferHistory.count, 1)
        XCTAssertEqual(resumeService.transferHistory[0].sessionId, "s-1")
        XCTAssertEqual(resumeService.transferHistory[0].fromDeviceId, "mac-home")
        XCTAssertEqual(resumeService.transferHistory[0].toDeviceId, "mac-office")
        // Bridge should NOT have been called to open a new session
        XCTAssertEqual(mockBridge.openCallCount, 0)
    }

    // MARK: - New Session (no existing)

    @MainActor
    func testNewSessionWhenNoneExists() async {
        let (mappingService, mockBridge, resumeService) = makeServices()

        // No existing session mapping
        mockBridge.stubbedOpenResult = SessionOpenResult(
            sessionId: "new-s-1",
            sdkSessionId: "new-sdk-1",
            created: true
        )

        let result = await resumeService.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "mac-home"
        )

        if case .created(let sessionId, let sdkSessionId) = result {
            XCTAssertEqual(sessionId, "new-s-1")
            XCTAssertEqual(sdkSessionId, "new-sdk-1")
        } else {
            XCTFail("Expected .created but got \(result)")
        }

        // Bridge should have been called
        XCTAssertEqual(mockBridge.openCallCount, 1)
        // The new mapping should be persisted
        let found = mappingService.findActive(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1"
        )
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.sessionId, "new-s-1")
        // No device transfer
        XCTAssertEqual(resumeService.transferHistory.count, 0)
    }

    // MARK: - Resume Failure: Runtime Not Ready

    @MainActor
    func testResumeFailsWhenRuntimeNotReady() async {
        let (_, _, resumeService) = makeServices(runtimeState: .notStarted)

        let result = await resumeService.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "mac-home"
        )

        if case .failed(let reason) = result {
            XCTAssertEqual(reason, .runtimeNotReady)
        } else {
            XCTFail("Expected .failed(.runtimeNotReady) but got \(result)")
        }
    }

    // MARK: - Resume Failure: Session Open Fails

    @MainActor
    func testResumeFailsWhenSessionOpenFails() async {
        let (_, mockBridge, resumeService) = makeServices()

        // No existing mapping, and bridge will throw
        mockBridge.stubbedError = RuntimeBridgeError.notConnected

        let result = await resumeService.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "mac-home"
        )

        if case .failed(let reason) = result {
            XCTAssertEqual(reason, .sessionOpenFailed)
        } else {
            XCTFail("Expected .failed(.sessionOpenFailed) but got \(result)")
        }
    }

    // MARK: - SessionLookupKey deviceId Exclusion

    @MainActor
    func testLookupKeyIgnoresDeviceId() {
        let (mappingService, _, _) = makeServices()

        // Insert a session from device A
        let mapping = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1", deviceId: "device-A")
        mappingService.insert(mapping)

        // Look up without specifying deviceId — should find it
        let found = mappingService.findActive(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1"
        )
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.sessionId, "s-1")
    }

    func testLookupKeyMatchesAcrossDevices() {
        // The lookup key should work regardless of which deviceId was used
        let keyA = SessionLookupKey(workspaceId: "ws-1", agentId: "agent-1", conversationId: "conv-1")
        let keyB = SessionLookupKey(workspaceId: "ws-1", agentId: "agent-1", conversationId: "conv-1")
        XCTAssertEqual(keyA, keyB)

        // Different conversation should NOT match
        let keyC = SessionLookupKey(workspaceId: "ws-1", agentId: "agent-1", conversationId: "conv-2")
        XCTAssertNotEqual(keyA, keyC)
    }

    // MARK: - Device Transfer Record Audit

    @MainActor
    func testDeviceTransferRecordCreation() {
        let (_, _, resumeService) = makeServices()

        resumeService.recordDeviceTransfer(
            sessionId: "s-1",
            fromDeviceId: "mac-home",
            toDeviceId: "mac-office"
        )

        XCTAssertEqual(resumeService.transferHistory.count, 1)
        let record = resumeService.transferHistory[0]
        XCTAssertEqual(record.sessionId, "s-1")
        XCTAssertEqual(record.fromDeviceId, "mac-home")
        XCTAssertEqual(record.toDeviceId, "mac-office")
    }

    @MainActor
    func testMultipleDeviceTransfers() async {
        let (mappingService, _, resumeService) = makeServices()

        // Session on mac-home
        let mapping = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1", deviceId: "mac-home")
        mappingService.insert(mapping)

        // Transfer to mac-office
        _ = await resumeService.resolveSession(
            workspaceId: "ws-1", agentId: "agent-1",
            conversationId: "conv-1", userId: "user-1",
            deviceId: "mac-office"
        )

        // Transfer to telegram
        _ = await resumeService.resolveSession(
            workspaceId: "ws-1", agentId: "agent-1",
            conversationId: "conv-1", userId: "user-1",
            deviceId: "telegram"
        )

        // Both transfers should be recorded
        XCTAssertEqual(resumeService.transferHistory.count, 2)
    }

    // MARK: - Telegram Channel Resume

    @MainActor
    func testTelegramChannelResume() async {
        let (mappingService, _, resumeService) = makeServices()

        // Session originally created from native Mac app
        let mapping = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1", deviceId: "mac-home")
        mappingService.insert(mapping)

        // Telegram sends a message for the same conversation
        let result = await resumeService.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "telegram"
        )

        // Should resume the existing session (cross-device)
        if case .resumed(let sessionId, let sdkSessionId, let previousDeviceId) = result {
            XCTAssertEqual(sessionId, "s-1")
            XCTAssertEqual(sdkSessionId, "sdk-1")
            XCTAssertEqual(previousDeviceId, "mac-home")
        } else {
            XCTFail("Expected .resumed for Telegram channel but got \(result)")
        }

        // Transfer should be recorded
        XCTAssertEqual(resumeService.transferHistory.count, 1)
        XCTAssertEqual(resumeService.transferHistory[0].toDeviceId, "telegram")
    }

    // MARK: - Closed Session Does Not Resume

    @MainActor
    func testClosedSessionDoesNotResume() async {
        let (mappingService, mockBridge, resumeService) = makeServices()

        // Insert and close a session
        let mapping = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1", deviceId: "mac-home")
        mappingService.insert(mapping)
        mappingService.updateStatus(sessionId: "s-1", status: .closed)

        // Set up bridge for new session
        mockBridge.stubbedOpenResult = SessionOpenResult(
            sessionId: "new-s-1",
            sdkSessionId: "new-sdk-1",
            created: true
        )

        let result = await resumeService.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "mac-home"
        )

        // Should create a new session since the old one is closed
        if case .created(let sessionId, _) = result {
            XCTAssertEqual(sessionId, "new-s-1")
        } else {
            XCTFail("Expected .created for closed session but got \(result)")
        }
    }

    // MARK: - Empty DeviceId Handling

    @MainActor
    func testEmptyDeviceIdDoesNotTriggerCrossDevice() async {
        let (mappingService, _, resumeService) = makeServices()

        // Session with empty deviceId (legacy or unspecified)
        let mapping = makeMapping(sessionId: "s-1", sdkSessionId: "sdk-1", deviceId: "")
        mappingService.insert(mapping)

        let result = await resumeService.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "mac-office"
        )

        // Should resume but without triggering cross-device logic (empty deviceId)
        if case .resumed(_, _, let previousDeviceId) = result {
            XCTAssertNil(previousDeviceId)
        } else {
            XCTFail("Expected .resumed without previousDeviceId but got \(result)")
        }

        // No device transfer recorded when original deviceId is empty
        XCTAssertEqual(resumeService.transferHistory.count, 0)
    }

    // MARK: - Mock Protocol Conformance

    @MainActor
    func testMockCrossDeviceResumeService() async {
        let mock = MockCrossDeviceResumeService()
        mock.stubbedResult = .resumed(sessionId: "s-1", sdkSessionId: "sdk-1", previousDeviceId: "mac-home")

        let result = await mock.resolveSession(
            workspaceId: "ws-1",
            agentId: "agent-1",
            conversationId: "conv-1",
            userId: "user-1",
            deviceId: "mac-office"
        )

        XCTAssertEqual(mock.resolveCallCount, 1)
        XCTAssertEqual(mock.lastResolveConversationId, "conv-1")
        XCTAssertEqual(mock.lastResolveDeviceId, "mac-office")

        if case .resumed(let sessionId, _, _) = result {
            XCTAssertEqual(sessionId, "s-1")
        } else {
            XCTFail("Expected stubbed .resumed result")
        }

        mock.recordDeviceTransfer(sessionId: "s-1", fromDeviceId: "mac-home", toDeviceId: "mac-office")
        XCTAssertEqual(mock.recordTransferCallCount, 1)
        XCTAssertEqual(mock.transferHistory.count, 1)
    }

    // MARK: - Helpers

    private func makeMapping(
        sessionId: String,
        sdkSessionId: String,
        workspaceId: String = "ws-1",
        agentId: String = "agent-1",
        conversationId: String = "conv-1",
        userId: String = "user-1",
        deviceId: String = "mac-home"
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
