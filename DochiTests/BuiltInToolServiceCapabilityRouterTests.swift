import XCTest
@testable import Dochi

@MainActor
private final class MockMCPServiceForCapabilityTests: MCPServiceProtocol {
    var tools: [MCPToolInfo] = []
    var callToolError: Error?
    var callToolResult = MCPToolResult(content: "ok", isError: false)

    func addServer(config: MCPServerConfig) {}
    func removeServer(id: UUID) {}
    func connect(serverId: UUID) async throws {}
    func disconnect(serverId: UUID) {}
    func disconnectAll() {}
    func listServers() -> [MCPServerConfig] { [] }
    func getServer(id: UUID) -> MCPServerConfig? { nil }
    func listTools() -> [MCPToolInfo] { tools }
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        if let callToolError {
            throw callToolError
        }
        return callToolResult
    }
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
        let result = await service.execute(
            name: "mcp_coding-shell_shell_execute",
            arguments: ["command": "pwd"]
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("MCP 서버가 현재 비가용 상태입니다"))
        XCTAssertTrue(result.content.contains("terminal.run"))
    }

    // MARK: - Helpers

    private func makeService(
        routerEnabled: Bool,
        mcpService: MCPServiceProtocol = MockMCPServiceForCapabilityTests()
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
            mcpService: mcpService
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
}
