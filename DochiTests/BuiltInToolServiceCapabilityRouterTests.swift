import XCTest
@testable import Dochi

@MainActor
private final class MockMCPServiceForCapabilityTests: MCPServiceProtocol {
    var tools: [MCPToolInfo] = []
    var callToolError: Error?
    var callToolResult = MCPToolResult(content: "ok", isError: false)
    var callToolCallCount = 0

    func addServer(config: MCPServerConfig) {}
    func removeServer(id: UUID) {}
    func connect(serverId: UUID) async throws {}
    func disconnect(serverId: UUID) {}
    func disconnectAll() {}
    func updateServer(config: MCPServerConfig) async throws {}
    func listServers() -> [MCPServerConfig] { [] }
    func getServer(id: UUID) -> MCPServerConfig? { nil }
    func listTools() -> [MCPToolInfo] { tools }
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        callToolCallCount += 1
        if let callToolError {
            throw callToolError
        }
        return callToolResult
    }

    func activateProfile(_ profile: MCPServerProfile) async {}
    func deactivateProfile(_ profile: MCPServerProfile) {}
    func serverStatus(for serverId: UUID) -> MCPServerStatus { .disconnected }
    func healthReport(for profile: MCPServerProfile) -> MCPProfileHealthReport {
        MCPProfileHealthReport(profileName: profile.displayName, serverStatuses: [])
    }
    func fallbackMessage(for toolName: String) -> String { "" }
}

@MainActor
private final class MockToolContextStoreForCapabilityTests: ToolContextStoreProtocol {
    var context: ToolRankingContext = .empty
    private(set) var recordedEvents: [ToolUsageEvent] = []

    func record(_ event: ToolUsageEvent) async {
        recordedEvents.append(event)
    }

    func profile(workspaceId _: String, agentName _: String) async -> ToolContextProfile? {
        nil
    }

    func userPreference(workspaceId _: String) async -> UserToolPreference {
        UserToolPreference()
    }

    func rankingContext(workspaceId _: String, agentName _: String) -> ToolRankingContext {
        context
    }

    func updateUserPreference(_: UserToolPreference, workspaceId _: String) async {}

    func flushToDisk() async {}
}

