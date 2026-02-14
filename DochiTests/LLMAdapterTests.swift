import XCTest
@testable import Dochi

final class LLMAdapterTests: XCTestCase {

    // MARK: - OpenAI Request Building

    @MainActor
    func testOpenAIRequestHeaders() throws {
        let adapter = OpenAIAdapter()
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "You are helpful.",
            model: "gpt-4o",
            tools: nil,
            apiKey: "sk-test-key"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.url, LLMProvider.openai.apiURL)
    }

    @MainActor
    func testOpenAIRequestBody() throws {
        let adapter = OpenAIAdapter()
        let messages = [Message(role: .user, content: "Hello")]
        let request = try adapter.buildRequest(
            messages: messages,
            systemPrompt: "Be helpful",
            model: "gpt-4o",
            tools: nil,
            apiKey: "key"
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "gpt-4o")
        XCTAssertEqual(body["stream"] as? Bool, true)

        let apiMessages = body["messages"] as! [[String: Any]]
        // First message should be system prompt
        XCTAssertEqual(apiMessages[0]["role"] as? String, "system")
        XCTAssertEqual(apiMessages[0]["content"] as? String, "Be helpful")
        // Second should be user
        XCTAssertEqual(apiMessages[1]["role"] as? String, "user")
        XCTAssertEqual(apiMessages[1]["content"] as? String, "Hello")
    }

    @MainActor
    func testOpenAIRequestWithTools() throws {
        let adapter = OpenAIAdapter()
        let tools: [[String: Any]] = [
            ["type": "function", "function": ["name": "test", "description": "A test tool"]]
        ]
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "",
            model: "gpt-4o",
            tools: tools,
            apiKey: "key"
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertNotNil(body["tools"])
    }

    // MARK: - OpenAI SSE Parsing

    func testOpenAIParseTextDelta() {
        let adapter = OpenAIAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"choices":[{"delta":{"content":"Hello"},"index":0}]}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .partial(let text) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected .partial, got \(String(describing: event))")
        }
        XCTAssertEqual(acc.text, "Hello")
    }

    func testOpenAIParseMultipleDeltas() {
        let adapter = OpenAIAdapter()
        var acc = StreamAccumulator()

        let lines = [
            #"data: {"choices":[{"delta":{"content":"He"},"index":0}]}"#,
            #"data: {"choices":[{"delta":{"content":"llo"},"index":0}]}"#,
            #"data: {"choices":[{"delta":{"content":" world"},"index":0}]}"#,
        ]

        for line in lines {
            _ = adapter.parseSSELine(line, accumulated: &acc)
        }

        XCTAssertEqual(acc.text, "Hello world")
    }

    func testOpenAIParseDone() {
        let adapter = OpenAIAdapter()
        var acc = StreamAccumulator()

        let event = adapter.parseSSELine("data: [DONE]", accumulated: &acc)
        if case .done = event {
            // success
        } else {
            XCTFail("Expected .done")
        }
    }

    func testOpenAIParseToolCallDelta() {
        let adapter = OpenAIAdapter()
        var acc = StreamAccumulator()

        // First chunk: id and name
        let line1 = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_123","function":{"name":"tools.list","arguments":""}}]},"index":0}]}"#
        let event1 = adapter.parseSSELine(line1, accumulated: &acc)
        if case .toolCallDelta(let index, let id, let name, _) = event1 {
            XCTAssertEqual(index, 0)
            XCTAssertEqual(id, "call_123")
            XCTAssertEqual(name, "tools.list")
        } else {
            XCTFail("Expected .toolCallDelta")
        }

        // Second chunk: arguments
        let line2 = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"key\":"}}]},"index":0}]}"#
        _ = adapter.parseSSELine(line2, accumulated: &acc)

        let line3 = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"val\"}"}}]},"index":0}]}"#
        _ = adapter.parseSSELine(line3, accumulated: &acc)

        let completed = acc.completedToolCalls
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed[0].id, "call_123")
        XCTAssertEqual(completed[0].name, "tools.list")
        XCTAssertEqual(completed[0].argumentsJSON, #"{"key":"val"}"#)
    }

    func testOpenAIParseFinishReasonStop() {
        let adapter = OpenAIAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"choices":[{"delta":{},"finish_reason":"stop","index":0}]}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)
        if case .done = event {
            // success
        } else {
            XCTFail("Expected .done for finish_reason stop")
        }
    }

    func testOpenAIIgnoresNonDataLines() {
        let adapter = OpenAIAdapter()
        var acc = StreamAccumulator()

        XCTAssertNil(adapter.parseSSELine("event: message", accumulated: &acc))
        XCTAssertNil(adapter.parseSSELine(": comment", accumulated: &acc))
        XCTAssertNil(adapter.parseSSELine("", accumulated: &acc))
    }

    // MARK: - Anthropic Request Building

    @MainActor
    func testAnthropicRequestHeaders() throws {
        let adapter = AnthropicAdapter()
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "System",
            model: "claude-sonnet-4-5-20250514",
            tools: nil,
            apiKey: "sk-ant-key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // No Bearer header
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    @MainActor
    func testAnthropicSystemIsTopLevel() throws {
        let adapter = AnthropicAdapter()
        let request = try adapter.buildRequest(
            messages: [Message(role: .user, content: "Hi")],
            systemPrompt: "You are Dochi.",
            model: "claude-sonnet-4-5-20250514",
            tools: nil,
            apiKey: "key"
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]

        // System is top-level
        XCTAssertEqual(body["system"] as? String, "You are Dochi.")
        XCTAssertEqual(body["max_tokens"] as? Int, 8192)
        XCTAssertEqual(body["stream"] as? Bool, true)

        // Messages should NOT contain system
        let messages = body["messages"] as! [[String: Any]]
        for msg in messages {
            XCTAssertNotEqual(msg["role"] as? String, "system")
        }
    }

    @MainActor
    func testAnthropicToolConversion() throws {
        let adapter = AnthropicAdapter()
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "test_tool",
                    "description": "A test",
                    "parameters": ["type": "object", "properties": [String: Any]()]
                ] as [String: Any]
            ]
        ]

        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "",
            model: "claude-sonnet-4-5-20250514",
            tools: tools,
            apiKey: "key"
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let convertedTools = body["tools"] as! [[String: Any]]
        XCTAssertEqual(convertedTools.count, 1)
        XCTAssertEqual(convertedTools[0]["name"] as? String, "test_tool")
        XCTAssertEqual(convertedTools[0]["description"] as? String, "A test")
        XCTAssertNotNil(convertedTools[0]["input_schema"])
    }

    // MARK: - Anthropic SSE Parsing

    func testAnthropicParseTextDelta() {
        let adapter = AnthropicAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .partial(let text) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected .partial")
        }
        XCTAssertEqual(acc.text, "Hello")
    }

    func testAnthropicParseToolUseStart() {
        let adapter = AnthropicAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_123","name":"tools.list"}}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .toolCallDelta(let index, let id, let name, _) = event {
            XCTAssertEqual(index, 1)
            XCTAssertEqual(id, "toolu_123")
            XCTAssertEqual(name, "tools.list")
        } else {
            XCTFail("Expected .toolCallDelta")
        }

        XCTAssertNotNil(acc.toolCalls[1])
        XCTAssertEqual(acc.toolCalls[1]?.id, "toolu_123")
        XCTAssertEqual(acc.toolCalls[1]?.name, "tools.list")
    }

    func testAnthropicParseInputJSONDelta() {
        let adapter = AnthropicAdapter()
        var acc = StreamAccumulator()

        // Start tool use block
        let startLine = #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"search"}}"#
        _ = adapter.parseSSELine(startLine, accumulated: &acc)

        // Input JSON deltas
        let delta1 = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\":"}}"#
        _ = adapter.parseSSELine(delta1, accumulated: &acc)

        let delta2 = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"hello\"}"}}"#
        _ = adapter.parseSSELine(delta2, accumulated: &acc)

        let completed = acc.completedToolCalls
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed[0].argumentsJSON, #"{"query":"hello"}"#)
    }

    func testAnthropicParseMessageStop() {
        let adapter = AnthropicAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"type":"message_stop"}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .done = event {
            // success
        } else {
            XCTFail("Expected .done")
        }
    }

    func testAnthropicParseMessageDeltaStop() {
        let adapter = AnthropicAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .done = event {
            // success
        } else {
            XCTFail("Expected .done for stop_reason end_turn")
        }
    }

    func testAnthropicParseError() {
        let adapter = AnthropicAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .error(let err) = event {
            XCTAssertTrue(err.localizedDescription.contains("Overloaded"))
        } else {
            XCTFail("Expected .error")
        }
    }

    // MARK: - Z.AI Request Building

    @MainActor
    func testZAIRequestIncludesEnableThinkingFalse() throws {
        let adapter = ZAIAdapter()
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "System",
            model: "glm-4.7",
            tools: nil,
            apiKey: "zai-key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer zai-key")
        XCTAssertEqual(request.url, LLMProvider.zai.apiURL)

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["enable_thinking"] as? Bool, false)
        XCTAssertEqual(body["model"] as? String, "glm-4.7")
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testZAIUsesOpenAIParsing() {
        let adapter = ZAIAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"choices":[{"delta":{"content":"你好"},"index":0}]}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .partial(let text) = event {
            XCTAssertEqual(text, "你好")
        } else {
            XCTFail("Expected .partial")
        }
    }

    // MARK: - StreamAccumulator

    func testStreamAccumulatorCompletedToolCalls() {
        var acc = StreamAccumulator()

        acc.toolCalls[0] = StreamAccumulator.ToolCallAccumulator(id: "t1", name: "search", arguments: #"{"q":"test"}"#)
        acc.toolCalls[2] = StreamAccumulator.ToolCallAccumulator(id: "t3", name: "list", arguments: "{}")
        acc.toolCalls[1] = StreamAccumulator.ToolCallAccumulator(id: "t2", name: "save", arguments: #"{"data":"x"}"#)

        let completed = acc.completedToolCalls
        XCTAssertEqual(completed.count, 3)
        // Should be sorted by index
        XCTAssertEqual(completed[0].id, "t1")
        XCTAssertEqual(completed[1].id, "t2")
        XCTAssertEqual(completed[2].id, "t3")
    }

    func testStreamAccumulatorEmpty() {
        let acc = StreamAccumulator()
        XCTAssertEqual(acc.text, "")
        XCTAssertTrue(acc.completedToolCalls.isEmpty)
    }

    // MARK: - Ollama Request Building

    @MainActor
    func testOllamaRequestNoAuthHeader() throws {
        let adapter = OllamaAdapter()
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "System",
            model: "llama3",
            tools: nil,
            apiKey: ""
        )

        XCTAssertEqual(request.httpMethod, "POST")
        // No auth header when API key is empty
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(request.url?.absoluteString.contains("localhost:11434") ?? false)
    }

    @MainActor
    func testOllamaRequestWithOptionalAuthHeader() throws {
        let adapter = OllamaAdapter()
        let request = try adapter.buildRequest(
            messages: [],
            systemPrompt: "",
            model: "mistral",
            tools: nil,
            apiKey: "custom-key"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-key")
    }

    @MainActor
    func testOllamaRequestBody() throws {
        let adapter = OllamaAdapter()
        let messages = [Message(role: .user, content: "Hello")]
        let request = try adapter.buildRequest(
            messages: messages,
            systemPrompt: "Be helpful",
            model: "llama3",
            tools: nil,
            apiKey: ""
        )

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "llama3")
        XCTAssertEqual(body["stream"] as? Bool, true)

        let apiMessages = body["messages"] as! [[String: Any]]
        XCTAssertEqual(apiMessages[0]["role"] as? String, "system")
        XCTAssertEqual(apiMessages[1]["role"] as? String, "user")
    }

    func testOllamaUsesOpenAIParsing() {
        let adapter = OllamaAdapter()
        var acc = StreamAccumulator()

        let line = #"data: {"choices":[{"delta":{"content":"Hello"},"index":0}]}"#
        let event = adapter.parseSSELine(line, accumulated: &acc)

        if case .partial(let text) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected .partial")
        }
    }

    func testOllamaParseDone() {
        let adapter = OllamaAdapter()
        var acc = StreamAccumulator()

        let event = adapter.parseSSELine("data: [DONE]", accumulated: &acc)
        if case .done = event {
            // success
        } else {
            XCTFail("Expected .done")
        }
    }

    // MARK: - LLMError

    func testLLMErrorDescriptions() {
        let cases: [(LLMError, String)] = [
            (.noAPIKey, "API 키가 설정되지 않았습니다."),
            (.authenticationFailed, "API 키를 확인하세요."),
            (.rateLimited(retryAfter: 5), "요청 한도를 초과했습니다"),
            (.modelNotFound("test"), "모델 'test'"),
            (.timeout, "응답 시간이 초과되었습니다."),
            (.emptyResponse, "응답을 생성하지 못했습니다."),
            (.cancelled, "요청이 취소되었습니다."),
        ]

        for (error, expectedSubstring) in cases {
            XCTAssertTrue(
                error.localizedDescription.contains(expectedSubstring),
                "\(error) description should contain '\(expectedSubstring)' but was '\(error.localizedDescription)'"
            )
        }
    }
}
