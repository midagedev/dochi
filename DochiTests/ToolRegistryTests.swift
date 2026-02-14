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

    // MARK: - Enable Bypasses Category Filter

    func testEnabledToolBypassesCategoryFilter() {
        // Restricted tool, but safe-only permissions
        registry.register(StubTool(name: "coding.run_task", category: .restricted, isBaseline: false))
        registry.register(StubTool(name: "safe.base", category: .safe, isBaseline: true))

        // Before enable: restricted tool not visible with safe-only permissions
        let before = registry.availableTools(for: ["safe"])
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(before[0].name, "safe.base")

        // After enable: restricted tool visible regardless of permissions
        registry.enable(names: ["coding.run_task"])
        let after = registry.availableTools(for: ["safe"])
        XCTAssertEqual(after.count, 2)
        let names = Set(after.map(\.name))
        XCTAssertTrue(names.contains("coding.run_task"))
        XCTAssertTrue(names.contains("safe.base"))
    }

    func testEnabledSensitiveToolBypassesCategoryFilter() {
        registry.register(StubTool(name: "agent.config_get", category: .sensitive, isBaseline: false))

        // Safe-only permissions, but explicitly enabled
        registry.enable(names: ["agent.config_get"])
        let available = registry.availableTools(for: ["safe"])
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available[0].name, "agent.config_get")
    }

    func testNonEnabledNonBaselineToolNotExposed() {
        // Non-baseline, not enabled → not available even with matching permissions
        registry.register(StubTool(name: "coding.run_task", category: .restricted, isBaseline: false))

        let available = registry.availableTools(for: ["safe", "sensitive", "restricted"])
        XCTAssertEqual(available.count, 0)
    }

    // MARK: - Non-Baseline Tool Summaries

    func testNonBaselineToolSummaries() {
        registry.register(StubTool(name: "safe.base", category: .safe, isBaseline: true))
        registry.register(StubTool(name: "coding.run_task", category: .restricted, isBaseline: false))
        registry.register(StubTool(name: "agent.config_get", category: .sensitive, isBaseline: false))

        let summaries = registry.nonBaselineToolSummaries
        XCTAssertEqual(summaries.count, 2)
        // Sorted by name
        XCTAssertEqual(summaries[0].name, "agent.config_get")
        XCTAssertEqual(summaries[1].name, "coding.run_task")
        XCTAssertEqual(summaries[1].category, .restricted)
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
