import Foundation

enum ToolRouteSource: String {
    case builtIn = "builtin"
    case mcp
}

enum ToolRouteDecision {
    case builtIn(tool: any BuiltInToolProtocol, reason: String)
    case mcp(
        requestedName: String,
        originalName: String,
        serverName: String,
        description: String,
        risk: ToolCategory,
        reason: String
    )
}

@MainActor
final class ToolRoutingPolicy {
    private let restrictedKeywords: [String] = [
        "execute", "exec", "shell", "terminal", "run",
        "delete", "remove", "rm", "chmod", "chown", "sudo", "kill",
        "reset", "rebase", "cherry", "force", "commit", "push",
    ]

    private let sensitiveKeywords: [String] = [
        "create", "update", "set", "add", "edit", "rename", "move", "copy",
        "branch", "merge", "checkout", "tag", "stash", "apply",
    ]

    private let safeKeywords: [String] = [
        "list", "get", "read", "search", "status", "log", "diff", "show", "find",
        "ls", "cat", "head", "tail",
    ]

    func resolve(
        requestedName: String,
        resolvedName: String,
        builtInTool: (any BuiltInToolProtocol)?,
        mcpTools: [MCPToolInfo]
    ) -> ToolRouteDecision? {
        if requestedName.hasPrefix("mcp_") {
            guard let mcpTool = mcpTools.first(where: { mcpToolName(for: $0) == requestedName }) else {
                return nil
            }
            return .mcp(
                requestedName: requestedName,
                originalName: mcpTool.name,
                serverName: mcpTool.serverName,
                description: mcpTool.description,
                risk: classifyMCPRisk(
                    serverName: mcpTool.serverName,
                    toolName: mcpTool.name,
                    description: mcpTool.description
                ),
                reason: "mcp-prefixed tool name"
            )
        }

        guard let builtInTool else {
            return nil
        }

        return .builtIn(
            tool: builtInTool,
            reason: resolvedName == requestedName ? "direct builtin match" : "desanitized builtin match"
        )
    }

    func classifyMCPRisk(serverName: String, toolName: String, description: String) -> ToolCategory {
        let haystack = "\(serverName) \(toolName) \(description)".lowercased()

        if containsKeyword(in: haystack, keywords: restrictedKeywords) {
            return .restricted
        }
        if containsKeyword(in: haystack, keywords: sensitiveKeywords) {
            return .sensitive
        }
        if containsKeyword(in: haystack, keywords: safeKeywords) {
            return .safe
        }

        // Unknown MCP tools default to sensitive.
        return .sensitive
    }

    func mcpToolName(for tool: MCPToolInfo) -> String {
        "mcp_\(tool.serverName)_\(tool.name)"
    }

    private func containsKeyword(in haystack: String, keywords: [String]) -> Bool {
        for keyword in keywords where haystack.contains(keyword) {
            return true
        }
        return false
    }
}