@MainActor
final class BuiltInToolServiceCapabilityRouterTests: XCTestCase {
    private static let flagKey = "capabilityRouterV2Enabled"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.flagKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.flagKey)
        super.tearDown()
    }

    func testAvailableToolSchemasFlagOffUsesLegacyToolExposure() {
        let service = makeService(routerEnabled: false)

        let schemas = service.availableToolSchemas(for: ["safe"])
        let names = schemaNames(from: schemas)

        XCTAssertTrue(names.contains(BuiltInToolService.sanitizeToolName("finder.reveal")))
        XCTAssertNil(service.selectedCapabilityLabel)
    }

    func testAvailableToolSchemasFlagOnFiltersByCapabilityPack() {
        let service = makeService(routerEnabled: true)

        let schemas = service.availableToolSchemas(for: ["safe"])
        let names = schemaNames(from: schemas)

        XCTAssertTrue(names.contains(BuiltInToolService.sanitizeToolName("datetime")))
        XCTAssertTrue(names.contains(BuiltInToolService.sanitizeToolName("tools.list")))
        XCTAssertFalse(names.contains(BuiltInToolService.sanitizeToolName("finder.reveal")))
        XCTAssertEqual(service.selectedCapabilityLabel, "Chat Core")
    }

    func testCapabilityFilterKeepsEnabledToolOutsidePack() {
        let service = makeService(routerEnabled: true)
        service.enableTools(names: ["open_url"])

        let schemas = service.availableToolSchemas(for: ["safe"])
        let names = schemaNames(from: schemas)

        XCTAssertTrue(names.contains("open_url"))
        XCTAssertEqual(service.selectedCapabilityLabel, "Chat Core")
    }

    func testRestrictedPermissionSelectsCodingReadLabel() {
        let service = makeService(routerEnabled: true)

        _ = service.availableToolSchemas(for: ["safe", "restricted"])

        XCTAssertEqual(service.selectedCapabilityLabel, "Chat Core + Coding Read")
    }

    func testPreferredToolGroupsPrioritizeSchemaOrder() {
        let service = makeService(routerEnabled: true)
        service.enableTools(names: ["open_url"])

        let schemas = service.availableToolSchemas(
            for: ["safe"],
            preferredToolGroups: ["url"]
        )
        let names = orderedSchemaNames(from: schemas)

        XCTAssertEqual(names.first, "open_url")
    }

    func testRankingContextBoostsPreferredAndHighUsageTools() {
        let contextStore = MockToolContextStoreForCapabilityTests()
        contextStore.context = ToolRankingContext(
            categoryScores: ["agent": 1.2],
            toolScores: ["agent.list": 2.5],
            preferredCategories: ["agent"],
            suppressedCategories: ["finder"]
        )

        let service = makeService(
            routerEnabled: false,
            toolContextStore: contextStore
        )
        service.enableTools(names: ["agent.list", "coding.sessions"])

        let schemas = service.availableToolSchemas(
            for: ["safe", "sensitive"],
            preferredToolGroups: [],
            intentHint: nil
        )
        let names = orderedSchemaNames(from: schemas)

        XCTAssertLessThan(index(of: "agent-_-list", in: names), index(of: "finder-_-list_dir", in: names))
    }

    func testCodingAgentIntentBoostPrioritizesAgentAndSessionTools() {
        let contextStore = MockToolContextStoreForCapabilityTests()
        let service = makeService(
            routerEnabled: false,
            toolContextStore: contextStore
        )
        service.enableTools(names: ["agent.list", "coding.sessions"])

        let schemas = service.availableToolSchemas(
            for: ["safe", "sensitive"],
            preferredToolGroups: [],
            intentHint: "코딩 에이전트 목록 확인해줘"
        )
        let names = orderedSchemaNames(from: schemas)

        let agentIndex = index(of: "agent-_-list", in: names)
        let sessionIndex = index(of: "coding-_-sessions", in: names)
        let finderIndex = index(of: "finder-_-list_dir", in: names)
        XCTAssertLessThan(agentIndex, finderIndex)
        XCTAssertLessThan(sessionIndex, finderIndex)
    }

    func testColdStartWithoutSignalsRemainsAlphabetical() {
        let service = makeService(routerEnabled: false)
        service.enableTools(names: ["open_url"])

        let schemas = service.availableToolSchemas(
            for: ["safe", "sensitive"],
            preferredToolGroups: [],
            intentHint: nil
        )
        let names = orderedSchemaNames(from: schemas)
        XCTAssertEqual(names, names.sorted())
    }

    func testExecuteMCPToolReturnsFallbackMessageWhenServerUnavailable() async {
        let mcpService = MockMCPServiceForCapabilityTests()
        mcpService.tools = [
            MCPToolInfo(
                serverName: "coding-shell",
                name: "shell_execute",
                description: "execute shell command",
                inputSchema: [:]
            ),
        ]
        mcpService.callToolError = MCPServiceError.notConnected

        let service = makeService(routerEnabled: false, mcpService: mcpService)
        service.confirmationHandler = { _, _ in true }
        let result = await service.execute(
            name: "mcp_coding-shell_shell_execute",
            arguments: ["command": "pwd"]
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("MCP 서버가 현재 비가용 상태입니다"))
        XCTAssertTrue(result.content.contains("terminal.run"))
    }

    func testRestrictedMCPToolRequiresApproval() async {
        let mcpService = MockMCPServiceForCapabilityTests()
        mcpService.tools = [
            MCPToolInfo(
                serverName: "coding-shell",
                name: "shell_execute",
                description: "execute shell command",
                inputSchema: [:]
            ),
        ]

        let service = makeService(routerEnabled: false, mcpService: mcpService)
        let result = await service.execute(
            name: "mcp_coding-shell_shell_execute",
            arguments: ["command": "pwd"]
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(mcpService.callToolCallCount, 0, "Restricted MCP tool must not execute without approval")
    }

    func testSafeMCPToolExecutesWithoutApproval() async {
        let mcpService = MockMCPServiceForCapabilityTests()
        mcpService.tools = [
            MCPToolInfo(
                serverName: "coding-git",
                name: "git_status",
                description: "read current git status",
                inputSchema: [:]
            ),
        ]

        let service = makeService(routerEnabled: false, mcpService: mcpService)
        let result = await service.execute(
            name: "mcp_coding-git_git_status",
            arguments: [:]
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(mcpService.callToolCallCount, 1)
    }

    func testAllToolInfosIncludesMCPRiskClassification() {
        let mcpService = MockMCPServiceForCapabilityTests()
        mcpService.tools = [
            MCPToolInfo(
                serverName: "coding-shell",
                name: "shell_execute",
                description: "execute shell command",
                inputSchema: [:]
            ),
            MCPToolInfo(
                serverName: "coding-git",
                name: "git_status",
                description: "read repository status",
                inputSchema: [:]
            ),
        ]

        let service = makeService(routerEnabled: false, mcpService: mcpService)
        let infos = service.allToolInfos

        let shellInfo = infos.first { $0.name == "mcp_coding-shell_shell_execute" }
        let gitInfo = infos.first { $0.name == "mcp_coding-git_git_status" }
        XCTAssertEqual(shellInfo?.category, .restricted)
        XCTAssertEqual(gitInfo?.category, .safe)
    }

    // MARK: - Helpers

    private func makeService(
        routerEnabled: Bool,
        mcpService: MCPServiceProtocol = MockMCPServiceForCapabilityTests(),
        toolContextStore: (any ToolContextStoreProtocol)? = nil
    ) -> BuiltInToolService {
        let settings = AppSettings()
        settings.capabilityRouterV2Enabled = routerEnabled
        settings.appGuideEnabled = false

        return BuiltInToolService(
            contextService: MockContextService(),
            keychainService: MockKeychainService(),
            sessionContext: SessionContext(workspaceId: UUID()),
            settings: settings,
            supabaseService: MockSupabaseService(),
            telegramService: MockTelegramService(),
            mcpService: mcpService,
            toolContextStore: toolContextStore
        )
    }

    private func schemaNames(from schemas: [[String: Any]]) -> Set<String> {
        var names = Set<String>()
        for schema in schemas {
            guard let function = schema["function"] as? [String: Any],
                  let name = function["name"] as? String else {
                continue
            }
            names.insert(name)
        }
        return names
    }

    private func orderedSchemaNames(from schemas: [[String: Any]]) -> [String] {
        schemas.compactMap { schema in
            guard let function = schema["function"] as? [String: Any] else { return nil }
            return function["name"] as? String
        }
    }

    private func index(of name: String, in names: [String]) -> Int {
        names.firstIndex(of: name) ?? Int.max
    }
}
