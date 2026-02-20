import XCTest
@testable import Dochi

final class LMStudioNativeLLMProviderAdapterTests: XCTestCase {
    func testLMStudioAdapterParsesToolCallAndDoneEvents() async throws {
        let streamPayload = """
        data: {"choices":[{"delta":{"content":"hello"}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"calendar.create","arguments":"{\\"title\\":\\"회의\\"}"}}]},"finish_reason":"tool_calls"}]}

        data: {"choices":[],"usage":{"prompt_tokens":9,"completion_tokens":3}}

        data: [DONE]
        """

        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(streamPayload.utf8)
        )
        let adapter = LMStudioNativeLLMProviderAdapter(httpClient: httpClient)
        let request = makeRequest(apiKey: nil)

        let events = try await collectEvents(from: adapter.stream(request: request))

        XCTAssertTrue(events.contains(where: { $0.kind == .partial && $0.text == "hello" }))
        XCTAssertTrue(events.contains(where: { event in
            event.kind == .toolUse &&
                event.toolCallId == "call_1" &&
                event.toolName == "calendar.create"
        }))
        XCTAssertTrue(events.contains(where: { event in
            event.kind == .done &&
                event.inputTokens == 9 &&
                event.outputTokens == 3
        }))

        let captured = await httpClient.capturedRequest()
        XCTAssertEqual(captured?.url, URL(string: "http://localhost:1234/v1/chat/completions"))
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer lmstudio-local")
    }

    func testLMStudioAdapterMapsServerError() async {
        let errorPayload = """
        {"error":{"type":"server_error","message":"service unavailable"}}
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 500,
            headers: [:],
            body: Data(errorPayload.utf8)
        )
        let adapter = LMStudioNativeLLMProviderAdapter(httpClient: httpClient)

        do {
            _ = try await collectEvents(from: adapter.stream(request: makeRequest(apiKey: nil)))
            XCTFail("Expected NativeLLMError")
        } catch let error as NativeLLMError {
            XCTAssertEqual(error.code, .server)
            XCTAssertEqual(error.statusCode, 500)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLMStudioAdapterRejectsNonLMStudioProviderRequest() async {
        let adapter = LMStudioNativeLLMProviderAdapter(httpClient: MockNativeLLMHTTPClient(
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

    func testLMStudioAdapterUsesCustomEndpointOverride() async throws {
        let streamPayload = """
        data: [DONE]
        """
        let httpClient = MockNativeLLMHTTPClient(
            statusCode: 200,
            headers: [:],
            body: Data(streamPayload.utf8)
        )
        let adapter = LMStudioNativeLLMProviderAdapter(httpClient: httpClient)
        let customEndpoint = URL(string: "http://127.0.0.1:1240/v1/chat/completions")!
        let request = NativeLLMRequest(
            provider: .lmStudio,
            model: "qwen2.5-7b-instruct",
            apiKey: nil,
            messages: [.init(role: .user, text: "hello")],
            endpointURL: customEndpoint
        )

        _ = try await collectEvents(from: adapter.stream(request: request))
        let captured = await httpClient.capturedRequest()
        XCTAssertEqual(captured?.url, customEndpoint)
    }
}

private extension LMStudioNativeLLMProviderAdapterTests {
    func makeRequest(apiKey: String?) -> NativeLLMRequest {
        NativeLLMRequest(
            provider: .lmStudio,
            model: "qwen2.5-7b-instruct",
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
