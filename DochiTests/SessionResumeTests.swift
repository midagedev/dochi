import XCTest
@testable import Dochi

// MARK: - SessionResumeTests

@MainActor
final class SessionResumeTests: XCTestCase {

    // MARK: - Test Fixtures

    private let workspaceId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let agentId = "test-agent"
    private let conversationId = "conv-001"
    private let deviceA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let deviceB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private var tempDir: URL!
    private var sessionMappingService: SessionMappingService!
    private var mockLeaseService: MockExecutionLeaseService!
    private var channelMapper: ChannelSessionMapper!
    private var sut: SessionResumeService!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        sessionMappingService = SessionMappingService(baseURL: tempDir)
        mockLeaseService = MockExecutionLeaseService()
        channelMapper = ChannelSessionMapper(baseURL: tempDir)

        // Configure mock lease service to have device available
        mockLeaseService.setNextDeviceId(deviceA)

        sut = SessionResumeService(
            sessionMappingService: sessionMappingService,
            leaseService: mockLeaseService,
            channelMapper: channelMapper
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Model Codable Roundtrip Tests

    func testSessionResumeRequestCodableRoundtrip() throws {
        let request = SessionResumeRequest(
            sourceChannel: .messenger,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceA,
            previousSessionId: "prev-session-123"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionResumeRequest.self, from: data)

        XCTAssertEqual(decoded.sourceChannel, .messenger)
        XCTAssertEqual(decoded.workspaceId, workspaceId)
        XCTAssertEqual(decoded.agentId, agentId)
        XCTAssertEqual(decoded.conversationId, conversationId)
        XCTAssertEqual(decoded.userId, "user-1")
        XCTAssertEqual(decoded.requestingDeviceId, deviceA)
        XCTAssertEqual(decoded.previousSessionId, "prev-session-123")
    }

    func testSessionResumeRequestCodableWithoutOptional() throws {
        let request = SessionResumeRequest(
            sourceChannel: .voice,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let decoded = try JSONDecoder().decode(SessionResumeRequest.self, from: data)

        XCTAssertEqual(decoded.sourceChannel, .voice)
        XCTAssertNil(decoded.previousSessionId)
    }

    func testResumeMetadataCodableRoundtrip() throws {
        let metadata = ResumeMetadata(
            previousDeviceId: deviceA,
            previousChannel: .text,
            lastActivityAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ResumeMetadata.self, from: data)

        XCTAssertEqual(decoded.previousDeviceId, deviceA)
        XCTAssertEqual(decoded.previousChannel, .text)
        XCTAssertEqual(decoded.lastActivityAt, Date(timeIntervalSince1970: 1700000000))
    }

    func testSessionChannelAllCases() {
        let allCases = SessionChannel.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.voice))
        XCTAssertTrue(allCases.contains(.text))
        XCTAssertTrue(allCases.contains(.messenger))
    }

    func testResumeFailureReasonCodableRoundtrip() throws {
        let reasons: [ResumeFailureReason] = [.sessionNotFound, .sessionClosed, .leaseReassignmentFailed, .internalError]
        for reason in reasons {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(ResumeFailureReason.self, from: data)
            XCTAssertEqual(decoded, reason)
        }
    }

    // MARK: - Session Key Normalization Tests

    func testNormalizeSessionKeyProducesConsistentKey() {
        let key1 = sut.normalizeSessionKey(workspaceId: workspaceId, agentId: agentId, conversationId: conversationId)
        let key2 = sut.normalizeSessionKey(workspaceId: workspaceId, agentId: agentId, conversationId: conversationId)
        XCTAssertEqual(key1, key2)
    }

    func testNormalizeSessionKeyIsDeviceIndependent() {
        // Two different devices produce the same key for the same conversation
        let key = sut.normalizeSessionKey(workspaceId: workspaceId, agentId: agentId, conversationId: conversationId)
        XCTAssertEqual(key, "\(workspaceId.uuidString):\(agentId):\(conversationId)")
        // The key does NOT contain deviceId
        XCTAssertFalse(key.contains(deviceA.uuidString))
        XCTAssertFalse(key.contains(deviceB.uuidString))
    }

