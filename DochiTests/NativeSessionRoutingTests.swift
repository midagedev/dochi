import XCTest
@testable import Dochi

final class NativeSessionRoutingTests: XCTestCase {

    @MainActor
    func testNativeLoopEnabledRoutesToNativePath() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready
        bridge.stubbedSessionEvents = [
            BridgeEvent(
                eventId: UUID().uuidString,
                timestamp: "2024-01-01T00:00:00Z",
                sessionId: "mock-session",
                workspaceId: nil,
                agentId: nil,
                eventType: .sessionCompleted,
                payload: .object(["text": .string("legacy-sdk-response")])
            ),
        ]

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
            provider: .anthropic,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(bridge.runCallCount, 0)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.interactionState, .idle)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertEqual(assistant, "native-response")
    }

    @MainActor
    func testNativeLoopUnsupportedProviderSetsErrorWithoutSDKFallback() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready

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
            provider: .openai,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(adapter.callCount, 0)
        XCTAssertEqual(bridge.runCallCount, 0)
        XCTAssertEqual(viewModel.interactionState, .idle)
        XCTAssertTrue(viewModel.errorMessage?.contains("네이티브 에이전트 루프") == true)
    }

    @MainActor
    func testNativeLoopFailureSetsErrorWithoutSDKFallback() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready

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
            provider: .anthropic,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(bridge.runCallCount, 0)
        XCTAssertEqual(viewModel.interactionState, .idle)
        XCTAssertTrue(viewModel.errorMessage?.contains("network down") == true)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertNil(assistant)
    }

    @MainActor
    func testNativeRequestDropsToolsWhenCapabilityUnsupported() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready

        let adapter = StubNativeProviderAdapter(
            provider: .lmStudio,
            eventsPerRequest: [[.done(text: "native-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )
        let toolService = MockBuiltInToolService()
        toolService.stubbedSchemas = [sampleToolSchema()]

        let viewModel = makeViewModel(
            bridge: bridge,
            provider: .lmStudio,
            nativeLoopService: nativeService,
            toolService: toolService,
            model: "tinyllama"
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(220))

        let request = try XCTUnwrap(adapter.receivedRequests.first)
        XCTAssertTrue(request.tools.isEmpty)
    }

    @MainActor
    func testNativeRequestKeepsToolsWhenCapabilitySupported() async throws {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready

        let adapter = StubNativeProviderAdapter(
            provider: .ollama,
            eventsPerRequest: [[.done(text: "native-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )
        let toolService = MockBuiltInToolService()
        toolService.stubbedSchemas = [sampleToolSchema()]

        let viewModel = makeViewModel(
            bridge: bridge,
            provider: .ollama,
            nativeLoopService: nativeService,
            toolService: toolService,
            model: "llama3.2"
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(220))

        let request = try XCTUnwrap(adapter.receivedRequests.first)
        XCTAssertEqual(request.tools.count, 1)
        XCTAssertEqual(request.tools.first?.name, "calendar.create")
    }

    @MainActor
    func testTelegramMessageUsesNativeLoopAndSkipsRuntimeBridge() async {
        let bridge = MockRuntimeBridgeService()
        bridge.runtimeState = .ready

        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "telegram-native-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
            bridge: bridge,
            provider: .anthropic,
            nativeLoopService: nativeService,
            telegramStreamReplies: false
        )
        let telegram = MockTelegramService()
        viewModel.setTelegramService(telegram)

        await viewModel.handleTelegramMessage(TelegramUpdate(
            updateId: 1,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "ping"
        ))

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(bridge.openCallCount, 0)
        XCTAssertEqual(bridge.runCallCount, 0)
        XCTAssertEqual(telegram.sentMessages.last?.chatId, 123_456)
        XCTAssertEqual(telegram.sentMessages.last?.text, "telegram-native-response")
    }

    @MainActor
    private func makeViewModel(
        bridge: MockRuntimeBridgeService,
        provider: LLMProvider,
        nativeLoopService: NativeAgentLoopService,
        telegramStreamReplies: Bool = false,
        toolService: MockBuiltInToolService? = nil,
        model: String? = nil
    ) -> DochiViewModel {
        let resolvedToolService = toolService ?? MockBuiltInToolService()
        let settings = AppSettings()
        settings.nativeAgentLoopEnabled = true
        settings.llmProvider = provider.rawValue
        settings.llmModel = model ?? provider.onboardingDefaultModel
        settings.telegramStreamReplies = telegramStreamReplies

        return DochiViewModel(
            toolService: resolvedToolService,
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: SessionContext(workspaceId: UUID()),
            runtimeBridge: bridge,
            nativeAgentLoopService: nativeLoopService
        )
    }

    func sampleToolSchema() -> [String: Any] {
        [
            "function": [
                "name": "calendar.create",
                "description": "create calendar event",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string"
                        ]
                    ],
                    "required": ["title"]
                ]
            ]
        ]
    }
}

private final class StubNativeProviderAdapter: @unchecked Sendable, NativeLLMProviderAdapter {
    let provider: LLMProvider
    private let eventsPerRequest: [[NativeLLMStreamEvent]]
    private let errorsPerRequest: [Error?]
    private(set) var callCount: Int = 0
    private(set) var receivedRequests: [NativeLLMRequest] = []

    init(
        provider: LLMProvider,
        eventsPerRequest: [[NativeLLMStreamEvent]],
        errorsPerRequest: [Error?] = []
    ) {
        self.provider = provider
        self.eventsPerRequest = eventsPerRequest
        self.errorsPerRequest = errorsPerRequest
    }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        let index = min(callCount, max(0, eventsPerRequest.count - 1))
        let events = eventsPerRequest.isEmpty ? [] : eventsPerRequest[index]
        let error = errorsPerRequest.isEmpty ? nil : errorsPerRequest[min(index, errorsPerRequest.count - 1)]
        callCount += 1
        receivedRequests.append(request)

        return AsyncThrowingStream { continuation in
            Task {
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
