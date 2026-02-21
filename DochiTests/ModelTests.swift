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

    func testAgentConfigEffectiveShellPermissions() {
        // Default: uses ShellPermissionConfig.default
        let config1 = AgentConfig(name: "도치")
        let shell1 = config1.effectiveShellPermissions
        XCTAssertFalse(shell1.blockedCommands.isEmpty)
        XCTAssertFalse(shell1.confirmCommands.isEmpty)
        XCTAssertFalse(shell1.allowedCommands.isEmpty)

        // Explicit shell permissions override default
        let custom = ShellPermissionConfig(
            blockedCommands: ["dangerous"],
            confirmCommands: ["risky"],
            allowedCommands: ["safe"]
        )
        let config2 = AgentConfig(name: "custom", shellPermissions: custom)
        XCTAssertEqual(config2.effectiveShellPermissions.blockedCommands, ["dangerous"])
        XCTAssertEqual(config2.effectiveShellPermissions.confirmCommands, ["risky"])
        XCTAssertEqual(config2.effectiveShellPermissions.allowedCommands, ["safe"])
    }

    func testAgentConfigEffectivePreferredToolGroups() {
        let config = AgentConfig(
            name: "coder",
            preferredToolGroups: [" Coding ", "git", "coding", ""]
        )
        XCTAssertEqual(config.effectivePreferredToolGroups, ["coding", "git"])
    }

    func testAgentConfigShellPermissionsCodable() throws {
        let custom = ShellPermissionConfig(
            blockedCommands: ["sudo "],
            confirmCommands: ["rm "],
            allowedCommands: ["ls"]
        )
        let config = AgentConfig(name: "test", shellPermissions: custom)

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(AgentConfig.self, from: data)

        XCTAssertEqual(decoded.shellPermissions?.blockedCommands, ["sudo "])
        XCTAssertEqual(decoded.shellPermissions?.confirmCommands, ["rm "])
        XCTAssertEqual(decoded.shellPermissions?.allowedCommands, ["ls"])
    }

    func testAgentConfigWithoutShellPermissionsCodable() throws {
        let config = AgentConfig(name: "legacy")

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(AgentConfig.self, from: data)

        XCTAssertNil(decoded.shellPermissions)
        // effectiveShellPermissions should return default
        XCTAssertFalse(decoded.effectiveShellPermissions.blockedCommands.isEmpty)
    }

    func testAgentConfigPreferredToolGroupsCodable() throws {
        let config = AgentConfig(name: "coder", preferredToolGroups: ["coding", "external_tool"])

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AgentConfig.self, from: data)

        XCTAssertEqual(decoded.preferredToolGroups ?? [], ["coding", "external_tool"])
        XCTAssertEqual(decoded.effectivePreferredToolGroups, ["coding", "external_tool"])
    }

    func testToolGroupCatalogNormalizedUnique() {
        let groups = ToolGroupCatalog.normalizedUnique([" Coding ", "git", "coding", "", "   "])
        XCTAssertEqual(groups, ["coding", "git"])
    }

    func testToolGroupCatalogGroupsFromToolNames() {
        let groups = ToolGroupCatalog.groups(fromToolNames: [
            "web.search",
            "web_search",
            "list_calendar_events",
            "create_calendar_event",
            "custom.tool",
            "set_alarm",
        ])
        XCTAssertEqual(groups, ["search", "calendar", "custom", "alarm"])
    }

    func testToolGroupCatalogSupportsTemplateSuggestedTools() {
        let groups = ToolGroupCatalog.groups(fromToolNames: AgentTemplate.scheduler.suggestedTools)
        XCTAssertEqual(groups, ["calendar", "reminders"])
    }

    func testToolGroupCatalogSupportsResearchTemplateSuggestedTools() {
        let groups = ToolGroupCatalog.groups(fromToolNames: AgentTemplate.researcher.suggestedTools)
        XCTAssertEqual(groups, ["search"])
    }

    // MARK: - ShellPermissionConfig

    func testShellPermissionConfigDefault() {
        let config = ShellPermissionConfig.default
        XCTAssertTrue(config.blockedCommands.contains("rm -rf /"))
        XCTAssertTrue(config.blockedCommands.contains("sudo "))
        XCTAssertTrue(config.confirmCommands.contains("rm "))
        XCTAssertTrue(config.confirmCommands.contains("mv "))
        XCTAssertTrue(config.allowedCommands.contains("ls"))
        XCTAssertTrue(config.allowedCommands.contains("git status"))
    }

    func testShellPermissionBlockedCommand() {
        let config = ShellPermissionConfig.default
        let result = config.matchResult(for: "sudo apt-get install foo")
        // "sudo " should be matched in blocked list
        XCTAssertEqual(result, .blocked(pattern: "sudo "))
    }

    func testShellPermissionBlockedTakesPrecedence() {
        let config = ShellPermissionConfig.default
        // "rm -rf /" is in both blocked (as exact pattern) and confirm (rm prefix)
        // Blocked should win since it's checked first
        let result = config.matchResult(for: "rm -rf /")
        if case .blocked = result {
            // expected
        } else {
            XCTFail("Expected .blocked, got \(result)")
        }
    }

    func testShellPermissionConfirmCommand() {
        let config = ShellPermissionConfig.default
        let result = config.matchResult(for: "rm somefile.txt")
        XCTAssertEqual(result, .confirm(pattern: "rm "))
    }

    func testShellPermissionAllowedCommand() {
        let config = ShellPermissionConfig.default
        let result = config.matchResult(for: "ls -la")
        XCTAssertEqual(result, .allowed)
    }

    func testShellPermissionDefaultCategory() {
        let config = ShellPermissionConfig.default
        let result = config.matchResult(for: "python3 script.py")
        XCTAssertEqual(result, .defaultCategory)
    }

    func testShellPermissionCaseInsensitive() {
        let config = ShellPermissionConfig.default
        let result = config.matchResult(for: "SUDO apt-get install")
        XCTAssertEqual(result, .blocked(pattern: "sudo "))
    }

    func testShellPermissionConfigCodable() throws {
        let config = ShellPermissionConfig(
            blockedCommands: ["danger"],
            confirmCommands: ["risky"],
            allowedCommands: ["safe"]
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ShellPermissionConfig.self, from: data)

        XCTAssertEqual(decoded.blockedCommands, ["danger"])
        XCTAssertEqual(decoded.confirmCommands, ["risky"])
        XCTAssertEqual(decoded.allowedCommands, ["safe"])
    }

    func testShellPermissionPrefixOnlyForAllowed() {
        // "false" should NOT match allowed "ls" — hasPrefix prevents this
        let config = ShellPermissionConfig(
            blockedCommands: [],
            confirmCommands: [],
            allowedCommands: ["ls"]
        )
        XCTAssertEqual(config.matchResult(for: "false"), .defaultCategory)
        XCTAssertEqual(config.matchResult(for: "ls -la"), .allowed)
    }

    func testShellPermissionPrefixOnlyForConfirm() {
        // "harmless" should NOT match confirm "rm" — hasPrefix prevents this
        let config = ShellPermissionConfig(
            blockedCommands: [],
            confirmCommands: ["rm"],
            allowedCommands: []
        )
        XCTAssertEqual(config.matchResult(for: "harmless"), .defaultCategory)
        XCTAssertEqual(config.matchResult(for: "rm file.txt"), .confirm(pattern: "rm"))
    }

    func testShellPermissionBlockedUsesContains() {
        // blocked uses contains — "echo foo && sudo rm" should still be blocked
        let config = ShellPermissionConfig(
            blockedCommands: ["sudo "],
            confirmCommands: [],
            allowedCommands: []
        )
        XCTAssertEqual(config.matchResult(for: "echo foo && sudo rm -rf /"), .blocked(pattern: "sudo "))
    }

    func testShellPermissionCustomConfig() {
        let config = ShellPermissionConfig(
            blockedCommands: ["format c:"],
            confirmCommands: ["deploy"],
            allowedCommands: ["status"]
        )

        XCTAssertEqual(config.matchResult(for: "format c:"), .blocked(pattern: "format c:"))
        XCTAssertEqual(config.matchResult(for: "deploy production"), .confirm(pattern: "deploy"))
        XCTAssertEqual(config.matchResult(for: "status check"), .allowed)
        XCTAssertEqual(config.matchResult(for: "unknown command"), .defaultCategory)
    }

    // MARK: - LLMProvider

    func testLLMProviderProperties() {
        XCTAssertEqual(LLMProvider.openai.displayName, "OpenAI")
        XCTAssertEqual(LLMProvider.anthropic.displayName, "Anthropic")
        XCTAssertEqual(LLMProvider.zai.displayName, "Z.AI")
        XCTAssertEqual(LLMProvider.ollama.displayName, "Ollama")

        XCTAssertFalse(LLMProvider.openai.models.isEmpty)
        XCTAssertFalse(LLMProvider.anthropic.models.isEmpty)
        XCTAssertFalse(LLMProvider.zai.models.isEmpty)
        XCTAssertTrue(LLMProvider.ollama.models.isEmpty) // Dynamic

        XCTAssertTrue(LLMProvider.openai.apiURL.absoluteString.contains("openai.com"))
        XCTAssertTrue(LLMProvider.anthropic.apiURL.absoluteString.contains("anthropic.com"))
        XCTAssertTrue(LLMProvider.zai.apiURL.absoluteString.contains("z.ai"))
        XCTAssertTrue(LLMProvider.ollama.apiURL.absoluteString.contains("localhost:11434"))
    }

    func testLLMProviderRequiresAPIKey() {
        XCTAssertTrue(LLMProvider.openai.requiresAPIKey)
        XCTAssertTrue(LLMProvider.anthropic.requiresAPIKey)
        XCTAssertTrue(LLMProvider.zai.requiresAPIKey)
        XCTAssertFalse(LLMProvider.ollama.requiresAPIKey)
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

    func testProviderCapabilityMatrixForOpenAIModel() {
        let capabilities = ProviderCapabilityMatrix.capabilities(
            for: .openai,
            model: "gpt-4o-mini"
        )

        XCTAssertTrue(capabilities.supportsToolCalling)
        XCTAssertTrue(capabilities.supportsVision)
        XCTAssertTrue(capabilities.supportsJSONOutput)
        XCTAssertTrue(capabilities.supportsOutputTokenReporting)
        XCTAssertTrue(capabilities.supportsStreamUsage)
    }

    func testProviderCapabilityMatrixForAnthropicModel() {
        let capabilities = ProviderCapabilityMatrix.capabilities(
            for: .anthropic,
            model: "claude-sonnet-4-5-20250514"
        )

        XCTAssertTrue(capabilities.supportsToolCalling)
        XCTAssertTrue(capabilities.supportsVision)
        XCTAssertTrue(capabilities.supportsJSONOutput)
        XCTAssertFalse(capabilities.supportsOutputTokenReporting)
        XCTAssertFalse(capabilities.supportsStreamUsage)
    }

    func testProviderCapabilityMatrixLocalToolHeuristic() {
        let supported = ProviderCapabilityMatrix.capabilities(
            for: .ollama,
            model: "llama3.2"
        )
        let unsupported = ProviderCapabilityMatrix.capabilities(
            for: .lmStudio,
            model: "tinyllama"
        )

        XCTAssertTrue(supported.supportsToolCalling)
        XCTAssertFalse(unsupported.supportsToolCalling)
    }

    func testProviderCapabilityMatrixLocalToolHeuristicUsesFamilyHint() {
        XCTAssertTrue(
            ProviderCapabilityMatrix.supportsLocalToolCalling(
                model: "corp-model-v1",
                familyHint: "mistral"
            )
        )
        XCTAssertFalse(
            ProviderCapabilityMatrix.supportsLocalToolCalling(
                model: "corp-model-v1",
                familyHint: "unknown-family"
            )
        )
    }

    // MARK: - LLMProvider.onboardingDefaultModel

    func testOnboardingDefaultModelCloudProvidersUseModelListFirstEntry() {
        XCTAssertEqual(LLMProvider.openai.onboardingDefaultModel, "gpt-4o")
        XCTAssertEqual(LLMProvider.anthropic.onboardingDefaultModel, "claude-sonnet-4-5-20250514")
        XCTAssertEqual(LLMProvider.zai.onboardingDefaultModel, "glm-5")
    }

    func testOnboardingDefaultModelLocalProviders() {
        XCTAssertEqual(LLMProvider.ollama.onboardingDefaultModel, "llama3")
        XCTAssertEqual(LLMProvider.lmStudio.onboardingDefaultModel, "")
    }

    @MainActor
    func testAppSettingsRemovesDeprecatedKeysOnInit() {
        UserDefaults.standard.set("compact", forKey: "uiDensity")
        UserDefaults.standard.set(true, forKey: "hasSeenPermissionInfo")
        UserDefaults.standard.set("openai", forKey: "ragEmbeddingProvider")

        _ = AppSettings()

        XCTAssertNil(UserDefaults.standard.object(forKey: "uiDensity"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "hasSeenPermissionInfo"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "ragEmbeddingProvider"))
    }

    @MainActor
    func testAppSettingsKeepsActiveKeysWhenRemovingDeprecatedKeys() {
        UserDefaults.standard.set("text-embedding-3-large", forKey: "ragEmbeddingModel")

        let settings = AppSettings()

        XCTAssertEqual(settings.ragEmbeddingModel, "text-embedding-3-large")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "ragEmbeddingModel"),
            "text-embedding-3-large"
        )
    }

    @MainActor
    func testAppSettingsOperatingProfileDefaultsToFamily() {
        UserDefaults.standard.removeObject(forKey: "operatingProfile")

        let settings = AppSettings()

        XCTAssertEqual(settings.operatingProfile, OperatingProfile.familyHomeAssistant.rawValue)
    }

    @MainActor
    func testAppSettingsOperatingProfilePersistence() {
        UserDefaults.standard.removeObject(forKey: "operatingProfile")
        let settings = AppSettings()
        settings.operatingProfile = OperatingProfile.personalProductivityAssistant.rawValue

        let restored = AppSettings()

        XCTAssertEqual(restored.operatingProfile, OperatingProfile.personalProductivityAssistant.rawValue)
    }

    @MainActor
    func testAppSettingsRepairsInvalidOperatingProfile() {
        UserDefaults.standard.set("legacy-unknown-profile", forKey: "operatingProfile")

        let settings = AppSettings()

        XCTAssertEqual(settings.operatingProfile, OperatingProfile.familyHomeAssistant.rawValue)
    }

    @MainActor
    func testAppSettingsAvatarCameraZoomDefaultsAndPersistence() {
        UserDefaults.standard.removeObject(forKey: "avatarCameraZoom")

        let settings = AppSettings()
        XCTAssertEqual(settings.avatarCameraZoom, AppSettings.avatarCameraZoomDefault, accuracy: 0.0001)

        settings.avatarCameraZoom = 1.08
        let restored = AppSettings()
        XCTAssertEqual(restored.avatarCameraZoom, 1.08, accuracy: 0.0001)
    }

    @MainActor
    func testAppSettingsAvatarCameraZoomClampsOutOfRangeValues() {
        UserDefaults.standard.set(9.9, forKey: "avatarCameraZoom")
        let settings = AppSettings()
        XCTAssertEqual(settings.avatarCameraZoom, AppSettings.avatarCameraZoomRange.upperBound, accuracy: 0.0001)

        settings.avatarCameraZoom = -3.0
        XCTAssertEqual(settings.avatarCameraZoom, AppSettings.avatarCameraZoomRange.lowerBound, accuracy: 0.0001)
    }

    @MainActor
    func testSetupHealthReportPerfectScoreWhenCoreSetupIsReady() {
        let settings = AppSettings()
        settings.autoSyncEnabled = false
        settings.defaultUserId = "user-1"
        settings.proactiveSuggestionEnabled = false
        settings.heartbeatEnabled = false

        let report = settings.setupHealthReport(hasProviderAPIKey: true)

        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertNil(report.primaryIssue)
    }

    @MainActor
    func testSetupHealthReportFlagsMissingAPIKey() {
        let settings = AppSettings()
        settings.llmProvider = LLMProvider.openai.rawValue
        settings.autoSyncEnabled = false
        settings.defaultUserId = "user-1"
        settings.proactiveSuggestionEnabled = false
        settings.heartbeatEnabled = false

        let report = settings.setupHealthReport(hasProviderAPIKey: false)

        XCTAssertTrue(report.issues.contains { $0.id == "api_key_missing" })
        XCTAssertEqual(report.primaryIssue?.sectionRawValue, "api-key")
        XCTAssertLessThan(report.score, 100)
    }

    @MainActor
    func testSetupHealthReportFlagsMissingSyncConfiguration() {
        let settings = AppSettings()
        settings.llmProvider = LLMProvider.ollama.rawValue
        settings.autoSyncEnabled = true
        settings.supabaseURL = ""
        settings.supabaseAnonKey = ""
        settings.defaultUserId = "user-1"
        settings.proactiveSuggestionEnabled = false
        settings.heartbeatEnabled = false

        let report = settings.setupHealthReport(hasProviderAPIKey: true)

        XCTAssertTrue(report.issues.contains { $0.id == "sync_config_missing" })
        XCTAssertEqual(report.primaryIssue?.sectionRawValue, "account")
        XCTAssertLessThan(report.score, 100)
    }
}

