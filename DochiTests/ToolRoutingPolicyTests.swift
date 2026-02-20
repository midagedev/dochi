import XCTest
@testable import Dochi

@MainActor
private final class DummyBuiltInToolForRoutingTests: BuiltInToolProtocol {
    let name: String
    let category: ToolCategory
    let description: String
    let inputSchema: [String: Any] = [:]
    let isBaseline = false

    init(name: String, category: ToolCategory, description: String = "dummy") {
        self.name = name
        self.category = category
        self.description = description
    }

    func execute(arguments _: [String: Any]) async -> ToolResult {
        ToolResult(toolCallId: "", content: "ok", isError: false)
    }
}

@MainActor
final class ToolRoutingPolicyTests: XCTestCase {
    func testResolveBuiltInRoute() {
        let policy = ToolRoutingPolicy()
        let tool = DummyBuiltInToolForRoutingTests(name: "git.status", category: .safe)

        let decision = policy.resolve(
            requestedName: "git-_-status",
            resolvedName: "git.status",
            builtInTool: tool,
            mcpTools: []
        )

        guard case .builtIn(let resolvedTool, _) = decision else {
            return XCTFail("Expected builtIn route")
        }
        XCTAssertEqual(resolvedTool.name, "git.status")
    }

    func testResolveMCPRoute() {
        let policy = ToolRoutingPolicy()
        let mcpTool = MCPToolInfo(
            serverName: "coding-git",
            name: "git_status",
            description: "read git status",
            inputSchema: [:]
        )

        let decision = policy.resolve(
            requestedName: "mcp_coding-git_git_status",
            resolvedName: "mcp_coding-git_git_status",
            builtInTool: nil,
            mcpTools: [mcpTool]
        )

        guard case .mcp(_, let originalName, _, _, let risk, _) = decision else {
            return XCTFail("Expected mcp route")
        }
        XCTAssertEqual(originalName, "git_status")
        XCTAssertEqual(risk, .safe)
    }

    func testClassifyMCPRiskUsesConservativeDefault() {
        let policy = ToolRoutingPolicy()

        let restricted = policy.classifyMCPRisk(
            serverName: "coding-shell",
            toolName: "shell_execute",
            description: "execute shell command"
        )
        XCTAssertEqual(restricted, .restricted)

        let safe = policy.classifyMCPRisk(
            serverName: "coding-git",
            toolName: "git_status",
            description: "read repository status"
        )
        XCTAssertEqual(safe, .safe)

        let unknown = policy.classifyMCPRisk(
            serverName: "custom-server",
            toolName: "project_tool",
            description: "custom behavior"
        )
        XCTAssertEqual(unknown, .sensitive)
    }
}
