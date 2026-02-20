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

    @MainActor
    func testNativeLoopEnabledRoutesToNativePath() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            makeEvent(type: .sessionCompleted, payload: ["text": .string("sdk-response")]),
        ]

        let settings = AppSettings()
        settings.nativeAgentLoopEnabled = true
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"

        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.partial("native"), .done(text: "native")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
            bridge: bridge,
            settings: settings,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(bridge.runCallCount, 0)
        XCTAssertEqual(viewModel.interactionState, .idle)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertEqual(assistant, "native")
    }

    @MainActor
    func testNativeLoopAppliesContextCompactionBeforeRequest() async throws {
        let workspaceId = UUID()
        let sessionContext = SessionContext(workspaceId: workspaceId)
        sessionContext.currentUserId = "user-1"

        let settings = AppSettings()
        settings.nativeAgentLoopEnabled = true
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"
        settings.contextAutoCompress = true
        settings.contextMaxSize = 1_200

        let contextService = MockContextService()
        contextService.workspaceMemory[workspaceId] = String(repeating: "W", count: 8_000)
        contextService.agentMemories["\(workspaceId)|도치"] = String(repeating: "A", count: 8_000)
        contextService.userMemory["user-1"] = String(repeating: "P", count: 8_000)

        let conversationService = MockConversationService()
        var conversation = Conversation(userId: "user-1")
        for index in 0..<10 {
            let role: MessageRole = index % 2 == 0 ? .user : .assistant
            let content = "message-\(index) " + String(repeating: "x", count: 1_200)
            conversation.messages.append(Message(role: role, content: content))
        }
        conversationService.save(conversation: conversation)

        let metricsCollector = MetricsCollector()
        let adapter = CapturingStubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: contextService,
            conversationService: conversationService,
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext,
            metricsCollector: metricsCollector,
            runtimeBridge: nil,
            nativeAgentLoopService: nativeService
        )
        viewModel.loadConversations()
        viewModel.selectConversation(id: conversation.id)
        viewModel.inputText = "latest message " + String(repeating: "z", count: 800)
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(260))

        XCTAssertEqual(adapter.callCount, 1)
        guard let request = adapter.capturedRequests.first else {
            return XCTFail("Expected captured native request")
        }

        let compactionMetric = metricsCollector.recentContextCompactions.last
        XCTAssertNotNil(compactionMetric)
        XCTAssertTrue(compactionMetric?.didCompact == true)
        XCTAssertGreaterThan(compactionMetric?.droppedMessageCount ?? 0, 0)
        XCTAssertTrue(compactionMetric?.usedSummaryFallback == true)
        XCTAssertTrue(request.systemPrompt?.contains("컨텍스트 요약 스냅샷") == true)
    }

    @MainActor
    func testNativeLoopDisabledFallsBackToSDKPath() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            makeEvent(type: .sessionCompleted, payload: ["text": .string("sdk-response")]),
        ]

        let settings = AppSettings()
        settings.nativeAgentLoopEnabled = false
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"

        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
            bridge: bridge,
            settings: settings,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(adapter.callCount, 0)
        XCTAssertEqual(bridge.runCallCount, 1)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertEqual(assistant, "sdk-response")
    }

    @MainActor
    func testNativeLoopStreamingStateTransitionHasNoRegression() async throws {
        let settings = AppSettings()
        settings.nativeAgentLoopEnabled = true
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"

        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.partial("stream"), .done(text: "stream")]],
            eventDelayNanos: 300_000_000
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
            bridge: nil,
            settings: settings,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        XCTAssertEqual(viewModel.interactionState, .processing)
        XCTAssertEqual(viewModel.processingSubState, .streaming)

        try await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(viewModel.interactionState, .processing)
        XCTAssertEqual(viewModel.streamingText, "stream")

        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(viewModel.interactionState, .idle)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertEqual(assistant, "stream")
    }

    @MainActor
    func testNativeLoopUnsupportedProviderFallsBackToSDKPath() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            makeEvent(type: .sessionCompleted, payload: ["text": .string("sdk-response")]),
        ]

        let settings = AppSettings()
        settings.nativeAgentLoopEnabled = true
        settings.llmProvider = LLMProvider.openai.rawValue
        settings.llmModel = "gpt-4o"

        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
            bridge: bridge,
            settings: settings,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(adapter.callCount, 0)
        XCTAssertEqual(bridge.runCallCount, 1)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertEqual(assistant, "sdk-response")
    }

    @MainActor
    func testNativeLoopFailureFallsBackToSDKPath() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            makeEvent(type: .sessionCompleted, payload: ["text": .string("sdk-response")]),
        ]

        let settings = AppSettings()
        settings.nativeAgentLoopEnabled = true
        settings.llmProvider = LLMProvider.anthropic.rawValue
        settings.llmModel = "claude-sonnet-4-5-20250514"

        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[]],
            errorsPerRequest: [NativeLLMError(
                code: .network,
                message: "network down",
                statusCode: nil,
                retryAfterSeconds: nil
            )]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
            bridge: bridge,
            settings: settings,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(240))

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(bridge.runCallCount, 1)
        XCTAssertEqual(viewModel.interactionState, .idle)
        XCTAssertNil(viewModel.processingSubState)
        XCTAssertNil(viewModel.errorMessage)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertEqual(assistant, "sdk-response")
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
    private func makeViewModel(
        bridge: MockRuntimeBridgeService?,
        settings: AppSettings? = nil,
        nativeLoopService: NativeAgentLoopService? = nil
    ) -> DochiViewModel {
        let resolvedSettings: AppSettings = {
            if let settings { return settings }
            let defaults = AppSettings()
            defaults.nativeAgentLoopEnabled = false
            defaults.llmProvider = LLMProvider.openai.rawValue
            defaults.llmModel = "gpt-4o"
            return defaults
        }()

        return DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: resolvedSettings,
            sessionContext: SessionContext(workspaceId: UUID()),
            runtimeBridge: bridge,
            nativeAgentLoopService: nativeLoopService
        )
    }
}

