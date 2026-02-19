import XCTest
@testable import Dochi

@MainActor
private final class CapabilityStubTool: BuiltInToolProtocol {
    let name: String
    let category: ToolCategory
    let description: String
    let isBaseline: Bool
    let inputSchema: [String: Any] = ["type": "object", "properties": [String: Any]()]

    init(name: String, category: ToolCategory = .safe, isBaseline: Bool = true) {
        self.name = name
        self.category = category
        self.description = name
        self.isBaseline = isBaseline
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        ToolResult(toolCallId: "", content: "ok")
    }
}

final class CapabilityRouterTests: XCTestCase {
    func testRouteUsesChatCoreByDefault() {
        let router = CapabilityRouter()

        let route = router.route(for: ["safe"])

        XCTAssertEqual(route.primary, .chatCore)
        XCTAssertNil(route.secondary)
        XCTAssertEqual(router.label(for: route), "Chat Core")
    }

    func testRouteAddsCodingReadWhenRestrictedPermissionExists() {
        let router = CapabilityRouter()

        let route = router.route(for: ["safe", "restricted"])

        XCTAssertEqual(route.primary, .chatCore)
        XCTAssertEqual(route.secondary, .codingRead)
        XCTAssertEqual(router.label(for: route), "Chat Core + Coding Read")
    }

    @MainActor
    func testFilterKeepsExplicitlyEnabledToolOutsidePack() {
        let router = CapabilityRouter()
        let tools: [any BuiltInToolProtocol] = [
            CapabilityStubTool(name: "datetime"),
            CapabilityStubTool(name: "finder.reveal"),
            CapabilityStubTool(name: "open_url", category: .sensitive, isBaseline: false),
        ]

        let filtered = router.filter(
            tools: tools,
            enabledToolNames: ["open_url"],
            permissions: ["safe"]
        )
        let names = Set(filtered.filteredTools.map(\.name))

        XCTAssertTrue(names.contains("datetime"))
        XCTAssertFalse(names.contains("finder.reveal"))
        XCTAssertTrue(names.contains("open_url"))
        XCTAssertEqual(filtered.selectedLabel, "Chat Core")
    }
}
