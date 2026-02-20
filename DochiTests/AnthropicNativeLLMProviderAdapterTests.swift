import XCTest
@testable import Dochi

final class AnthropicNativeLLMProviderAdapterTests: XCTestCase {
    func testAnthropicAdapterParsesPartialToolUseAndDoneEvents() async throws {
        let streamPayload = """
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"안녕하세요"}}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"calendar.create","input":{"title":"회의"}}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        event: message_stop
        data: {"type":"message_stop","stop_reason":"end_turn"}
        """

        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(streamPayload.utf8)
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        let events = try await collectEvents(from: adapter.stream(request: request))

        XCTAssertTrue(events.contains(where: { $0.kind == .partial && $0.text == "안녕하세요" }))
        XCTAssertTrue(events.contains(where: { event in
            event.kind == .toolUse &&
                event.toolCallId == "toolu_1" &&
                event.toolName == "calendar.create" &&
                (event.toolInputJSON?.contains("\"title\":\"회의\"") ?? false)
        }))
        XCTAssertEqual(events.last?.kind, .done)

        let captured = await httpClient.capturedRequest()
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(captured?.httpMethod, "POST")
    }

    func testAnthropicAdapterMapsRateLimitError() async {
        let errorPayload = """
        {"error":{"type":"rate_limit_error","message":"Too many requests"}}
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 429,
            headers: ["Retry-After": "7"],
            body: Data(errorPayload.utf8)
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        do {
            _ = try await collectEvents(from: adapter.stream(request: request))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .rateLimited)
            XCTAssertEqual(error.statusCode, 429)
            XCTAssertEqual(error.retryAfterSeconds, 7)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAnthropicAdapterMapsAuthenticationError() async {
        let errorPayload = """
        {"error":{"type":"authentication_error","message":"Invalid API key"}}
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 401,
            headers: [:],
            body: Data(errorPayload.utf8)
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "bad-key")

        do {
            _ = try await collectEvents(from: adapter.stream(request: request))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .authentication)
            XCTAssertEqual(error.statusCode, 401)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAnthropicAdapterMapsTimeoutError() async {
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            stubbedError: URLError(.timedOut)
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        do {
            _ = try await collectEvents(from: adapter.stream(request: request))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .timeout)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAnthropicAdapterMapsCancellationAsInterrupted() async {
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            stubbedError: CancellationError()
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        do {
            _ = try await collectEvents(from: adapter.stream(request: request))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAnthropicAdapterEmitsPartialBeforeStreamCompletion() async throws {
        let streamLines = [
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"partial-now\"}}",
            "",
            ": heartbeat",
            ": heartbeat",
            ": heartbeat",
            ": heartbeat",
            ": heartbeat",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
            "",
        ]
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            streamLines: streamLines,
            streamLineDelayNanoseconds: 25_000_000
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        let stream = adapter.stream(request: request)
        var iterator = stream.makeAsyncIterator()
        let startedAt = Date()

        let first = try await iterator.next()
        let firstLatency = Date().timeIntervalSince(startedAt)
        let second = try await iterator.next()
        let totalLatency = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(first?.kind, .partial)
        XCTAssertEqual(first?.text, "partial-now")
        XCTAssertLessThan(firstLatency, totalLatency)
        XCTAssertGreaterThan(totalLatency - firstLatency, 0.05)
        XCTAssertEqual(second?.kind, .done)
        let streamingCalls = await httpClient.sendStreamingCallCount
        let sendCalls = await httpClient.sendCallCount
        XCTAssertEqual(streamingCalls, 1)
        XCTAssertEqual(sendCalls, 0)
    }

    func testAnthropicAdapterCancelsNetworkStreamWhenConsumerStopsEarly() async throws {
        let streamLines = [
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"first\"}}",
            "",
            ": heartbeat",
            ": heartbeat",
            ": heartbeat",
            ": heartbeat",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
            "",
        ]
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            streamLines: streamLines,
            streamLineDelayNanoseconds: 30_000_000
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        let firstEventTask = Task<NativeLLMStreamEvent?, Error> {
            for try await event in adapter.stream(request: request) {
                return event
            }
            return nil
        }

        let first = try await firstEventTask.value
        XCTAssertEqual(first?.kind, .partial)
        XCTAssertEqual(first?.text, "first")

        try await Task.sleep(nanoseconds: 80_000_000)
        let cancelled = await httpClient.didCancelStream()
        XCTAssertTrue(cancelled)
    }

    func testIncrementalSSEStreamParsesPartialJsonDelta() async throws {
        let streamLines = [
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_2\",\"name\":\"weather.get\",\"input\":{}}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"city\\\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\":\\\"Seoul\\\"}\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
            "",
        ]
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            streamLines: streamLines
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        let events = try await collectEvents(from: adapter.stream(request: request))

        let toolEvent = events.first(where: { $0.kind == .toolUse })
        XCTAssertNotNil(toolEvent)
        XCTAssertEqual(toolEvent?.toolCallId, "toolu_2")
        XCTAssertEqual(toolEvent?.toolName, "weather.get")
        XCTAssertTrue(toolEvent?.toolInputJSON?.contains("Seoul") ?? false)
        XCTAssertEqual(events.last?.kind, .done)
    }

    func testIncrementalSSEStreamHandlesSSEErrorEvent() async {
        let streamLines = [
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"partial\"}}",
            "",
            "event: error",
            "data: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Server overloaded\"}}",
            "",
        ]
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            streamLines: streamLines
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        do {
            _ = try await collectEvents(from: adapter.stream(request: request))
            XCTFail("Expected NativeLLMError to be thrown")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .server)
            XCTAssertTrue(error.message.contains("Server overloaded"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testIncrementalSSEStreamMultipleTextDeltas() async throws {
        let streamLines = [
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" World\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"!\"}}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
            "",
        ]
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            streamLines: streamLines
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        let events = try await collectEvents(from: adapter.stream(request: request))

        let partials = events.filter { $0.kind == .partial }
        XCTAssertEqual(partials.count, 3)
        XCTAssertEqual(partials[0].text, "Hello")
        XCTAssertEqual(partials[1].text, " World")
        XCTAssertEqual(partials[2].text, "!")
        XCTAssertEqual(events.last?.kind, .done)
    }

    func testIncrementalSSEStreamEmptyBodyYieldsDone() async throws {
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            streamLines: []
        )
        let adapter = AnthropicNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .anthropic, apiKey: "test-key")

        let events = try await collectEvents(from: adapter.stream(request: request))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .done)
    }
}

private extension AnthropicNativeLLMProviderAdapterTests {
    func makeRequest(provider: LLMProvider, apiKey: String?) -> NativeLLMRequest {
        NativeLLMRequest(
            provider: provider,
            model: "claude-sonnet-4-5-20250514",
            apiKey: apiKey,
            systemPrompt: "테스트 시스템 프롬프트",
            messages: [.init(role: .user, text: "안녕")]
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
}
