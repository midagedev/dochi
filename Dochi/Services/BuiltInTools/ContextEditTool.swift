import Foundation
import os

/// 컨텍스트 파일 편집 도구 (base system prompt)
@MainActor
final class ContextEditTool: BuiltInTool {
    var contextService: (any ContextServiceProtocol)?
    weak var settings: AppSettings?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:context.update_base_system_prompt",
                name: "context.update_base_system_prompt",
                description: "Replace or append to the base system prompt (system_prompt.md).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "mode": ["type": "string", "enum": ["replace", "append"]],
                        "content": ["type": "string"]
                    ],
                    "required": ["mode", "content"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let contextService else {
            return MCPToolResult(content: "ContextService not available", isError: true)
        }
        switch name {
        case "context.update_base_system_prompt":
            guard let mode = arguments["mode"] as? String, let content = arguments["content"] as? String else {
                return MCPToolResult(content: "mode and content are required", isError: true)
            }
            let current = contextService.loadBaseSystemPrompt()
            let updated: String
            if mode == "replace" {
                updated = content
            } else if mode == "append" {
                updated = current.isEmpty ? content : current + "\n\n" + content
            } else {
                return MCPToolResult(content: "mode must be 'replace' or 'append'", isError: true)
            }
            contextService.saveBaseSystemPrompt(updated)
            Log.tool.info("system_prompt.md updated (mode=\(mode))")
            return MCPToolResult(content: "Base system prompt updated (mode=\(mode))", isError: false)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }
}

