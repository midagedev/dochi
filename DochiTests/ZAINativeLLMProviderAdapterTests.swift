import XCTest
@testable import Dochi

final class ZAINativeLLMProviderAdapterTests: XCTestCase {
    func testZAIAdapterParsesToolCallAndDoneEvents() async throws {
        let streamPayload = """
        data: {"choices":[{"delta":{"content":"안녕하세요"}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"calendar.create","arguments":"{\\"title\\":\\"회의\\"}"}}]},"finish_reason":"tool_calls"}]}

        data: [DONE]
        """

        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(streamPayload.utf8)
        )
        let adapter = ZAINativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(apiKey: "zai-test-key")

        let events = try await collectEvents(from: adapter.stream(request: request))

        XCTAssertTrue(events.contains(where: { $0.kind == .partial && $0.text == "안녕하세요" }))
        XCTAssertTrue(events.contains(where: { event in
            event.kind == .toolUse &&
                event.toolCallId == "call_1" &&
                event.toolName == "calendar.create"
        }))
        XCTAssertEqual(events.last?.kind, .done)

        let captured = await httpClient.capturedRequest()
        XCTAssertEqual(captured?.url, LLMProvider.zai.apiURL)
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer zai-test-key")

        guard let body = captured?.httpBody else {
            return XCTFail("Expected request body")
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["stream"] as? Bool, true)
        let streamOptions = try XCTUnwrap(object["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
    }

    func testZAIAdapterMapsUsageTokensFromOpenAICompatiblePayload() async throws {
        let streamPayload = """
        data: {"choices":[{"delta":{"content":"안녕"},"finish_reason":"stop"}]}

        data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":4}}

        data: [DONE]
        """

        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(streamPayload.utf8)
        )
        let adapter = ZAINativeLLMProviderAdapter(httpClient: httpClient)
        let events = try await collectEvents(from: adapter.stream(request: makeRequest(apiKey: "zai-test-key")))

        XCTAssertTrue(events.contains(where: { event in
            event.kind == .done &&
                event.inputTokens == 10 &&
                event.outputTokens == 4
        }))
    }

    func testZAIAdapterMapsAuthenticationError() async {
        let errorPayload = """
        {"error":{"type":"authentication_error","message":"invalid key"}}
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 401,
            headers: [:],
            body: Data(errorPayload.utf8)
        )
        let adapter = ZAINativeLLMProviderAdapter(httpClient: httpClient)

        do {
            _ = try await collectEvents(from: adapter.stream(request: makeRequest(apiKey: "bad-key")))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .authentication)
            XCTAssertEqual(error.statusCode, 401)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testZAIAdapterMapsRateLimitError() async {
        let errorPayload = """
        {"error":{"type":"rate_limit_error","message":"too many requests"}}
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 429,
            headers: ["Retry-After": "2"],
            body: Data(errorPayload.utf8)
        )
        let adapter = ZAINativeLLMProviderAdapter(httpClient: httpClient)

        do {
            _ = try await collectEvents(from: adapter.stream(request: makeRequest(apiKey: "zai-test-key")))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .rateLimited)
            XCTAssertEqual(error.statusCode, 429)
            XCTAssertEqual(error.retryAfterSeconds, 2)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testZAIAdapterMapsServerError() async {
        let errorPayload = """
        {"error":{"type":"server_error","message":"upstream error"}}
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 500,
            headers: [:],
            body: Data(errorPayload.utf8)
        )
        let adapter = ZAINativeLLMProviderAdapter(httpClient: httpClient)

        do {
            _ = try await collectEvents(from: adapter.stream(request: makeRequest(apiKey: "zai-test-key")))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .server)
            XCTAssertEqual(error.statusCode, 500)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testZAIAdapterRejectsNonZAIProviderRequest() async {
        let adapter = ZAINativeLLMProviderAdapter(httpClient: MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data()
        ))
        let wrongRequest = NativeLLMRequest(
            provider: .openai,
            model: "gpt-4o-mini",
            apiKey: "test-key",
            messages: [.init(role: .user, text: "hello")]
        )

        do {
            _ = try await collectEvents(from: adapter.stream(request: wrongRequest))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .unsupportedProvider)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

private extension ZAINativeLLMProviderAdapterTests {
    func makeRequest(apiKey: String?) -> NativeLLMRequest {
        NativeLLMRequest(
            provider: .zai,
            model: "glm-5",
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
