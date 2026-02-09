import XCTest
@testable import Dochi

@MainActor
final class AppSettingsTests: XCTestCase {
    var mockKeychain: MockKeychainService!
    var mockContext: MockContextService!
    var sut: AppSettings!

    static let suiteName = "com.dochi.tests.settings"

    override func setUp() {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)

        mockKeychain = MockKeychainService()
        mockContext = MockContextService()
        sut = AppSettings(keychainService: mockKeychain, contextService: mockContext, defaults: defaults)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        sut = nil
        mockKeychain = nil
        mockContext = nil
    }

    // MARK: - Default Values

    func testDefaultWakeWord() {
        XCTAssertEqual(sut.wakeWord, Constants.Defaults.wakeWord)
    }

    func testDefaultTTSSpeed() {
        XCTAssertEqual(sut.ttsSpeed, Constants.Defaults.ttsSpeed)
    }

    func testDefaultChatFontSize() {
        XCTAssertEqual(sut.chatFontSize, Constants.Defaults.chatFontSize)
    }

    func testDefaultContextMaxSize() {
        XCTAssertEqual(sut.contextMaxSize, Constants.Defaults.contextMaxSize)
    }

    func testDefaultContextAutoCompress() {
        XCTAssertTrue(sut.contextAutoCompress)
    }

    // MARK: - API Keys

    func testApiKeyStorage() {
        sut.apiKey = "sk-test-key"

        XCTAssertEqual(sut.apiKey, "sk-test-key")
        XCTAssertEqual(mockKeychain.storage["openai"], "sk-test-key")
    }

    func testAnthropicApiKeyStorage() {
        sut.anthropicApiKey = "sk-ant-key"

        XCTAssertEqual(sut.anthropicApiKey, "sk-ant-key")
        XCTAssertEqual(mockKeychain.storage["anthropic"], "sk-ant-key")
    }

    func testApiKeyForProvider() {
        mockKeychain.storage["openai"] = "sk-openai"
        mockKeychain.storage["anthropic"] = "sk-anthropic"
        mockKeychain.storage["zai"] = "sk-zai"

        XCTAssertEqual(sut.apiKey(for: .openai), "sk-openai")
        XCTAssertEqual(sut.apiKey(for: .anthropic), "sk-anthropic")
        XCTAssertEqual(sut.apiKey(for: .zai), "sk-zai")
    }

    func testApiKeyReturnsEmptyWhenNotSet() {
        XCTAssertEqual(sut.apiKey(for: .openai), "")
    }

    // MARK: - MCP Server Management

    func testAddMCPServer() {
        let config = MCPServerConfig(name: "Test Server", command: "npx", arguments: ["-y", "@test/server"])

        sut.addMCPServer(config)

        XCTAssertEqual(sut.mcpServers.count, 1)
        XCTAssertEqual(sut.mcpServers.first?.name, "Test Server")
    }

    func testRemoveMCPServer() {
        let config = MCPServerConfig(name: "Test", command: "cmd", arguments: [])
        sut.addMCPServer(config)

        sut.removeMCPServer(id: config.id)

        XCTAssertTrue(sut.mcpServers.isEmpty)
    }

    func testUpdateMCPServer() {
        var config = MCPServerConfig(name: "Old Name", command: "cmd", arguments: [])
        sut.addMCPServer(config)

        config.name = "New Name"
        sut.updateMCPServer(config)

        XCTAssertEqual(sut.mcpServers.first?.name, "New Name")
    }

    // MARK: - Build Instructions

    func testBuildInstructionsWithSystemPrompt() {
        // Create a workspace and set agent persona
        let workspace = Workspace(id: UUID(), name: "Test", ownerId: UUID(), createdAt: Date())
        mockContext.workspaces = [workspace]
        mockContext.saveAgentPersona(workspaceId: workspace.id, agentName: "도치", content: "You are a helpful assistant.")
        sut.currentWorkspaceId = workspace.id

        let instructions = sut.buildInstructions()

        XCTAssertTrue(instructions.contains("You are a helpful assistant."))
    }

    func testBuildInstructionsIncludesCurrentTime() {
        let instructions = sut.buildInstructions()

        XCTAssertTrue(instructions.contains("현재 시각"))
    }

    func testBuildInstructionsWithProfiles() {
        let profile = UserProfile(name: "Alice", aliases: ["앨리스"])
        mockContext.profiles = [profile]

        let instructions = sut.buildInstructions(
            currentUserName: "Alice",
            currentUserId: profile.id,
            recentSummaries: nil
        )

        XCTAssertTrue(instructions.contains("Alice"))
    }
}
