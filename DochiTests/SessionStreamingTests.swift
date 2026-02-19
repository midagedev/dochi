import XCTest
@testable import Dochi

final class SessionStreamingTests: XCTestCase {

    // MARK: - BridgeEvent Parsing

    func testBridgeEventDecodePartial() throws {
        let json = """
        {
            "eventId": "e-1",
            "timestamp": "2024-01-01T00:00:00Z",
            "sessionId": "s-1",
            "eventType": "session.partial",
            "payload": {"delta": "Hello"}
        }
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.eventId, "e-1")
        XCTAssertEqual(event.sessionId, "s-1")
        XCTAssertEqual(event.eventType, .sessionPartial)

        // Verify payload contains delta
        if case .object(let dict) = event.payload,
           case .string(let delta) = dict["delta"] {
            XCTAssertEqual(delta, "Hello")
        } else {
            XCTFail("Expected payload with delta string")
        }
    }

    func testBridgeEventDecodeToolCall() throws {
        let json = """
        {
            "eventId": "e-2",
            "timestamp": "2024-01-01T00:00:00Z",
            "sessionId": "s-1",
            "eventType": "session.tool_call",
            "payload": {"toolName": "web_search", "toolCallId": "tc-1"}
        }
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.eventType, .sessionToolCall)

        if case .object(let dict) = event.payload,
           case .string(let toolName) = dict["toolName"] {
            XCTAssertEqual(toolName, "web_search")
        } else {
            XCTFail("Expected payload with toolName")
        }
    }

    func testBridgeEventDecodeCompleted() throws {
        let json = """
        {
            "eventId": "e-3",
            "timestamp": "2024-01-01T00:00:00Z",
            "sessionId": "s-1",
            "eventType": "session.completed",
            "payload": {"text": "Hello world"}
        }
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.eventType, .sessionCompleted)

        if case .object(let dict) = event.payload,
           case .string(let text) = dict["text"] {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected payload with text")
        }
    }

    func testBridgeEventDecodeFailed() throws {
        let json = """
        {
            "eventId": "e-4",
            "timestamp": "2024-01-01T00:00:00Z",
            "sessionId": "s-1",
            "eventType": "session.failed",
            "payload": {"error": "Model overloaded"}
        }
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.eventType, .sessionFailed)

        if case .object(let dict) = event.payload,
           case .string(let error) = dict["error"] {
            XCTAssertEqual(error, "Model overloaded")
        } else {
            XCTFail("Expected payload with error string")
        }
    }

    func testBridgeEventDecodeWithNullOptionals() throws {
        let json = """
        {
            "eventId": "e-5",
            "timestamp": "2024-01-01T00:00:00Z",
            "eventType": "session.partial",
            "payload": {"delta": "test"}
        }
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: json.data(using: .utf8)!)
        XCTAssertNil(event.sessionId)
        XCTAssertNil(event.workspaceId)
        XCTAssertNil(event.agentId)
    }

    // MARK: - Notification to Event Mapping

    func testJsonRpcNotificationDecode() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "method": "bridge.event",
            "params": {
                "eventId": "e-1",
                "timestamp": "2024-01-01T00:00:00Z",
                "sessionId": "s-1",
                "eventType": "session.partial",
                "payload": {"delta": "Hello"}
            }
        }
        """
        let notification = try JSONDecoder().decode(JsonRpcNotification.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(notification.method, "bridge.event")
        XCTAssertNotNil(notification.params)

        // Verify the params can be re-encoded and decoded as BridgeEvent
        if let params = notification.params {
            let encoded = try JSONEncoder().encode(AnyCodableValue.object(params))
            let event = try JSONDecoder().decode(BridgeEvent.self, from: encoded)
            XCTAssertEqual(event.eventType, .sessionPartial)
            XCTAssertEqual(event.sessionId, "s-1")
        }
    }

    // MARK: - Mock Bridge Session Lifecycle

    @MainActor
    func testMockBridgeOpenSession() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready

        let result = try await bridge.openSession(params: SessionOpenParams(
            workspaceId: "ws-1",
            agentId: "a-1",
            conversationId: "c-1",
            userId: "u-1",
            deviceId: nil,
            sdkSessionId: nil
        ))

        XCTAssertEqual(result.sessionId, "mock-session")
        XCTAssertTrue(result.created)
        XCTAssertEqual(bridge.openCallCount, 1)
    }

    @MainActor
    func testMockBridgeRunSessionDeliversEvents() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            BridgeEvent(
                eventId: "e-1", timestamp: "2024-01-01T00:00:00Z",
                sessionId: "s-1", workspaceId: nil, agentId: nil,
                eventType: .sessionPartial,
                payload: .object(["delta": .string("Hello")])
            ),
            BridgeEvent(
                eventId: "e-2", timestamp: "2024-01-01T00:00:01Z",
                sessionId: "s-1", workspaceId: nil, agentId: nil,
                eventType: .sessionPartial,
                payload: .object(["delta": .string(" world")])
            ),
            BridgeEvent(
                eventId: "e-3", timestamp: "2024-01-01T00:00:02Z",
                sessionId: "s-1", workspaceId: nil, agentId: nil,
                eventType: .sessionCompleted,
                payload: .object(["text": .string("Hello world")])
            ),
        ]

        let params = SessionRunParams(
            sessionId: "s-1", input: "Hello",
            contextSnapshotRef: nil, permissionMode: nil
        )

        var receivedEvents: [BridgeEvent] = []
        for try await event in bridge.runSession(params: params) {
            receivedEvents.append(event)
        }

        XCTAssertEqual(receivedEvents.count, 3)
        XCTAssertEqual(receivedEvents[0].eventType, .sessionPartial)
        XCTAssertEqual(receivedEvents[1].eventType, .sessionPartial)
        XCTAssertEqual(receivedEvents[2].eventType, .sessionCompleted)
        XCTAssertEqual(bridge.runCallCount, 1)
    }

    @MainActor
    func testMockBridgeRunSessionCompletesOnFailed() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.stubbedSessionEvents = [
            BridgeEvent(
                eventId: "e-1", timestamp: "2024-01-01T00:00:00Z",
                sessionId: "s-1", workspaceId: nil, agentId: nil,
                eventType: .sessionFailed,
                payload: .object(["error": .string("Model error")])
            ),
        ]

        let params = SessionRunParams(
            sessionId: "s-1", input: "test",
            contextSnapshotRef: nil, permissionMode: nil
        )

        var receivedEvents: [BridgeEvent] = []
        for try await event in bridge.runSession(params: params) {
            receivedEvents.append(event)
        }

        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents[0].eventType, .sessionFailed)
    }

    @MainActor
    func testMockBridgeInterruptSession() async throws {
        let bridge = MockRuntimeBridgeService()
        let result = try await bridge.interruptSession(sessionId: "s-1")
        XCTAssertTrue(result.interrupted)
        XCTAssertEqual(result.sessionId, "s-1")
        XCTAssertEqual(bridge.interruptCallCount, 1)
    }

    @MainActor
    func testMockBridgeCloseSession() async throws {
        let bridge = MockRuntimeBridgeService()
        let result = try await bridge.closeSession(sessionId: "s-1")
        XCTAssertTrue(result.closed)
        XCTAssertEqual(result.sessionId, "s-1")
        XCTAssertEqual(bridge.closeCallCount, 1)
    }

    // MARK: - Event → State Mapping

    @MainActor
    func testPartialEventAccumulatesText() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            makeEvent(type: .sessionPartial, payload: ["delta": .string("Hello")]),
            makeEvent(type: .sessionPartial, payload: ["delta": .string(" world")]),
            makeEvent(type: .sessionCompleted, payload: ["text": .string("Hello world")]),
        ]

        let viewModel = makeViewModel(bridge: bridge)
        viewModel.configureRuntimeBridge(bridge)
        // Manually ensure a conversation exists
        viewModel.inputText = "test"
        viewModel.sendMessage()

        // Wait for processing to complete
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(viewModel.interactionState, .idle)
        XCTAssertEqual(viewModel.streamingText, "")
        // The assistant message should have been appended
        if let conversation = viewModel.currentConversation {
            let assistantMessages = conversation.messages.filter { $0.role == .assistant }
            XCTAssertFalse(assistantMessages.isEmpty, "Expected an assistant message")
            XCTAssertEqual(assistantMessages.last?.content, "Hello world")
        }
    }

    @MainActor
    func testToolCallEventProcessedInStream() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            makeEvent(type: .sessionToolCall, payload: ["toolName": .string("web_search"), "toolCallId": .string("tc-1")]),
            makeEvent(type: .sessionToolResult, payload: ["toolCallId": .string("tc-1"), "content": .string("result")]),
            makeEvent(type: .sessionCompleted, payload: ["text": .string("Done")]),
        ]

        let viewModel = makeViewModel(bridge: bridge)
        viewModel.configureRuntimeBridge(bridge)
        viewModel.inputText = "search something"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(200))

        // Verify session run was invoked
        XCTAssertEqual(bridge.runCallCount, 1)
        XCTAssertEqual(bridge.lastRunParams?.input, "search something")

        // After completion, state should be idle with no active tool
        XCTAssertEqual(viewModel.interactionState, .idle)
        XCTAssertNil(viewModel.currentToolName)

        // The completed event's text should be appended as assistant message
        if let conversation = viewModel.currentConversation {
            let assistantMessages = conversation.messages.filter { $0.role == .assistant }
            XCTAssertEqual(assistantMessages.last?.content, "Done")
        }
    }

    @MainActor
    func testFailedEventSetsErrorMessage() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            makeEvent(type: .sessionFailed, payload: ["error": .string("Model overloaded")]),
        ]

        let viewModel = makeViewModel(bridge: bridge)
        viewModel.configureRuntimeBridge(bridge)
        viewModel.inputText = "test"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(viewModel.interactionState, .idle)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Model overloaded") ?? false)
    }

    @MainActor
    func testSDKSessionAvailableWhenRuntimeReady() {
        let bridge = MockRuntimeBridgeService()
        let viewModel = makeViewModel(bridge: bridge)
        viewModel.configureRuntimeBridge(bridge)

        bridge.runtimeState = .notStarted
        XCTAssertFalse(viewModel.isSDKSessionAvailable)

        bridge.runtimeState = .ready
        XCTAssertTrue(viewModel.isSDKSessionAvailable)

        bridge.runtimeState = .degraded
        XCTAssertFalse(viewModel.isSDKSessionAvailable)
    }

    @MainActor
    func testNewConversationClearsSDKSession() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            makeEvent(type: .sessionCompleted, payload: ["text": .string("hi")]),
        ]

        let viewModel = makeViewModel(bridge: bridge)
        viewModel.configureRuntimeBridge(bridge)
        viewModel.inputText = "hello"
        viewModel.sendMessage()
        try await Task.sleep(for: .milliseconds(200))

        // Should have an active session
        XCTAssertNotNil(viewModel.activeSDKSessionId)

        // New conversation should clear it
        viewModel.newConversation()
        XCTAssertNil(viewModel.activeSDKSessionId)

        // Allow async close task to execute
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(bridge.closeCallCount, 1)
    }

    // MARK: - Helpers

    private func makeEvent(
        type: BridgeEventType,
        payload: [String: AnyCodableValue],
        sessionId: String = "mock-session"
    ) -> BridgeEvent {
        BridgeEvent(
            eventId: UUID().uuidString,
            timestamp: "2024-01-01T00:00:00Z",
            sessionId: sessionId,
            workspaceId: nil,
            agentId: nil,
            eventType: type,
            payload: .object(payload)
        )
    }

    @MainActor
    private func makeViewModel(bridge: MockRuntimeBridgeService) -> DochiViewModel {
        DochiViewModel(
            llmService: MockLLMService(),
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: AppSettings(),
            sessionContext: SessionContext(workspaceId: UUID()),
            runtimeBridge: bridge
        )
    }
}
