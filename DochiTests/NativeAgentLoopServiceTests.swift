import XCTest
@testable import Dochi

@MainActor
final class NativeAgentLoopServiceTests: XCTestCase {
    func testNativeAgentLoopServiceRoutesToMatchingProviderAdapter() async throws {
        let anthropicAdapter = StaticNativeLLMProviderAdapter(
            provider: .anthropic,
            events: [.partial("anthropic"), .done(text: "anthropic")]
        )
        let openAIAdapter = StaticNativeLLMProviderAdapter(
            provider: .openai,
            events: [.partial("openai"), .done(text: "openai")]
        )
        let zaiAdapter = StaticNativeLLMProviderAdapter(
            provider: .zai,
            events: [.partial("zai"), .done(text: "zai")]
        )
        let ollamaAdapter = StaticNativeLLMProviderAdapter(
            provider: .ollama,
            events: [.partial("ollama"), .done(text: "ollama")]
        )
        let lmStudioAdapter = StaticNativeLLMProviderAdapter(
            provider: .lmStudio,
            events: [.partial("lmstudio"), .done(text: "lmstudio")]
        )

        let service = NativeAgentLoopService(
            adapters: [anthropicAdapter, openAIAdapter, zaiAdapter, ollamaAdapter, lmStudioAdapter]
        )

        let anthropicEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .anthropic)))
        XCTAssertEqual(anthropicEvents.first?.text, "anthropic")

        let openAIEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .openai)))
        XCTAssertEqual(openAIEvents.first?.text, "openai")

        let zaiEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .zai)))
        XCTAssertEqual(zaiEvents.first?.text, "zai")

        let ollamaEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .ollama)))
        XCTAssertEqual(ollamaEvents.first?.text, "ollama")

        let lmStudioEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .lmStudio)))
        XCTAssertEqual(lmStudioEvents.first?.text, "lmstudio")
    }

    func testNativeAgentLoopServiceReturnsUnsupportedProviderError() async {
        let service = NativeAgentLoopService(adapters: [
            StaticNativeLLMProviderAdapter(
                provider: .anthropic,
                events: [.done(text: nil)]
            ),
        ])

        do {
            _ = try await collectEvents(from: service.run(request: makeRequest(provider: .zai)))
            XCTFail("Expected NativeLLMError.unsupportedProvider")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .unsupportedProvider)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testNativeAgentLoopServiceRecordsFirstPartialLatencyMetric() async throws {
        let runtimeMetrics = MockRuntimeMetrics()
        let adapter = StaticNativeLLMProviderAdapter(
            provider: .anthropic,
            events: [.partial("hello"), .done(text: "hello")]
        )
        let service = NativeAgentLoopService(
            adapters: [adapter],
            runtimeMetrics: runtimeMetrics
        )

        _ = try await collectEvents(
            from: service.run(
                request: makeRequest(provider: .anthropic),
                hookContext: NativeAgentLoopHookContext(
                    sessionId: "session-metric-1",
                    workspaceId: "workspace-1",
                    agentId: "도치"
                )
            )
        )

        let keys = runtimeMetrics.histogramValues.keys.filter { $0.hasPrefix(MetricName.firstPartialLatencyMs) }
        XCTAssertEqual(keys.count, 1)
        let key = try XCTUnwrap(keys.first)
        XCTAssertTrue(key.contains("provider=anthropic"))
        XCTAssertTrue(key.contains("session=session-metric-1"))
        XCTAssertFalse(key.contains("tool="))
    }

    func testNativeAgentLoopServiceRecordsToolLatencyMetricWithStandardLabels() async throws {
        let runtimeMetrics = MockRuntimeMetrics()
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(toolCallId: "", content: "ok")

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { request in
            if request.messages.containsToolResult(toolCallId: "tool_1") {
                return [.done(text: "done")]
            }
            return [
                .toolUse(toolCallId: "tool_1", toolName: "calendar.create", toolInputJSON: "{\"title\":\"회의\"}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService,
            runtimeMetrics: runtimeMetrics
        )

        _ = try await collectEvents(
            from: service.run(
                request: makeRequest(provider: .anthropic),
                hookContext: NativeAgentLoopHookContext(
                    sessionId: "session-metric-2",
                    workspaceId: "workspace-2",
                    agentId: "도치"
                )
            )
        )

        let keys = runtimeMetrics.histogramValues.keys.filter { $0.hasPrefix(MetricName.toolLatencyMs) }
        XCTAssertEqual(keys.count, 1)
        let key = try XCTUnwrap(keys.first)
        XCTAssertTrue(key.contains("provider=anthropic"))
        XCTAssertTrue(key.contains("session=session-metric-2"))
        XCTAssertTrue(key.contains("tool=calendar.create"))
    }

    func testNativeAgentLoopServiceLiveMetricsAppearInSnapshotForGate() async throws {
        let runtimeMetrics = RuntimeMetrics()
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(toolCallId: "", content: "created")

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { request in
            if request.messages.containsToolResult(toolCallId: "tool_1") {
                return [.partial("완료"), .done(text: "완료")]
            }
            return [
                .toolUse(toolCallId: "tool_1", toolName: "calendar.create", toolInputJSON: "{\"title\":\"회의\"}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService,
            runtimeMetrics: runtimeMetrics
        )

        _ = try await collectEvents(
            from: service.run(
                request: makeRequest(provider: .anthropic),
                hookContext: NativeAgentLoopHookContext(
                    sessionId: "session-metric-3",
                    workspaceId: "workspace-3",
                    agentId: "도치"
                )
            )
        )

        let snapshot = runtimeMetrics.snapshot()
        let firstPartialHistograms = snapshot.histograms.values.filter { $0.name == MetricName.firstPartialLatencyMs }
        let toolLatencyHistograms = snapshot.histograms.values.filter { $0.name == MetricName.toolLatencyMs }
        XCTAssertFalse(firstPartialHistograms.isEmpty)
        XCTAssertFalse(toolLatencyHistograms.isEmpty)
    }

    func testNativeAgentLoopServiceExecutesToolAndReruns() async throws {
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(toolCallId: "", content: "created")

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { request in
            if request.messages.containsToolResult(toolCallId: "tool_1") {
                return [.partial("완료"), .done(text: "완료")]
            }
            return [
                .toolUse(toolCallId: "tool_1", toolName: "calendar.create", toolInputJSON: "{\"title\":\"회의\"}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService
        )

        let events = try await collectEvents(from: service.run(request: makeRequest(provider: .anthropic)))

        XCTAssertEqual(events.map(\.kind), [.toolUse, .toolResult, .partial, .done])
        XCTAssertEqual(toolService.executeCallCount, 1)
        XCTAssertEqual(toolService.lastExecutedName, "calendar.create")
        XCTAssertEqual(toolService.lastArguments?["title"] as? String, "회의")

        XCTAssertEqual(adapter.capturedRequests.count, 2)
        XCTAssertTrue(adapter.capturedRequests[1].messages.containsToolUse(toolCallId: "tool_1"))
        XCTAssertTrue(adapter.capturedRequests[1].messages.containsToolResult(toolCallId: "tool_1"))
    }

    func testNativeAgentLoopServiceExecutesMultiToolCallsBeforeRerun() async throws {
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(toolCallId: "", content: "ok")

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { request in
            if request.messages.toolResultCount >= 2 {
                return [.done(text: "done")]
            }
            return [
                .toolUse(toolCallId: "tool_1", toolName: "calendar.create", toolInputJSON: "{\"title\":\"A\"}"),
                .toolUse(toolCallId: "tool_2", toolName: "calculator", toolInputJSON: "{\"expression\":\"1+1\"}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService
        )

        let events = try await collectEvents(from: service.run(request: makeRequest(provider: .anthropic)))

        XCTAssertEqual(events.map(\.kind), [.toolUse, .toolUse, .toolResult, .toolResult, .done])
        XCTAssertEqual(toolService.executeCallCount, 2)
        XCTAssertEqual(adapter.capturedRequests.count, 2)
        XCTAssertEqual(adapter.capturedRequests[1].messages.toolResultCount, 2)
    }

    func testNativeAgentLoopServiceBlocksRepeatedToolSignatureWithGuard() async {
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(toolCallId: "", content: "ok")

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { _ in
            [
                .toolUse(toolCallId: "tool_1", toolName: "calendar.create", toolInputJSON: "{\"title\":\"A\"}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService,
            guardPolicy: NativeAgentLoopGuardPolicy(
                maxIterations: 8,
                maxRepeatedSignatures: 1
            )
        )

        let result = await collectEventsAndError(from: service.run(request: makeRequest(provider: .anthropic)))

        XCTAssertEqual(toolService.executeCallCount, 1)
        XCTAssertEqual(result.events.map(\.kind), [.toolUse, .toolResult, .toolUse])
        guard let error = result.error as? NativeLLMError else {
            return XCTFail("Expected NativeLLMError")
        }
        XCTAssertEqual(error.code, .loopGuardTriggered)
    }

    func testNativeAgentLoopServiceTerminatesOnToolError() async {
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(
            toolCallId: "",
            content: "permission denied",
            isError: true
        )

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { _ in
            [
                .toolUse(toolCallId: "tool_1", toolName: "shell.execute", toolInputJSON: "{\"cmd\":\"echo hi\"}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService
        )

        let result = await collectEventsAndError(from: service.run(request: makeRequest(provider: .anthropic)))

        XCTAssertEqual(result.events.map(\.kind), [.toolUse, .toolResult])
        XCTAssertEqual(result.events.last?.isToolResultError, true)
        XCTAssertEqual(toolService.executeCallCount, 1)
        XCTAssertEqual(adapter.capturedRequests.count, 1)

        guard let error = result.error as? NativeLLMError else {
            return XCTFail("Expected NativeLLMError")
        }
        XCTAssertEqual(error.code, .toolExecutionFailed)
    }

    func testNativeAgentLoopServiceRecordsStandardizedAuditFields() async throws {
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(toolCallId: "", content: "created")
        toolService.allToolInfos = [
            ToolInfo(
                name: "calendar.create",
                description: "create event",
                category: .sensitive,
                isBaseline: false,
                isEnabled: true,
                parameters: []
            ),
        ]

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { request in
            if request.messages.containsToolResult(toolCallId: "tool_1") {
                return [.done(text: "done")]
            }
            return [
                .toolUse(toolCallId: "tool_1", toolName: "calendar.create", toolInputJSON: "{\"title\":\"회의\"}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService
        )

        _ = try await collectEvents(
            from: service.run(
                request: makeRequest(provider: .anthropic),
                hookContext: NativeAgentLoopHookContext(
                    sessionId: "native-session-1",
                    workspaceId: "workspace-1",
                    agentId: "도치"
                )
            )
        )

        XCTAssertEqual(service.auditLog.count, 1)
        guard let audit = service.auditLog.first else {
            return XCTFail("Expected audit event")
        }
        XCTAssertEqual(audit.toolCallId, "tool_1")
        XCTAssertEqual(audit.sessionId, "native-session-1")
        XCTAssertEqual(audit.agentId, "도치")
        XCTAssertEqual(audit.toolName, "calendar.create")
        XCTAssertEqual(audit.riskLevel, ToolCategory.sensitive.rawValue)
        XCTAssertEqual(audit.decision, .approved)
        XCTAssertFalse(audit.argumentsHash.isEmpty)
        XCTAssertNil(audit.resultCode)
    }

    func testNativeAgentLoopServiceAppliesPreHookBlockAndAuditsDecision() async {
        let toolService = MockBuiltInToolService()
        toolService.allToolInfos = [
            ToolInfo(
                name: "shell.execute",
                description: "run shell",
                category: .restricted,
                isBaseline: false,
                isEnabled: true,
                parameters: []
            ),
        ]

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { _ in
            [
                .toolUse(toolCallId: "tool_1", toolName: "shell.execute", toolInputJSON: "{\"cmd\":\"rm -rf /\"}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService
        )

        let result = await collectEventsAndError(
            from: service.run(
                request: makeRequest(provider: .anthropic),
                hookContext: NativeAgentLoopHookContext(
                    sessionId: "native-session-2",
                    workspaceId: "workspace-2",
                    agentId: "도치"
                )
            )
        )

        XCTAssertEqual(result.events.map(\.kind), [.toolUse, .toolResult])
        XCTAssertEqual(toolService.executeCallCount, 0)
        guard let error = result.error as? NativeLLMError else {
            return XCTFail("Expected NativeLLMError")
        }
        XCTAssertEqual(error.code, .toolExecutionFailed)

        XCTAssertEqual(service.auditLog.count, 1)
        guard let audit = service.auditLog.first else {
            return XCTFail("Expected audit event")
        }
        XCTAssertEqual(audit.decision, .hookBlocked)
        XCTAssertEqual(audit.hookName, "ForbiddenPattern")
        XCTAssertEqual(audit.riskLevel, ToolCategory.restricted.rawValue)
        XCTAssertEqual(audit.resultCode, BridgeErrorCode.toolPermissionDenied.rawValue)
    }

    func testNativeAgentLoopServiceForwardsMemoryCandidateToPipeline() async throws {
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(
            toolCallId: "",
            content: "오늘 일정: 14시 제품 리뷰 미팅, 16시 디자인 동기화"
        )
        toolService.allToolInfos = [
            ToolInfo(
                name: "calendar.today",
                description: "today",
                category: .safe,
                isBaseline: true,
                isEnabled: true,
                parameters: []
            ),
        ]

        let memoryPipeline = MockMemoryPipelineService()
        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { request in
            if request.messages.containsToolResult(toolCallId: "tool_1") {
                return [.done(text: "done")]
            }
            return [
                .toolUse(toolCallId: "tool_1", toolName: "calendar.today", toolInputJSON: "{}"),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService,
            memoryPipeline: memoryPipeline
        )

        _ = try await collectEvents(
            from: service.run(
                request: makeRequest(provider: .anthropic),
                hookContext: NativeAgentLoopHookContext(
                    sessionId: "native-session-3",
                    workspaceId: "workspace-3",
                    agentId: "도치"
                )
            )
        )
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(memoryPipeline.submitCallCount, 1)
        guard let candidate = memoryPipeline.submittedCandidates.first else {
            return XCTFail("Expected memory candidate")
        }
        XCTAssertEqual(candidate.sessionId, "native-session-3")
        XCTAssertEqual(candidate.workspaceId, "workspace-3")
        XCTAssertEqual(candidate.agentId, "도치")
        XCTAssertEqual(candidate.source, .toolResult)
    }

    func testNativeAgentLoopServiceHandlesOutOfRangeUnsignedArguments() async throws {
        let toolService = MockBuiltInToolService()
        toolService.stubbedResult = ToolResult(toolCallId: "", content: "ok")
        toolService.allToolInfos = [
            ToolInfo(
                name: "calculator",
                description: "calculate",
                category: .safe,
                isBaseline: true,
                isEnabled: true,
                parameters: []
            ),
        ]

        let adapter = CapturingNativeLLMProviderAdapter(provider: .anthropic) { request in
            if request.messages.containsToolResult(toolCallId: "tool_1") {
                return [.done(text: "done")]
            }
            return [
                .toolUse(
                    toolCallId: "tool_1",
                    toolName: "calculator",
                    toolInputJSON: "{\"n\":18446744073709551615}"
                ),
                .done(text: nil),
            ]
        }

        let service = NativeAgentLoopService(
            adapters: [adapter],
            toolService: toolService
        )

        _ = try await collectEvents(
            from: service.run(
                request: makeRequest(provider: .anthropic),
                hookContext: NativeAgentLoopHookContext(
                    sessionId: "native-session-5",
                    workspaceId: "workspace-5",
                    agentId: "도치"
                )
            )
        )

        XCTAssertEqual(toolService.executeCallCount, 1)
        guard let audit = service.auditLog.first else {
            return XCTFail("Expected audit event for out-of-range integer argument")
        }
        XCTAssertFalse(audit.argumentsHash.isEmpty)
    }

    func testNativeAgentLoopServiceRunsSessionCloseAndStopHooks() async throws {
        let spyHook = SpyLifecycleHook()
        let hookPipeline = HookPipeline()
        hookPipeline.registerLifecycleHook(spyHook)

        let adapter = StaticNativeLLMProviderAdapter(
            provider: .anthropic,
            events: [.done(text: "done")]
        )

        let service = NativeAgentLoopService(
            adapters: [adapter],
            hookPipeline: hookPipeline
        )

        _ = try await collectEvents(
            from: service.run(
                request: makeRequest(provider: .anthropic),
                hookContext: NativeAgentLoopHookContext(
                    sessionId: "native-session-4",
                    workspaceId: "workspace-4",
                    agentId: "도치"
                )
            )
        )

        XCTAssertEqual(spyHook.sessionCloseCallCount, 1)
        XCTAssertEqual(spyHook.lastSessionId, "native-session-4")

        service.runStopHooks()
        XCTAssertEqual(spyHook.stopCallCount, 1)
    }
}

private extension NativeAgentLoopServiceTests {
    func makeRequest(provider: LLMProvider) -> NativeLLMRequest {
        NativeLLMRequest(
            provider: provider,
            model: "test-model",
            apiKey: "test-key",
            messages: [.init(role: .user, text: "hello")]
        )
    }

    func collectEvents(
        from stream: AsyncThrowingStream<NativeLLMStreamEvent, Error>
    ) async throws -> [NativeLLMStreamEvent] {
        var events: [NativeLLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func collectEventsAndError(
        from stream: AsyncThrowingStream<NativeLLMStreamEvent, Error>
    ) async -> (events: [NativeLLMStreamEvent], error: Error?) {
        var events: [NativeLLMStreamEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
            return (events, nil)
        } catch {
            return (events, error)
        }
    }
}

private struct StaticNativeLLMProviderAdapter: NativeLLMProviderAdapter {
    let provider: LLMProvider
    let events: [NativeLLMStreamEvent]

    func stream(request _: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private final class CapturingNativeLLMProviderAdapter: @unchecked Sendable, NativeLLMProviderAdapter {
    typealias EventBuilder = @Sendable (NativeLLMRequest) throws -> [NativeLLMStreamEvent]

    let provider: LLMProvider
    private let eventBuilder: EventBuilder
    private(set) var capturedRequests: [NativeLLMRequest] = []

    init(provider: LLMProvider, eventBuilder: @escaping EventBuilder) {
        self.provider = provider
        self.eventBuilder = eventBuilder
    }

    func stream(request: NativeLLMRequest) -> AsyncThrowingStream<NativeLLMStreamEvent, Error> {
        capturedRequests.append(request)
        return AsyncThrowingStream { continuation in
            do {
                let events = try eventBuilder(request)
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

@MainActor
private final class SpyLifecycleHook: SessionLifecycleHook {
    let name = "SpyLifecycle"
    private(set) var sessionCloseCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastSessionId: String?

    func onSessionClose(sessionId: String, auditLog _: [ToolAuditEvent]) {
        sessionCloseCallCount += 1
        lastSessionId = sessionId
    }

    func onStop(auditLog _: [ToolAuditEvent]) {
        stopCallCount += 1
    }
}

private extension Array where Element == NativeLLMMessage {
    var toolResultCount: Int {
        reduce(into: 0) { count, message in
            count += message.contents.filter {
                if case .toolResult = $0 { return true }
                return false
            }.count
        }
    }

    func containsToolResult(toolCallId: String) -> Bool {
        contains { message in
            message.contents.contains {
                if case .toolResult(let id, _, _) = $0 {
                    return id == toolCallId
                }
                return false
            }
        }
    }

    func containsToolUse(toolCallId: String) -> Bool {
        contains { message in
            message.contents.contains {
                if case .toolUse(let id, _, _) = $0 {
                    return id == toolCallId
                }
                return false
            }
        }
    }
}
