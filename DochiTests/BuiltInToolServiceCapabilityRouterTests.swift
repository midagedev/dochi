import XCTest
@testable import Dochi

@MainActor
private final class MockMCPServiceForCapabilityTests: MCPServiceProtocol {
    func addServer(config: MCPServerConfig) {}
    func removeServer(id: UUID) {}
    func connect(serverId: UUID) async throws {}
    func disconnect(serverId: UUID) {}
    func disconnectAll() {}
    func listServers() -> [MCPServerConfig] { [] }
    func getServer(id: UUID) -> MCPServerConfig? { nil }
    func listTools() -> [MCPToolInfo] { [] }
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        MCPToolResult(content: "ok", isError: false)
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

    // MARK: - Helpers

    private func makeService(routerEnabled: Bool) -> BuiltInToolService {
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
            mcpService: MockMCPServiceForCapabilityTests()
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
}
