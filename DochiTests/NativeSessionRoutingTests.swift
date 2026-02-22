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
    func testTelegramMessageSendsFailureNoticeOnNativeLoopThrow() async {
        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[]],
            errorsPerRequest: [
                NativeLLMError(
                    code: .network,
                    message: "network down",
                    statusCode: nil,
                    retryAfterSeconds: nil
                ),
            ]
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
            updateId: 99,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "ping"
        ))

        XCTAssertEqual(adapter.callCount, 1)
        XCTAssertEqual(telegram.sentMessages.last?.chatId, 123_456)
        XCTAssertTrue(telegram.sentMessages.last?.text.contains("요청 처리 중 오류가 발생했습니다") == true)
    }

    @MainActor
    func testTelegramBridgeCommandBypassesNativeLoop() async throws {
        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native-should-not-run")]]
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

        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(
            name: "Codex",
            command: "codex",
            workingDirectory: "/tmp/repo"
        )
        manager.saveProfile(profile)
        manager.sessions = [
            ExternalToolSession(
                id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                profileId: profile.id,
                tmuxSessionName: "mock-session",
                status: .idle,
                startedAt: Date()
            ),
        ]
        viewModel.configureExternalToolManager(manager)

        let telegram = MockTelegramService()
        viewModel.setTelegramService(telegram)

        await viewModel.handleTelegramMessage(TelegramUpdate(
            updateId: 1,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "/bridge status"
        ))

        XCTAssertEqual(adapter.callCount, 0)
        XCTAssertEqual(telegram.sentMessages.last?.chatId, 123_456)
        XCTAssertTrue(telegram.sentMessages.last?.text.contains("Codex") == true)
    }

    @MainActor
    func testTelegramBridgeRootsCommandBypassesNativeLoopAndListsRoots() async throws {
        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native-should-not-run")]]
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

        let manager = MockExternalToolSessionManager()
        manager.mockGitRepositoryInsights = [
            GitRepositoryInsight(
                workDomain: "dochi",
                workDomainConfidence: 0.95,
                workDomainReason: "matched owner",
                path: "/tmp/project-alpha",
                name: "project-alpha",
                branch: "main",
                originURL: "git@github.com:org/project-alpha.git",
                remoteHost: "github.com",
                remoteOwner: "org",
                remoteRepository: "project-alpha",
                lastCommitEpoch: 1_700_000_000,
                lastCommitISO8601: "2023-11-14T00:00:00Z",
                lastCommitRelative: "1h ago",
                upstreamLastCommitEpoch: 1_700_000_000,
                upstreamLastCommitISO8601: "2023-11-14T00:00:00Z",
                upstreamLastCommitRelative: "1h ago",
                daysSinceLastCommit: 0,
                recentCommitCount30d: 20,
                changedFileCount: 3,
                untrackedFileCount: 1,
                aheadCount: 0,
                behindCount: 0,
                score: 88
            ),
        ]
        viewModel.configureExternalToolManager(manager)

        let telegram = MockTelegramService()
        viewModel.setTelegramService(telegram)

        await viewModel.handleTelegramMessage(TelegramUpdate(
            updateId: 2,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "/bridge roots --limit 1"
        ))

        XCTAssertEqual(adapter.callCount, 0)
        XCTAssertEqual(telegram.sentMessages.last?.chatId, 123_456)
        XCTAssertTrue(telegram.sentMessages.last?.text.contains("/tmp/project-alpha") == true)
    }

    @MainActor
    func testTelegramBridgeRepoInitCommandBypassesNativeLoop() async throws {
        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native-should-not-run")]]
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

        let manager = MockExternalToolSessionManager()
        viewModel.configureExternalToolManager(manager)

        let telegram = MockTelegramService()
        viewModel.setTelegramService(telegram)

        await viewModel.handleTelegramMessage(TelegramUpdate(
            updateId: 3,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "/bridge repo init /tmp/new-repo --branch develop --readme --gitignore"
        ))

        XCTAssertEqual(adapter.callCount, 0)
        XCTAssertEqual(manager.initializeRepositoryCallCount, 1)
        XCTAssertTrue(telegram.sentMessages.last?.text.contains("default_branch: develop") == true)
    }

    @MainActor
    func testTelegramOrchestratorApprovalFlowConsumesTokenOnce() async throws {
        let adapter = StubNativeProviderAdapter(
            provider: .anthropic,
            eventsPerRequest: [[.done(text: "native-should-not-run")]]
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

        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(
            name: "Codex",
            command: "codex",
            workingDirectory: "/tmp/repo"
        )
        manager.saveProfile(profile)

        let runtimeSessionId = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        manager.sessions = [
            ExternalToolSession(
                id: runtimeSessionId,
                profileId: profile.id,
                tmuxSessionName: "mock-session",
                status: .idle,
                startedAt: Date()
            ),
        ]
        manager.mockOrchestrationSelection = OrchestrationSessionSelection(
            action: .attachT1,
            reason: "attach path",
            repositoryRoot: "/tmp/repo",
            selectedSession: UnifiedCodingSession(
                source: "test",
                runtimeType: .tmux,
                controllabilityTier: .t1Attach,
                provider: "codex",
                nativeSessionId: "sess-telegram",
                runtimeSessionId: runtimeSessionId.uuidString,
                workingDirectory: "/tmp/repo",
                repositoryRoot: "/tmp/repo",
                path: "/tmp/sess-telegram.jsonl",
                updatedAt: Date(),
                isActive: true,
                activityScore: 95,
                activityState: .active
            )
        )
        manager.mockOrchestrationDecision = OrchestrationExecutionDecision(
            kind: .allowed,
            policyCode: .t1AllowNonDestructive,
            commandClass: .nonDestructive,
            reason: "allowed",
            isDestructiveCommand: false
        )
        viewModel.configureExternalToolManager(manager)

        let telegram = MockTelegramService()
        viewModel.setTelegramService(telegram)

        await viewModel.handleTelegramMessage(TelegramUpdate(
            updateId: 10,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "/orch request git status --repo /tmp/repo"
        ))

        let requestText = try XCTUnwrap(telegram.sentMessages.last?.text)
        let approvalId = try XCTUnwrap(extractField(named: "approval_id", from: requestText))
        let challengeCode = try XCTUnwrap(extractField(named: "challenge_code", from: requestText))

        await viewModel.handleTelegramMessage(TelegramUpdate(
            updateId: 11,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "/orch approve \(approvalId) \(challengeCode)"
        ))
        XCTAssertTrue(telegram.sentMessages.last?.text.contains("승인이 완료") == true)

        await viewModel.handleTelegramMessage(TelegramUpdate(
            updateId: 12,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "/orch execute git status --repo /tmp/repo --approval-id \(approvalId)"
        ))
        XCTAssertEqual(manager.sendCommandCallCount, 1)
        XCTAssertTrue(telegram.sentMessages.last?.text.contains("전송") == true)

        await viewModel.handleTelegramMessage(TelegramUpdate(
            updateId: 13,
            chatId: 123_456,
            senderId: 42,
            senderUsername: "tester",
            text: "/orch execute git status --repo /tmp/repo --approval-id \(approvalId)"
        ))
        XCTAssertEqual(manager.sendCommandCallCount, 1)
        XCTAssertTrue(telegram.sentMessages.last?.text.contains("이미 사용") == true)
        XCTAssertEqual(adapter.callCount, 0)
    }

    @MainActor
    private func extractField(named key: String, from text: String) -> String? {
        let prefix = "\(key):"
        for line in text.components(separatedBy: .newlines) {
            guard line.contains(prefix) else { continue }
            if let range = line.range(of: prefix) {
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
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
