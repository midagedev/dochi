import XCTest
@testable import Dochi

final class ModelTests: XCTestCase {

    // MARK: - ToolCall / CodableToolCall

    func testCodableToolCallArguments() {
        let tc = CodableToolCall(id: "1", name: "test", argumentsJSON: #"{"key":"value","num":42}"#)
        let args = tc.arguments
        XCTAssertEqual(args["key"] as? String, "value")
        XCTAssertEqual(args["num"] as? Int, 42)
    }

    func testCodableToolCallEmptyArguments() {
        let tc = CodableToolCall(id: "1", name: "test", argumentsJSON: "{}")
        XCTAssertTrue(tc.arguments.isEmpty)
    }

    func testCodableToolCallInvalidJSON() {
        let tc = CodableToolCall(id: "1", name: "test", argumentsJSON: "not json")
        XCTAssertTrue(tc.arguments.isEmpty)
    }

    func testToolCallToCodable() {
        let tc = ToolCall(id: "1", name: "test", arguments: ["hello": "world"])
        let codable = tc.codable
        XCTAssertEqual(codable.id, "1")
        XCTAssertEqual(codable.name, "test")
        XCTAssertEqual(codable.arguments["hello"] as? String, "world")
    }

    func testToolCallRoundTrip() {
        let original = ToolCall(id: "abc", name: "search", arguments: ["query": "test", "limit": 10])
        let codable = original.codable
        let decoded = codable.arguments
        XCTAssertEqual(decoded["query"] as? String, "test")
        XCTAssertEqual(decoded["limit"] as? Int, 10)
    }

    // MARK: - ToolResult

    func testToolResultDefaults() {
        let result = ToolResult(toolCallId: "tc1", content: "ok")
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.toolCallId, "tc1")
        XCTAssertEqual(result.content, "ok")
    }

    func testToolResultError() {
        let result = ToolResult(toolCallId: "tc2", content: "오류 발생", isError: true)
        XCTAssertTrue(result.isError)
    }

    // MARK: - Message

    func testMessageInit() {
        let msg = Message(role: .user, content: "안녕")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "안녕")
        XCTAssertNil(msg.toolCalls)
        XCTAssertNil(msg.toolCallId)
        XCTAssertNil(msg.imageURLs)
    }

    func testMessageWithToolCalls() {
        let tc = CodableToolCall(id: "t1", name: "search", argumentsJSON: "{}")
        let msg = Message(role: .assistant, content: "", toolCalls: [tc])
        XCTAssertEqual(msg.toolCalls?.count, 1)
        XCTAssertEqual(msg.toolCalls?[0].name, "search")
    }

    func testMessageCodable() throws {
        let tc = CodableToolCall(id: "t1", name: "search", argumentsJSON: #"{"q":"hi"}"#)
        let msg = Message(role: .assistant, content: "reply", toolCalls: [tc], toolCallId: "tc-ref")

        let encoder = JSONEncoder()
        let data = try encoder.encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.content, "reply")
        XCTAssertEqual(decoded.toolCalls?.count, 1)
        XCTAssertEqual(decoded.toolCallId, "tc-ref")
    }

    // MARK: - Conversation

    func testConversationDefaults() {
        let conv = Conversation()
        XCTAssertEqual(conv.title, "새 대화")
        XCTAssertTrue(conv.messages.isEmpty)
        XCTAssertNil(conv.userId)
        XCTAssertNil(conv.summary)
    }

    // MARK: - UserProfile

    func testUserProfileDefaults() {
        let p = UserProfile(name: "홍길동")
        XCTAssertEqual(p.name, "홍길동")
        XCTAssertTrue(p.aliases.isEmpty)
        XCTAssertNil(p.description)
    }

    // MARK: - AgentConfig

    func testAgentConfigEffectivePermissions() {
        // Default: all categories accessible (confirmation dialog is the real safeguard)
        let config1 = AgentConfig(name: "도치")
        XCTAssertEqual(config1.effectivePermissions, ["safe", "sensitive", "restricted"])

        // Explicit permissions override default
        let config2 = AgentConfig(name: "admin", permissions: ["safe", "sensitive", "restricted"])
        XCTAssertEqual(config2.effectivePermissions, ["safe", "sensitive", "restricted"])

        // Explicit safe-only restriction
        let config3 = AgentConfig(name: "viewer", permissions: ["safe"])
        XCTAssertEqual(config3.effectivePermissions, ["safe"])
    }

    // MARK: - LLMProvider

    func testLLMProviderProperties() {
        XCTAssertEqual(LLMProvider.openai.displayName, "OpenAI")
        XCTAssertEqual(LLMProvider.anthropic.displayName, "Anthropic")
        XCTAssertEqual(LLMProvider.zai.displayName, "Z.AI")

        XCTAssertFalse(LLMProvider.openai.models.isEmpty)
        XCTAssertFalse(LLMProvider.anthropic.models.isEmpty)
        XCTAssertFalse(LLMProvider.zai.models.isEmpty)

        XCTAssertTrue(LLMProvider.openai.apiURL.absoluteString.contains("openai.com"))
        XCTAssertTrue(LLMProvider.anthropic.apiURL.absoluteString.contains("anthropic.com"))
        XCTAssertTrue(LLMProvider.zai.apiURL.absoluteString.contains("z.ai"))
    }

    // MARK: - State Enums

    func testInteractionStateValues() {
        let states: [InteractionState] = [.idle, .listening, .processing, .speaking]
        XCTAssertEqual(states.count, 4)
    }

    func testSessionStateValues() {
        let states: [SessionState] = [.inactive, .active, .ending]
        XCTAssertEqual(states.count, 3)
    }

    func testProcessingSubStateValues() {
        let states: [ProcessingSubState] = [.streaming, .toolCalling, .toolError, .complete]
        XCTAssertEqual(states.count, 4)
    }

    // MARK: - InteractionMode

    func testInteractionModeRawValues() {
        XCTAssertEqual(InteractionMode.voiceAndText.rawValue, "voiceAndText")
        XCTAssertEqual(InteractionMode.textOnly.rawValue, "textOnly")
        XCTAssertEqual(InteractionMode(rawValue: "voiceAndText"), .voiceAndText)
        XCTAssertNil(InteractionMode(rawValue: "invalid"))
    }

    // MARK: - LLMResponse

    func testLLMResponseText() {
        let response = LLMResponse.text("hello")
        if case .text(let t) = response {
            XCTAssertEqual(t, "hello")
        } else {
            XCTFail("Expected .text")
        }
    }

    func testLLMResponseToolCalls() {
        let tc = CodableToolCall(id: "1", name: "test", argumentsJSON: "{}")
        let response = LLMResponse.toolCalls([tc])
        if case .toolCalls(let calls) = response {
            XCTAssertEqual(calls.count, 1)
        } else {
            XCTFail("Expected .toolCalls")
        }
    }

    // MARK: - LLMProvider.provider(forModel:)

    func testProviderForModelOpenAI() {
        XCTAssertEqual(LLMProvider.provider(forModel: "gpt-4o"), .openai)
        XCTAssertEqual(LLMProvider.provider(forModel: "gpt-4o-mini"), .openai)
    }

    func testProviderForModelAnthropic() {
        XCTAssertEqual(LLMProvider.provider(forModel: "claude-sonnet-4-5-20250514"), .anthropic)
    }

    func testProviderForModelZAI() {
        XCTAssertEqual(LLMProvider.provider(forModel: "glm-5"), .zai)
    }

    func testProviderForModelUnknown() {
        XCTAssertNil(LLMProvider.provider(forModel: "unknown-model"))
    }
}

