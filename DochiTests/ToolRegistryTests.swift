import XCTest
@testable import Dochi

// MARK: - Stub Tool for Testing

@MainActor
private final class StubTool: BuiltInToolProtocol {
    let name: String
    let category: ToolCategory
    let description: String
    let isBaseline: Bool
    let inputSchema: [String: Any] = ["type": "object", "properties": [String: Any]()]
    var executeResult: ToolResult

    init(name: String, category: ToolCategory = .safe, isBaseline: Bool = false) {
        self.name = name
        self.category = category
        self.description = "Stub tool: \(name)"
        self.isBaseline = isBaseline
        self.executeResult = ToolResult(toolCallId: "", content: "ok from \(name)")
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        executeResult
    }
}

@MainActor
final class ToolRegistryTests: XCTestCase {
    private var registry: ToolRegistry!

    override func setUp() {
        super.setUp()
        registry = ToolRegistry()
    }

    // MARK: - Registration

    func testRegisterAndLookup() {
        let tool = StubTool(name: "test.tool")
        registry.register(tool)

        XCTAssertNotNil(registry.tool(named: "test.tool"))
        XCTAssertNil(registry.tool(named: "nonexistent"))
    }

    func testAllToolNames() {
        registry.register(StubTool(name: "b.tool"))
        registry.register(StubTool(name: "a.tool"))

        let names = registry.allToolNames
        XCTAssertEqual(names, ["a.tool", "b.tool"]) // sorted
    }

    // MARK: - Baseline

    func testBaselineTools() {
        registry.register(StubTool(name: "baseline1", isBaseline: true))
        registry.register(StubTool(name: "extra1", isBaseline: false))

        let baseline = registry.baselineTools
        XCTAssertEqual(baseline.count, 1)
        XCTAssertEqual(baseline[0].name, "baseline1")
    }

    // MARK: - Available Tools with Permissions

    func testAvailableToolsBaselineOnly() {
        registry.register(StubTool(name: "safe.base", category: .safe, isBaseline: true))
        registry.register(StubTool(name: "safe.extra", category: .safe, isBaseline: false))
        registry.register(StubTool(name: "sensitive.tool", category: .sensitive, isBaseline: false))

        let available = registry.availableTools(for: ["safe"])
        // Only baseline safe tools (extra is not enabled)
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available[0].name, "safe.base")
    }

    func testAvailableToolsWithEnabled() {
        registry.register(StubTool(name: "safe.base", category: .safe, isBaseline: true))
        registry.register(StubTool(name: "safe.extra", category: .safe, isBaseline: false))

        registry.enable(names: ["safe.extra"])

        let available = registry.availableTools(for: ["safe"])
        XCTAssertEqual(available.count, 2)
    }

    func testAvailableToolsPermissionFiltering() {
        registry.register(StubTool(name: "safe.tool", category: .safe, isBaseline: true))
        registry.register(StubTool(name: "sensitive.tool", category: .sensitive, isBaseline: true))
        registry.register(StubTool(name: "restricted.tool", category: .restricted, isBaseline: true))

        // Only safe permission
        let safeOnly = registry.availableTools(for: ["safe"])
        XCTAssertEqual(safeOnly.count, 1)
        XCTAssertEqual(safeOnly[0].name, "safe.tool")

        // Safe + sensitive
        let safeSensitive = registry.availableTools(for: ["safe", "sensitive"])
        XCTAssertEqual(safeSensitive.count, 2)

        // All permissions
        let all = registry.availableTools(for: ["safe", "sensitive", "restricted"])
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Enable / Disable

    func testEnableNonExistentToolIgnored() {
        registry.enable(names: ["nonexistent"])
        XCTAssertTrue(registry.enabledToolNames.isEmpty)
    }

    func testEnableExistingTool() {
        registry.register(StubTool(name: "my.tool"))
        registry.enable(names: ["my.tool"])
        XCTAssertTrue(registry.enabledToolNames.contains("my.tool"))
    }

    func testResetEnabled() {
        registry.register(StubTool(name: "my.tool"))
        registry.enable(names: ["my.tool"])
        XCTAssertFalse(registry.enabledToolNames.isEmpty)

        registry.resetEnabled()
        XCTAssertTrue(registry.enabledToolNames.isEmpty)
    }

    func testReset() {
        registry.register(StubTool(name: "my.tool"))
        registry.enable(names: ["my.tool"])

        registry.reset()
        XCTAssertTrue(registry.enabledToolNames.isEmpty)
    }

    // MARK: - Enable Multiple

    func testEnableMultipleTools() {
        registry.register(StubTool(name: "tool.a"))
        registry.register(StubTool(name: "tool.b"))
        registry.register(StubTool(name: "tool.c"))

        registry.enable(names: ["tool.a", "tool.c"])

        XCTAssertTrue(registry.enabledToolNames.contains("tool.a"))
        XCTAssertFalse(registry.enabledToolNames.contains("tool.b"))
        XCTAssertTrue(registry.enabledToolNames.contains("tool.c"))
    }
}
