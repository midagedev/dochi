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

        let service = NativeAgentLoopService(adapters: [anthropicAdapter, openAIAdapter])

        let anthropicEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .anthropic)))
        XCTAssertEqual(anthropicEvents.first?.text, "anthropic")

        let openAIEvents = try await collectEvents(from: service.run(request: makeRequest(provider: .openai)))
        XCTAssertEqual(openAIEvents.first?.text, "openai")
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
                .toolUse(toolCallId: "tool_1", toolName: "shell.execute", toolInputJSON: "{\"cmd\":\"rm -rf /\"}"),
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