// MARK: - ModelRouter Tests

@MainActor
final class ModelRouterTests: XCTestCase {

    private var settings: AppSettings!
    private var keychainService: MockKeychainService!

    override func setUp() {
        super.setUp()
        settings = AppSettings()
        settings.llmProvider = LLMProvider.openai.rawValue
        settings.llmModel = "gpt-4o"
        keychainService = MockKeychainService()
        keychainService.store["openai"] = "sk-test-openai"
        keychainService.store["anthropic"] = "sk-test-anthropic"
    }

    // MARK: - resolvePrimary without agent config (existing behavior)

    func testResolvePrimaryWithoutAgentConfig() {
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let resolved = router.resolvePrimary()

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .openai)
        XCTAssertEqual(resolved?.model, "gpt-4o")
        XCTAssertEqual(resolved?.apiKey, "sk-test-openai")
        XCTAssertFalse(resolved?.isFallback ?? true)
    }

    // MARK: - resolvePrimary with agent config

    func testResolvePrimaryWithAgentModel() {
        let config = AgentConfig(name: "claude-agent", defaultModel: "claude-sonnet-4-5-20250514")
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let resolved = router.resolvePrimary(agentConfig: config)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .anthropic)
        XCTAssertEqual(resolved?.model, "claude-sonnet-4-5-20250514")
        XCTAssertEqual(resolved?.apiKey, "sk-test-anthropic")
    }

    func testResolvePrimaryAgentModelFallsBackWhenNoAPIKey() {
        // Agent wants Z.AI model but no Z.AI API key is stored
        let config = AgentConfig(name: "zai-agent", defaultModel: "glm-5")
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let resolved = router.resolvePrimary(agentConfig: config)

        // Should fall back to app-level settings (OpenAI)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .openai)
        XCTAssertEqual(resolved?.model, "gpt-4o")
    }

    func testResolvePrimaryAgentModelNilFallsBackToAppSettings() {
        let config = AgentConfig(name: "default-agent", defaultModel: nil)
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let resolved = router.resolvePrimary(agentConfig: config)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .openai)
        XCTAssertEqual(resolved?.model, "gpt-4o")
    }

    func testResolvePrimaryAgentModelEmptyFallsBackToAppSettings() {
        let config = AgentConfig(name: "default-agent", defaultModel: "")
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let resolved = router.resolvePrimary(agentConfig: config)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .openai)
        XCTAssertEqual(resolved?.model, "gpt-4o")
    }

    func testResolvePrimaryAgentModelUnknownFallsBackToAppSettings() {
        let config = AgentConfig(name: "bad-agent", defaultModel: "nonexistent-model")
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let resolved = router.resolvePrimary(agentConfig: config)

        // Unknown model can't be resolved to a provider, falls back to app settings
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .openai)
        XCTAssertEqual(resolved?.model, "gpt-4o")
    }

    func testResolvePrimaryNoAgentConfigParameter() {
        // Calling without agentConfig parameter (default nil) should work as before
        let router = ModelRouter(settings: settings, keychainService: keychainService)
        let resolved = router.resolvePrimary()

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.provider, .openai)
        XCTAssertEqual(resolved?.model, "gpt-4o")
    }
}