private final class StubNativeProviderAdapter: @unchecked Sendable, NativeLLMProviderAdapter {
    let provider: LLMProvider
    private let eventsPerRequest: [[NativeLLMStreamEvent]]
    private let errorsPerRequest: [Error?]
    private let eventDelayNanos: UInt64
    private(set) var callCount: Int = 0

    init(
        provider: LLMProvider,
        eventsPerRequest: [[NativeLLMStreamEvent]],
        errorsPerRequest: [Error?] = [],
        eventDelayNanos: UInt64 = 0
    ) {
        self.provider = provider
        self.eventsPerRequest = eventsPerRequest
        self.errorsPerRequest = errorsPerRequest
        self.eventDelayNanos = eventDelayNanos
    }

    func stream(request _: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        let index = min(callCount, max(0, eventsPerRequest.count - 1))
        let events = eventsPerRequest.isEmpty ? [] : eventsPerRequest[index]
        let error = errorsPerRequest.isEmpty ? nil : errorsPerRequest[min(index, errorsPerRequest.count - 1)]
        callCount += 1

        return AsyncThrowingStream { continuation in
            Task {
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                for (index, event) in events.enumerated() {
                    continuation.yield(event)
                    if eventDelayNanos > 0, index < events.count - 1 {
                        try? await Task.sleep(nanoseconds: eventDelayNanos)
                    }
                }
                continuation.finish()
            }
        }
    }
}

private final class CapturingStubNativeProviderAdapter: @unchecked Sendable, NativeLLMProviderAdapter {
    let provider: LLMProvider
    private let eventsPerRequest: [[NativeLLMStreamEvent]]
    private(set) var callCount: Int = 0
    private(set) var capturedRequests: [NativeLLMRequest] = []

    init(
        provider: LLMProvider,
        eventsPerRequest: [[NativeLLMStreamEvent]]
    ) {
        self.provider = provider
        self.eventsPerRequest = eventsPerRequest
    }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        capturedRequests.append(request)
        let index = min(callCount, max(0, eventsPerRequest.count - 1))
        let events = eventsPerRequest.isEmpty ? [] : eventsPerRequest[index]
        callCount += 1

        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
