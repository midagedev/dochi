import XCTest
@testable import Dochi

final class NativeSessionRoutingTests: XCTestCase {

    @MainActor
    func testNativeLoopEnabledRoutesToNativePath() async throws {
        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
            provider: .anthropic,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.interactionState, .idle)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertEqual(assistant, "native-response")
    }

    @MainActor
    func testNativeLoopUnsupportedProviderSetsErrorWithoutSDKFallback() async throws {
        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
            provider: .openai,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(adapter.callCount, 0)
        XCTAssertEqual(viewModel.interactionState, .idle)
        XCTAssertTrue(viewModel.errorMessage?.contains("사용 가능한 네이티브 provider") == true)
    }

    @MainActor
    func testNativeLoopFailureSetsErrorWithoutSDKFallback() async throws {
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
            provider: .anthropic,
            nativeLoopService: nativeService
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(viewModel.interactionState, .idle)
        XCTAssertTrue(viewModel.errorMessage?.contains("network down") == true)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertNil(assistant)
    }

    @MainActor
    func testNativeRequestDropsToolsWhenCapabilityUnsupported() async throws {
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
    func testNativeLoopFallsBackToConfiguredProviderWhenPrimaryFails() async throws {
        let primaryAdapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[]],
            errorsPerRequest: [NativeLLMError(
                code: .network,
                message: "primary down",
                statusCode: nil,
                retryAfterSeconds: nil
            )]
        )
        let fallbackAdapter = StubNativeProviderAdapter(
            provider: .openai,
            eventsPerRequest: [[.done(text: "fallback-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [primaryAdapter, fallbackAdapter],
            toolService: MockBuiltInToolService()
        )

        let keychain = MockKeychainService()
        keychain.store[LLMProvider.anthropic.keychainAccount] = "anthropic-test-key"
        keychain.store[LLMProvider.openai.keychainAccount] = "openai-test-key"

        let viewModel = makeViewModel(
            provider: .anthropic,
            nativeLoopService: nativeService,
            keychainService: keychain,
            settingsTransform: { settings in
                settings.fallbackLLMProvider = LLMProvider.openai.rawValue
                settings.fallbackLLMModel = "gpt-4o-mini"
            }
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(320))

        XCTAssertEqual(primaryAdapter.callCount, 1)
        XCTAssertEqual(fallbackAdapter.callCount, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.interactionState, .idle)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertEqual(assistant, "fallback-response")
    }

    @MainActor
    func testNativeLoopCancelledDoesNotTriggerFallbackRetry() async throws {
        let primaryAdapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[]],
            errorsPerRequest: [NativeLLMError(
                code: .cancelled,
                message: "cancelled",
                statusCode: nil,
                retryAfterSeconds: nil
            )]
        )
        let fallbackAdapter = StubNativeProviderAdapter(
            provider: .openai,
            eventsPerRequest: [[.done(text: "fallback-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [primaryAdapter, fallbackAdapter],
            toolService: MockBuiltInToolService()
        )

        let keychain = MockKeychainService()
        keychain.store[LLMProvider.anthropic.keychainAccount] = "anthropic-test-key"
        keychain.store[LLMProvider.openai.keychainAccount] = "openai-test-key"

        let viewModel = makeViewModel(
            provider: .anthropic,
            nativeLoopService: nativeService,
            keychainService: keychain,
            settingsTransform: { settings in
                settings.fallbackLLMProvider = LLMProvider.openai.rawValue
                settings.fallbackLLMModel = "gpt-4o-mini"
            }
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(320))

        XCTAssertEqual(primaryAdapter.callCount, 1)
        XCTAssertEqual(fallbackAdapter.callCount, 0)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.interactionState, .idle)
        let assistant = viewModel.currentConversation?.messages.last(where: { $0.role == .assistant })?.content
        XCTAssertNil(assistant)
    }

    @MainActor
    func testNativeLoopRecordsUsageMetricsFromDoneEvent() async throws {
        let adapter = StubNativeProviderAdapter(
            provider: .openai,
            eventsPerRequest: [[.done(text: "usage-response", inputTokens: 21, outputTokens: 8)]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let keychain = MockKeychainService()
        keychain.store[LLMProvider.openai.keychainAccount] = "openai-test-key"
        let metricsCollector = MetricsCollector()
        let usageStore = MockUsageStore()
        metricsCollector.usageStore = usageStore

        let viewModel = makeViewModel(
            provider: .openai,
            nativeLoopService: nativeService,
            keychainService: keychain,
            metricsCollector: metricsCollector
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(260))

        XCTAssertEqual(metricsCollector.recentMetrics.count, 1)
        XCTAssertEqual(metricsCollector.recentMetrics.last?.inputTokens, 21)
        XCTAssertEqual(metricsCollector.recentMetrics.last?.outputTokens, 8)
        XCTAssertEqual(metricsCollector.recentTokenEstimationDeviations.count, 1)
        XCTAssertEqual(metricsCollector.recentTokenEstimationDeviations.last?.actualInputTokens, 21)
        XCTAssertGreaterThan(metricsCollector.recentTokenEstimationDeviations.last?.estimatedInputTokens ?? 0, 0)
        XCTAssertNotNil(metricsCollector.tokenEstimationDeviationReport)

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(usageStore.recordedMetrics.count, 1)
        XCTAssertEqual(usageStore.recordedMetrics.last?.inputTokens, 21)
        XCTAssertEqual(usageStore.recordedMetrics.last?.outputTokens, 8)

        let assistantMessage = try XCTUnwrap(viewModel.currentConversation?.messages.last(where: { $0.role == .assistant }))
        XCTAssertEqual(assistantMessage.metadata?.inputTokens, 21)
        XCTAssertEqual(assistantMessage.metadata?.outputTokens, 8)
    }

    @MainActor
    func testNativeLoopRecordsNilUsageWhenProviderDoesNotReturnUsage() async throws {
        let adapter = StubNativeProviderAdapter(
            provider: .ollama,
            eventsPerRequest: [[.done(text: "no-usage-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let metricsCollector = MetricsCollector()
        let usageStore = MockUsageStore()
        metricsCollector.usageStore = usageStore

        let viewModel = makeViewModel(
            provider: .ollama,
            nativeLoopService: nativeService,
            metricsCollector: metricsCollector
        )
        viewModel.inputText = "hello"
        viewModel.sendMessage()

        try await Task.sleep(for: .milliseconds(260))

        XCTAssertEqual(metricsCollector.recentMetrics.count, 1)
        XCTAssertNil(metricsCollector.recentMetrics.last?.inputTokens)
        XCTAssertNil(metricsCollector.recentMetrics.last?.outputTokens)
        XCTAssertTrue(metricsCollector.recentTokenEstimationDeviations.isEmpty)
        XCTAssertNil(metricsCollector.tokenEstimationDeviationReport)

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(usageStore.recordedMetrics.count, 1)
        XCTAssertNil(usageStore.recordedMetrics.last?.inputTokens)
        XCTAssertNil(usageStore.recordedMetrics.last?.outputTokens)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testTelegramMessageUsesNativeLoop() async {
        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "telegram-native-response")]]
        )
        let nativeService = NativeAgentLoopService(
            adapters: [adapter],
            toolService: MockBuiltInToolService()
        )

        let viewModel = makeViewModel(
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
        XCTAssertEqual(telegram.sentMessages.last?.chatId, 123_456)
        XCTAssertEqual(telegram.sentMessages.last?.text, "telegram-native-response")
    }

    @MainActor
    private func makeViewModel(
        provider: LLMProvider,
        nativeLoopService: NativeAgentLoopService,
        telegramStreamReplies: Bool = false,
        toolService: MockBuiltInToolService? = nil,
        model: String? = nil,
        keychainService: MockKeychainService? = nil,
        settingsTransform: ((AppSettings) -> Void)? = nil,
        metricsCollector: MetricsCollector? = nil
    ) -> DochiViewModel {
        let resolvedToolService = toolService ?? MockBuiltInToolService()
        let resolvedKeychainService = keychainService ?? MockKeychainService()
        let resolvedMetricsCollector = metricsCollector ?? MetricsCollector()
        let settings = AppSettings()
        settings.nativeAgentLoopEnabled = true
        settings.llmProvider = provider.rawValue
        settings.llmModel = model ?? provider.onboardingDefaultModel
        settings.telegramStreamReplies = telegramStreamReplies
        settingsTransform?(settings)
        let router = ModelRouterV2(
            settings: settings,
            readinessProbe: { _ in true },
            supportsProvider: { candidate in
                nativeLoopService.supports(provider: candidate)
            }
        )

        return DochiViewModel(
            toolService: resolvedToolService,
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: resolvedKeychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: SessionContext(workspaceId: UUID()),
            metricsCollector: resolvedMetricsCollector,
            nativeAgentLoopService: nativeLoopService,
            modelRouter: router
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
