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
            let descriptions: [String: String] = [
                "registry": "Tool registry operations (list/enable/ttl/reset)",
                "reminders": "Apple Reminders (create/list/complete)",
                "alarm": "Voice alarms via TTS (set/list/cancel)",
                "memory": "Family/personal memory save/update",
                "profile": "User identification (set_current_user)",
                "search_image": "Web search and image generation/print",
                "settings": "App settings and MCP servers",
                "agent": "Agent create/list/set_active",
                "agent_edit": "Agent persona/memory/config editing",
                "context": "Base system prompt editing",
                "profile_admin": "Profile create/alias/rename/merge",
                "workspace": "Supabase workspace ops",
                "telegram": "Telegram integration ops",
                "coding": "Claude Code helpers (open, IDE, clipboard)",
                "claude_ui": "Claude Code UI API integration (health, MCP manage)"
            ]
            let payload: [String: Any] = [
                "catalog": catalog,
                "descriptions": descriptions,
                "enabled": host.getEnabledToolNames() ?? [],
                "baseline_count": 1, // registry tools always present; baseline dynamic in host
                "available_tool_count": catalog.values.reduce(0) { $0 + $1.count }
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            return MCPToolResult(content: String(data: data, encoding: .utf8) ?? "{}", isError: false)

        case "tools.enable":
            guard let arr = arguments["names"] as? [Any] else {
                return MCPToolResult(content: "names array is required", isError: true)
            }
            let names = arr.compactMap { $0 as? String }
            host.setEnabledToolNames(names)
            Log.tool.info("tools.enable names=\(names)")
            return MCPToolResult(content: "Enabled tools: \(names)", isError: false)

        case "tools.enable_categories":
            guard let arr = arguments["categories"] as? [Any] else {
                return MCPToolResult(content: "categories array is required", isError: true)
            }
            let cats = arr.compactMap { $0 as? String }
            // Map categories to tool names via catalog
            let catalog = host.toolCatalogByCategory()
            var allNames: [String] = []
            var unknown: [String] = []
            for c in cats {
                if let list = catalog[c], !list.isEmpty { allNames.append(contentsOf: list) }
                else { unknown.append(c) }
            }
            guard !allNames.isEmpty else {
                return MCPToolResult(content: "No tools found for categories: \(cats)", isError: true)
            }
            let unique = Array(Set(allNames)).sorted()
            host.setEnabledToolNames(unique)
            Log.tool.info("tools.enable_categories cats=\(cats) enabled=\(unique) unknown=\(unknown)")
            var msg = "Enabled categories: \(cats) → tools: \(unique)"
            if !unknown.isEmpty { msg += " (unknown categories: \(unknown))" }
            return MCPToolResult(content: msg, isError: false)

        case "tools.enable_ttl":
            guard let minutes = arguments["minutes"] as? Int else {
                return MCPToolResult(content: "minutes (integer) is required", isError: true)
            }
            host.setRegistryTTL(minutes: minutes)
            Log.tool.info("tools.enable_ttl minutes=\(minutes)")
            return MCPToolResult(content: "Registry TTL set to \(minutes) minutes", isError: false)

        case "tools.reset":
            host.setEnabledToolNames(nil)
            Log.tool.info("tools.reset")
            return MCPToolResult(content: "Enabled tools reset", isError: false)

        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }
}
