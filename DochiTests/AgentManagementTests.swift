import XCTest
@testable import Dochi

@MainActor
final class AgentManagementTests: XCTestCase {
    private var viewModel: DochiViewModel!
    private var contextService: MockContextService!
    private var settings: AppSettings!
    private var sessionContext: SessionContext!
    private var toolService: MockBuiltInToolService!

    override func setUp() {
        super.setUp()
        contextService = MockContextService()
        settings = AppSettings()
        toolService = MockBuiltInToolService()
        let wsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        sessionContext = SessionContext(workspaceId: wsId)

        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"

        viewModel = DochiViewModel(
            llmService: MockLLMService(),
            toolService: toolService,
            contextService: contextService,
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext
        )
    }

    // MARK: - deleteAgent

    func testDeleteAgentRemovesFromContextService() {
        let wsId = sessionContext.workspaceId
        contextService.createAgent(workspaceId: wsId, name: "테스트", wakeWord: nil, description: nil)
        contextService.createAgent(workspaceId: wsId, name: "보조", wakeWord: nil, description: nil)
        settings.activeAgentName = "보조"

        // Delete non-active agent
        viewModel.deleteAgent(name: "테스트")

        let remaining = contextService.listAgents(workspaceId: wsId)
        XCTAssertFalse(remaining.contains("테스트"))
        XCTAssertTrue(remaining.contains("보조"))
        // Active agent unchanged
        XCTAssertEqual(settings.activeAgentName, "보조")
    }

    func testDeleteActiveAgentSwitchesToFirst() {
        let wsId = sessionContext.workspaceId
        contextService.createAgent(workspaceId: wsId, name: "에이전트A", wakeWord: nil, description: nil)
        contextService.createAgent(workspaceId: wsId, name: "에이전트B", wakeWord: nil, description: nil)
        settings.activeAgentName = "에이전트A"

        viewModel.deleteAgent(name: "에이전트A")

        let remaining = contextService.listAgents(workspaceId: wsId)
        XCTAssertFalse(remaining.contains("에이전트A"))
        // Should switch to the remaining agent
        XCTAssertEqual(settings.activeAgentName, "에이전트B")
    }

    func testDeleteLastAgentFallsBackToDefault() {
        let wsId = sessionContext.workspaceId
        contextService.createAgent(workspaceId: wsId, name: "유일한에이전트", wakeWord: nil, description: nil)
        settings.activeAgentName = "유일한에이전트"

        viewModel.deleteAgent(name: "유일한에이전트")

        let remaining = contextService.listAgents(workspaceId: wsId)
        XCTAssertTrue(remaining.isEmpty)
        // Falls back to default name
        XCTAssertEqual(settings.activeAgentName, "도치")
    }

    func testDeleteAgentResetsToolRegistry() {
        let wsId = sessionContext.workspaceId
        contextService.createAgent(workspaceId: wsId, name: "삭제대상", wakeWord: nil, description: nil)
        settings.activeAgentName = "삭제대상"

        let resetCountBefore = toolService.resetCallCount
        viewModel.deleteAgent(name: "삭제대상")

        XCTAssertGreaterThan(toolService.resetCallCount, resetCountBefore)
    }

    // MARK: - AgentConfig round-trip

    func testAgentConfigSaveAndLoad() {
        let wsId = sessionContext.workspaceId
        let config = AgentConfig(
            name: "테스트봇",
            wakeWord: "테스트야",
            description: "테스트용 봇",
            defaultModel: "gpt-4o",
            permissions: ["safe", "sensitive"]
        )

        contextService.saveAgentConfig(workspaceId: wsId, config: config)

        let loaded = contextService.loadAgentConfig(workspaceId: wsId, agentName: "테스트봇")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "테스트봇")
        XCTAssertEqual(loaded?.wakeWord, "테스트야")
        XCTAssertEqual(loaded?.description, "테스트용 봇")
        XCTAssertEqual(loaded?.defaultModel, "gpt-4o")
        XCTAssertEqual(loaded?.effectivePermissions, ["safe", "sensitive"])
    }

    func testAgentConfigPermissionsUpdate() {
        let wsId = sessionContext.workspaceId

        // Create with default permissions
        let config1 = AgentConfig(name: "봇")
        XCTAssertEqual(config1.effectivePermissions, ["safe", "sensitive", "restricted"])

        // Update with restricted permissions
        let config2 = AgentConfig(name: "봇", permissions: ["safe"])
        contextService.saveAgentConfig(workspaceId: wsId, config: config2)

        let loaded = contextService.loadAgentConfig(workspaceId: wsId, agentName: "봇")
        XCTAssertEqual(loaded?.effectivePermissions, ["safe"])
    }
}