// MARK: - TaskComplexityClassifier Tests

final class TaskComplexityTests: XCTestCase {

    func testLightClassification() {
        XCTAssertEqual(TaskComplexityClassifier.classify("안녕"), .light)
        XCTAssertEqual(TaskComplexityClassifier.classify("ㅋㅋ"), .light)
        XCTAssertEqual(TaskComplexityClassifier.classify("hi"), .light)
        XCTAssertEqual(TaskComplexityClassifier.classify("고마워"), .light)
        XCTAssertEqual(TaskComplexityClassifier.classify("응"), .light)
    }

    func testHeavyClassification() {
        XCTAssertEqual(TaskComplexityClassifier.classify("이 코드를 분석해줘"), .heavy)
        XCTAssertEqual(TaskComplexityClassifier.classify("함수를 구현해줘"), .heavy)
        XCTAssertEqual(TaskComplexityClassifier.classify("debug this code please"), .heavy)
        XCTAssertEqual(TaskComplexityClassifier.classify("SQL 쿼리를 작성해줘"), .heavy)
    }

    func testStandardClassification() {
        XCTAssertEqual(TaskComplexityClassifier.classify("내일 회의 일정이 어떻게 돼?"), .standard)
        XCTAssertEqual(TaskComplexityClassifier.classify("점심 메뉴 추천해줘"), .standard)
    }

    func testShortHeavyKeyword() {
        // Short message with heavy keyword should still be heavy
        XCTAssertEqual(TaskComplexityClassifier.classify("코드 짜줘"), .heavy)
    }

    func testLongMessageBias() {
        // Long messages with heavy keywords get extra weight
        let longText = String(repeating: "이것은 긴 메시지입니다. ", count: 30) + "코드를 분석하고"
        XCTAssertEqual(TaskComplexityClassifier.classify(longText), .heavy)
    }

    func testEmptyString() {
        // Empty string is very short, should be light
        XCTAssertEqual(TaskComplexityClassifier.classify(""), .light)
    }

    func testAllCases() {
        XCTAssertEqual(TaskComplexity.allCases.count, 3)
        XCTAssertEqual(TaskComplexity.light.rawValue, "light")
        XCTAssertEqual(TaskComplexity.standard.rawValue, "standard")
        XCTAssertEqual(TaskComplexity.heavy.rawValue, "heavy")
    }

    func testDisplayNames() {
        XCTAssertEqual(TaskComplexity.light.displayName, "경량")
        XCTAssertEqual(TaskComplexity.standard.displayName, "표준")
        XCTAssertEqual(TaskComplexity.heavy.displayName, "고급")
    }
}
