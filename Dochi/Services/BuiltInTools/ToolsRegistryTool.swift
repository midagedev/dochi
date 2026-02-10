import Foundation
import os

/// 툴 레지스트리: 최소 스펙만 노출하고, 필요한 도구 이름만 활성화하도록 함
@MainActor
final class ToolsRegistryTool: BuiltInTool {
    weak var registryHost: BuiltInToolService?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:tools.list",
                name: "tools.list",
                description: "List available built-in tool names grouped by category. This does not include full schemas.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:tools.enable_categories",
                name: "tools.enable_categories",
                description: "Enable tools by category names (e.g., agent, agent_edit, settings, workspace, telegram, context, profile_admin).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "categories": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["categories"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:tools.enable",
                name: "tools.enable",
                description: "Enable a set of tools by name. Only enabled tools (plus baseline) will be exposed in subsequent requests.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "names": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["names"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:tools.enable_ttl",
                name: "tools.enable_ttl",
                description: "Set the TTL (minutes) for enabled tools registry.",
                inputSchema: [
                    "type": "object",
                    "properties": ["minutes": ["type": "integer"]],
                    "required": ["minutes"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:tools.reset",
                name: "tools.reset",
                description: "Reset enabled tools back to baseline only.",
                inputSchema: ["type": "object", "properties": [:]]
            )
        ]
    }

    func callTool(name: String, arguments: [String : Any]) async throws -> MCPToolResult {
        guard let host = registryHost else {
            return MCPToolResult(content: "Registry host unavailable", isError: true)
        }
        switch name {
        case "tools.list":
            let catalog = host.toolCatalogByCategory()
            let data = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted])
            return MCPToolResult(content: String(data: data, encoding: .utf8) ?? "{}", isError: false)

        case "tools.enable":
            guard let arr = arguments["names"] as? [Any] else {
                return MCPToolResult(content: "names array is required", isError: true)
            }
            let names = arr.compactMap { $0 as? String }
            host.setEnabledToolNames(names)
            return MCPToolResult(content: "Enabled tools: \(names)", isError: false)

        case "tools.enable_categories":
            guard let arr = arguments["categories"] as? [Any] else {
                return MCPToolResult(content: "categories array is required", isError: true)
            }
            let cats = arr.compactMap { $0 as? String }
            // Map categories to tool names via catalog
            let catalog = host.toolCatalogByCategory()
            let names = cats.flatMap { catalog[$0] ?? [] }
            host.setEnabledToolNames(Array(Set(names)))
            return MCPToolResult(content: "Enabled categories: \(cats) → tools: \(names)", isError: false)

        case "tools.enable_ttl":
            guard let minutes = arguments["minutes"] as? Int else {
                return MCPToolResult(content: "minutes (integer) is required", isError: true)
            }
            host.setRegistryTTL(minutes: minutes)
            return MCPToolResult(content: "Registry TTL set to \(minutes) minutes", isError: false)

        case "tools.reset":
            host.setEnabledToolNames(nil)
            return MCPToolResult(content: "Enabled tools reset", isError: false)

        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }
}