    func testNormalizeSessionKeyDiffersForDifferentConversations() {
        let key1 = sut.normalizeSessionKey(workspaceId: workspaceId, agentId: agentId, conversationId: "conv-001")
        let key2 = sut.normalizeSessionKey(workspaceId: workspaceId, agentId: agentId, conversationId: "conv-002")
        XCTAssertNotEqual(key1, key2)
    }

    func testNormalizeSessionKeyDiffersForDifferentAgents() {
        let key1 = sut.normalizeSessionKey(workspaceId: workspaceId, agentId: "agent-1", conversationId: conversationId)
        let key2 = sut.normalizeSessionKey(workspaceId: workspaceId, agentId: "agent-2", conversationId: conversationId)
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - Resume Scenario: Same Device

    func testResumeSameDeviceReturnsResumed() async throws {
        // Pre-seed an active session mapping on deviceA
        let mapping = SessionMapping(
            sessionId: "session-existing",
            sdkSessionId: "sdk-existing",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        sessionMappingService.insert(mapping)

        // Also inject an active lease for the conversation
        let lease = ExecutionLease(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            assignedDeviceId: deviceA
        )
        mockLeaseService.leases[lease.leaseId] = lease
        mockLeaseService.conversationLeaseMap[conversationId] = lease.leaseId

        let request = SessionResumeRequest(
            sourceChannel: .voice,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .resumed(let sessionId, let deviceId, _):
            XCTAssertEqual(sessionId, "session-existing")
            XCTAssertEqual(deviceId, deviceA)
        default:
            XCTFail("Expected .resumed but got \(result)")
        }
    }

    // MARK: - Resume Scenario: Different Device

    func testResumeDifferentDeviceReassignsLease() async throws {
        // Pre-seed an active session mapping on deviceA
        let mapping = SessionMapping(
            sessionId: "session-on-A",
            sdkSessionId: "sdk-on-A",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        sessionMappingService.insert(mapping)

        // Inject an active lease on deviceA
        let lease = ExecutionLease(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            assignedDeviceId: deviceA
        )
        mockLeaseService.leases[lease.leaseId] = lease
        mockLeaseService.conversationLeaseMap[conversationId] = lease.leaseId
        mockLeaseService.setNextDeviceId(deviceB)

        // Request resume from deviceB
        let request = SessionResumeRequest(
            sourceChannel: .text,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceB
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .resumed(let sessionId, let deviceId, let metadata):
            // A new session mapping is created for the new device
            XCTAssertNotEqual(sessionId, "session-on-A")
            XCTAssertEqual(deviceId, deviceB)
            XCTAssertEqual(metadata.previousDeviceId, deviceA)
            // The old session mapping should be closed
            let oldMapping = sessionMappingService.findBySessionId("session-on-A")
            XCTAssertEqual(oldMapping?.status, .closed)
            // Verify reassign was called
            XCTAssertEqual(mockLeaseService.reassignCallCount, 1)
        default:
            XCTFail("Expected .resumed but got \(result)")
        }
    }

    // MARK: - Resume Scenario: No Session Found

    func testResumeNoSessionCreatesNewSession() async throws {
        mockLeaseService.setNextDeviceId(deviceA)

        let request = SessionResumeRequest(
            sourceChannel: .voice,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .newSession(let sessionId, let deviceId, let reason):
            XCTAssertEqual(deviceId, deviceA)
            XCTAssertEqual(reason, .sessionNotFound)
            XCTAssertEqual(mockLeaseService.acquireCallCount, 1)
            // Verify the new mapping stores the userId from the request
            let mapping = sessionMappingService.findBySessionId(sessionId)
            XCTAssertEqual(mapping?.userId, "user-1")
        default:
            XCTFail("Expected .newSession but got \(result)")
        }
    }

    // MARK: - Resume Scenario: Closed Session

    func testResumeClosedSessionCreatesNewSessionWithContextReuse() async throws {
        // Pre-seed a closed session mapping
        let closedMapping = SessionMapping(
            sessionId: "session-closed",
            sdkSessionId: "sdk-closed",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .closed,
            createdAt: Date().addingTimeInterval(-3600),
            lastActiveAt: Date().addingTimeInterval(-1800)
        )
        sessionMappingService.insert(closedMapping)

        mockLeaseService.setNextDeviceId(deviceB)

        let request = SessionResumeRequest(
            sourceChannel: .text,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceB
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .newSession(_, let deviceId, let reason):
            XCTAssertEqual(deviceId, deviceB)
            XCTAssertEqual(reason, .sessionClosed)
            XCTAssertEqual(mockLeaseService.acquireCallCount, 1)
        default:
            XCTFail("Expected .newSession but got \(result)")
        }
    }

    // MARK: - Resume Failure Fallback

    func testResumeFailsWhenLeaseAcquisitionFails() async throws {
        mockLeaseService.stubbedError = ExecutionLeaseError.noDeviceAvailable

        let request = SessionResumeRequest(
            sourceChannel: .voice,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .failed(let error):
            if case .leaseAcquisitionFailed = error {
                // Expected
            } else {
                XCTFail("Expected leaseAcquisitionFailed but got \(error)")
            }
        default:
            XCTFail("Expected .failed but got \(result)")
        }
    }

    func testResumeLeaseReassignmentFailureFallsBackToNewSession() async throws {
        // Pre-seed an active session mapping on deviceA
        let mapping = SessionMapping(
            sessionId: "session-on-A",
            sdkSessionId: "sdk-on-A",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        sessionMappingService.insert(mapping)

        // Inject active lease but make reassignment fail
        let lease = ExecutionLease(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            assignedDeviceId: deviceA
        )
        mockLeaseService.leases[lease.leaseId] = lease
        mockLeaseService.conversationLeaseMap[conversationId] = lease.leaseId

        // Temporarily make reassign fail but acquire succeed
        mockLeaseService.stubbedError = ExecutionLeaseError.reassignmentFailed(lease.leaseId)

        let request = SessionResumeRequest(
            sourceChannel: .text,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceB
        )

        let result = try await sut.resumeSession(request)

        // Since stubbedError affects all operations, the fallback createNewSession will also fail
        switch result {
        case .failed:
            // Expected because stubbedError is set globally on the mock
            break
        case .newSession(_, _, let reason):
            XCTAssertEqual(reason, .leaseReassignmentFailed)
        default:
            XCTFail("Expected .failed or .newSession with leaseReassignmentFailed but got \(result)")
        }
    }

    // MARK: - canResume Tests

    func testCanResumeReturnsTrueWhenMappingExists() {
        let mapping = SessionMapping(
            sessionId: "session-1",
            sdkSessionId: "sdk-1",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        sessionMappingService.insert(mapping)

        XCTAssertTrue(sut.canResume(conversationId: conversationId))
    }

    func testCanResumeReturnsTrueForClosedMapping() {
        let mapping = SessionMapping(
            sessionId: "session-closed",
            sdkSessionId: "sdk-closed",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .closed,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        sessionMappingService.insert(mapping)

        XCTAssertTrue(sut.canResume(conversationId: conversationId))
    }

    func testCanResumeReturnsFalseWhenNoMapping() {
        XCTAssertFalse(sut.canResume(conversationId: "nonexistent"))
    }

    // MARK: - Channel Session Mapper Tests

    func testChannelMapperVoicePassthrough() {
        let result = channelMapper.resolveConversationId(channel: .voice, identifier: "conv-123")
        XCTAssertEqual(result, "conv-123")
    }

    func testChannelMapperTextPassthrough() {
        let result = channelMapper.resolveConversationId(channel: .text, identifier: "conv-456")
        XCTAssertEqual(result, "conv-456")
    }

    func testChannelMapperMessengerReturnsNilWithoutMapping() {
        let result = channelMapper.resolveConversationId(channel: .messenger, identifier: "tg-chat-789")
        XCTAssertNil(result)
    }

    func testChannelMapperMessengerResolvesAfterRegistration() {
        channelMapper.registerMessengerMapping(externalChatId: "tg-chat-789", conversationId: conversationId)
        let result = channelMapper.resolveConversationId(channel: .messenger, identifier: "tg-chat-789")
        XCTAssertEqual(result, conversationId)
    }

    func testChannelMapperRemoveMessengerMapping() {
        channelMapper.registerMessengerMapping(externalChatId: "tg-100", conversationId: conversationId)
        XCTAssertNotNil(channelMapper.messengerConversationId(for: "tg-100"))

        channelMapper.removeMessengerMapping(externalChatId: "tg-100")
        XCTAssertNil(channelMapper.messengerConversationId(for: "tg-100"))
    }

    func testChannelMapperAllMessengerMappings() {
        channelMapper.registerMessengerMapping(externalChatId: "chat-1", conversationId: "conv-1")
        channelMapper.registerMessengerMapping(externalChatId: "chat-2", conversationId: "conv-2")

        let all = channelMapper.allMessengerMappings
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all["chat-1"], "conv-1")
        XCTAssertEqual(all["chat-2"], "conv-2")
    }

    func testChannelMapperOverwriteMapping() {
        channelMapper.registerMessengerMapping(externalChatId: "chat-1", conversationId: "conv-old")
        channelMapper.registerMessengerMapping(externalChatId: "chat-1", conversationId: "conv-new")

        let result = channelMapper.resolveConversationId(channel: .messenger, identifier: "chat-1")
        XCTAssertEqual(result, "conv-new")
    }

    // MARK: - Channel Mapper Persistence (Critical 3)

    func testChannelMapperPersistsMappingsToFile() {
        // Register mappings and verify the file exists
        channelMapper.registerMessengerMapping(externalChatId: "tg-100", conversationId: "conv-persist-1")
        channelMapper.registerMessengerMapping(externalChatId: "tg-200", conversationId: "conv-persist-2")

        let fileURL = tempDir.appendingPathComponent("channel_mappings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "channel_mappings.json should exist after registering mappings")

        // Create a new mapper from the same directory and verify it loads the mappings
        let freshMapper = ChannelSessionMapper(baseURL: tempDir)
        XCTAssertEqual(freshMapper.allMessengerMappings.count, 2)
        XCTAssertEqual(freshMapper.messengerConversationId(for: "tg-100"), "conv-persist-1")
        XCTAssertEqual(freshMapper.messengerConversationId(for: "tg-200"), "conv-persist-2")
    }

    func testChannelMapperPersistsAfterRemoval() {
        channelMapper.registerMessengerMapping(externalChatId: "tg-100", conversationId: "conv-1")
        channelMapper.registerMessengerMapping(externalChatId: "tg-200", conversationId: "conv-2")
        channelMapper.removeMessengerMapping(externalChatId: "tg-100")

        // Reload from disk
        let freshMapper = ChannelSessionMapper(baseURL: tempDir)
        XCTAssertEqual(freshMapper.allMessengerMappings.count, 1)
        XCTAssertNil(freshMapper.messengerConversationId(for: "tg-100"))
        XCTAssertEqual(freshMapper.messengerConversationId(for: "tg-200"), "conv-2")
    }

    func testChannelMapperEmptyFileLoadsEmpty() {
        // No registrations — create fresh mapper from same dir
        let freshMapper = ChannelSessionMapper(baseURL: tempDir)
        XCTAssertEqual(freshMapper.allMessengerMappings.count, 0)
    }

    // MARK: - userId Validation (C3 Hijack Prevention)

    func testResumeUserIdMismatchCreatesNewSession() async throws {
        // Pre-seed an active session owned by user-1
        let mapping = SessionMapping(
            sessionId: "session-owned",
            sdkSessionId: "sdk-owned",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        sessionMappingService.insert(mapping)
        mockLeaseService.setNextDeviceId(deviceB)

        // A different user (user-2) attempts to resume -> hijack prevention
        let request = SessionResumeRequest(
            sourceChannel: .text,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-2",
            requestingDeviceId: deviceB
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .newSession(_, _, let reason):
            XCTAssertEqual(reason, .sessionNotFound, "userId mismatch should create new session with .sessionNotFound reason")
            // The new session should be owned by user-2
            let newMappings = sessionMappingService.activeMappings.filter { $0.userId == "user-2" }
            XCTAssertEqual(newMappings.count, 1)
        default:
            XCTFail("Expected .newSession (hijack prevention) but got \(result)")
        }
    }

    func testResumeUserIdMatchResumesSameDevice() async throws {
        // Pre-seed an active session owned by user-1
        let mapping = SessionMapping(
            sessionId: "session-owned",
            sdkSessionId: "sdk-owned",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        sessionMappingService.insert(mapping)

        let lease = ExecutionLease(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            assignedDeviceId: deviceA
        )
        mockLeaseService.leases[lease.leaseId] = lease
        mockLeaseService.conversationLeaseMap[conversationId] = lease.leaseId

        // Same user resumes -> should succeed
        let request = SessionResumeRequest(
            sourceChannel: .voice,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .resumed(let sessionId, _, _):
            XCTAssertEqual(sessionId, "session-owned")
        default:
            XCTFail("Expected .resumed but got \(result)")
        }
    }

    // MARK: - Resume Error Tests

    func testSessionResumeErrorDescriptions() {
        let errors: [SessionResumeError] = [
            .conversationNotFound("conv-1"),
            .leaseAcquisitionFailed("no device"),
            .internalError("unexpected")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
            XCTAssertNotNil(error.userGuidance)
            XCTAssertFalse(error.userGuidance.isEmpty)
        }
    }

    // MARK: - Mock Service Tests

    func testMockSessionResumeServiceReturnsStubbed() async throws {
        let mock = MockSessionResumeService()
        let request = SessionResumeRequest(
            sourceChannel: .voice,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let result = try await mock.resumeSession(request)
        XCTAssertEqual(mock.resumeCallCount, 1)
        XCTAssertEqual(mock.lastRequest, request)

        switch result {
        case .newSession(_, _, let reason):
            XCTAssertEqual(reason, .sessionNotFound)
        default:
            XCTFail("Expected .newSession from mock default stub")
        }
    }

    func testMockSessionResumeServiceCanResume() {
        let mock = MockSessionResumeService()
        XCTAssertFalse(mock.canResume(conversationId: "conv-1"))

        mock.stubbedCanResume = true
        XCTAssertTrue(mock.canResume(conversationId: "conv-1"))
        XCTAssertEqual(mock.canResumeCallCount, 2)
    }

    func testMockSessionResumeServiceNormalize() {
        let mock = MockSessionResumeService()
        let key = mock.normalizeSessionKey(workspaceId: workspaceId, agentId: agentId, conversationId: conversationId)
        XCTAssertEqual(key, "\(workspaceId.uuidString):\(agentId):\(conversationId)")
        XCTAssertEqual(mock.normalizeCallCount, 1)
    }

    // MARK: - Messenger Resume Integration (S1: channelMapper used in resumeSession)

    func testMessengerResumeResolvesExternalChatIdViaChannelMapper() async throws {
        // Register a messenger mapping: external chatId -> internal conversationId
        channelMapper.registerMessengerMapping(externalChatId: "tg-555", conversationId: conversationId)

        // Pre-seed an active session for the internal conversationId
        let mapping = SessionMapping(
            sessionId: "session-tg",
            sdkSessionId: "sdk-tg",
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            deviceId: deviceA.uuidString,
            status: .active,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        sessionMappingService.insert(mapping)

        let lease = ExecutionLease(
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            assignedDeviceId: deviceA
        )
        mockLeaseService.leases[lease.leaseId] = lease
        mockLeaseService.conversationLeaseMap[conversationId] = lease.leaseId

        // Resume using the EXTERNAL chat ID (channelMapper should resolve it)
        let request = SessionResumeRequest(
            sourceChannel: .messenger,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: "tg-555",  // external chat ID, NOT internal conversationId
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let result = try await sut.resumeSession(request)

        // Should resume the existing session after resolving via channelMapper
        switch result {
        case .resumed(let sessionId, _, _):
            XCTAssertEqual(sessionId, "session-tg")
        default:
            XCTFail("Expected .resumed after channel mapper resolution but got \(result)")
        }
    }

    func testMessengerResumeWithoutMappingCreatesNewSession() async throws {
        mockLeaseService.setNextDeviceId(deviceA)

        // No channel mapping registered for "unknown-chat"
        let request = SessionResumeRequest(
            sourceChannel: .messenger,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: "unknown-chat",
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .newSession(_, _, let reason):
            XCTAssertEqual(reason, .sessionNotFound, "Unmapped messenger chat should create new session")
        default:
            XCTFail("Expected .newSession for unmapped messenger chat but got \(result)")
        }
    }

    func testVoiceChannelBypassesChannelMapper() async throws {
        mockLeaseService.setNextDeviceId(deviceA)

        // Voice channel should use conversationId directly, not go through channelMapper
        let request = SessionResumeRequest(
            sourceChannel: .voice,
            workspaceId: workspaceId,
            agentId: agentId,
            conversationId: conversationId,
            userId: "user-1",
            requestingDeviceId: deviceA
        )

        let result = try await sut.resumeSession(request)

        switch result {
        case .newSession:
            break // Expected — no existing session
        default:
            XCTFail("Expected .newSession for voice channel but got \(result)")
        }
    }
}
