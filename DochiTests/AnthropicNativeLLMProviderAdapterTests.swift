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
}

final class OpenAINativeLLMProviderAdapterTests: XCTestCase {
    func testOpenAIAdapterParsesToolCallDeltasAndUsageDoneEvent() async throws {
        let streamPayload = """
        data: {"choices":[{"delta":{"content":"안녕"}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"calendar.","arguments":"{\\"title\\":\\"회의\\""}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"create","arguments":"}"}}]},"finish_reason":"tool_calls"}]}

        data: {"choices":[],"usage":{"prompt_tokens":21,"completion_tokens":8}}

        data: [DONE]
        """

        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(streamPayload.utf8)
        )
        let adapter = OpenAINativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .openai, apiKey: "test-openai-key")

        let events = try await collectEvents(from: adapter.stream(request: request))

        XCTAssertTrue(events.contains(where: { $0.kind == .partial && $0.text == "안녕" }))
        XCTAssertTrue(events.contains(where: { event in
            event.kind == .toolUse &&
                event.toolCallId == "call_1" &&
                event.toolName == "calendar.create" &&
                (event.toolInputJSON?.contains("\"title\":\"회의\"") ?? false)
        }))
        XCTAssertTrue(events.contains(where: { event in
            event.kind == .done &&
                event.inputTokens == 21 &&
                event.outputTokens == 8
        }))

        let captured = await httpClient.capturedRequest()
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer test-openai-key")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(captured?.httpMethod, "POST")
    }

    func testOpenAIAdapterRequestIncludesStreamUsageOption() async throws {
        let streamPayload = """
        data: [DONE]
        """

        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(streamPayload.utf8)
        )
        let adapter = OpenAINativeLLMProviderAdapter(httpClient: httpClient)
        let request = NativeLLMRequest(
            provider: .openai,
            model: "gpt-4o-mini",
            apiKey: "test-openai-key",
            systemPrompt: "system",
            messages: [.init(role: .user, text: "hello")],
            tools: [
                NativeLLMToolDefinition(
                    name: "calendar.create",
                    description: "create event",
                    inputSchema: [
                        "type": .string("object"),
                        "properties": .object([
                            "title": .object([
                                "type": .string("string")
                            ])
                        ])
                    ]
                )
            ]
        )

        _ = try await collectEvents(from: adapter.stream(request: request))
        let captured = await httpClient.capturedRequest()

        guard let body = captured?.httpBody else {
            return XCTFail("Expected request body")
        }

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["stream"] as? Bool, true)

        let streamOptions = try XCTUnwrap(object["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
    }

    func testOpenAIAdapterMapsRateLimitError() async {
        let errorPayload = """
        {"error":{"type":"rate_limit_error","message":"Too many requests"}}
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 429,
            headers: ["Retry-After": "3"],
            body: Data(errorPayload.utf8)
        )
        let adapter = OpenAINativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .openai, apiKey: "test-openai-key")

        do {
            _ = try await collectEvents(from: adapter.stream(request: request))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .rateLimited)
            XCTAssertEqual(error.statusCode, 429)
            XCTAssertEqual(error.retryAfterSeconds, 3)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testOpenAIAdapterMapsAuthenticationError() async {
        let errorPayload = """
        {"error":{"type":"authentication_error","message":"Invalid API key"}}
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 401,
            headers: [:],
            body: Data(errorPayload.utf8)
        )
        let adapter = OpenAINativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .openai, apiKey: "bad-openai-key")

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

    func testOpenAIAdapterMapsTimeoutError() async {
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(),
            stubbedError: URLError(.timedOut)
        )
        let adapter = OpenAINativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(provider: .openai, apiKey: "test-openai-key")

        do {
            _ = try await collectEvents(from: adapter.stream(request: request))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .timeout)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testOpenAIEventKindsMatchAnthropicForToolTurn() async throws {
        let openAIStreamPayload = """
        data: {"choices":[{"delta":{"content":"안녕하세요"}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"calendar.create","arguments":"{\\"title\\":\\"회의\\"}"}}]},"finish_reason":"tool_calls"}]}

        data: [DONE]
        """

        let anthropicStreamPayload = """
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"안녕하세요"}}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"call_1","name":"calendar.create","input":{"title":"회의"}}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        event: message_stop
        data: {"type":"message_stop","stop_reason":"end_turn"}
        """

        let openAIClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(openAIStreamPayload.utf8)
        )
        let anthropicClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(anthropicStreamPayload.utf8)
        )

        let openAIAdapter = OpenAINativeLLMProviderAdapter(httpClient: openAIClient)
        let anthropicAdapter = AnthropicNativeLLMProviderAdapter(httpClient: anthropicClient)

        let openAIEvents = try await collectEvents(
            from: openAIAdapter.stream(request: makeRequest(provider: .openai, apiKey: "test-openai-key"))
        )
        let anthropicEvents = try await collectEvents(
            from: anthropicAdapter.stream(request: makeRequest(provider: .anthropic, apiKey: "test-anthropic-key"))
        )

        XCTAssertEqual(openAIEvents.map(\.kind), anthropicEvents.map(\.kind))
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

private extension OpenAINativeLLMProviderAdapterTests {
    func makeRequest(provider: LLMProvider, apiKey: String?) -> NativeLLMRequest {
        NativeLLMRequest(
            provider: provider,
            model: provider == .openai ? "gpt-4o-mini" : "claude-sonnet-4-5-20250514",
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

private actor MockNativeLLMHTTPClient: NativeLLMHTTPClient {
    private let statusCode: Int
    private let headers: [String: String]
    private let body: Data
    private let stubbedError: Error?
    private(set) var lastRequest: URLRequest?

    init(
        statusCode: Int,
        headers: [String: String],
        body: Data,
        stubbedError: Error? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.stubbedError = stubbedError
    }

    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        lastRequest = request
        if let stubbedError {
            throw stubbedError
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
              ) else {
            throw NativeLLMError(
                code: .invalidResponse,
                message: "Failed to build HTTPURLResponse in test",
                statusCode: nil,
                retryAfterSeconds: nil
            )
        }
        return (body, response)
    }

    func capturedRequest() -> URLRequest? {
        lastRequest
    }
}
