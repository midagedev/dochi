import Foundation
import os

/// 에이전트 페르소나/메모리/설정 편집 도구
@MainActor
final class AgentEditorTool: BuiltInTool {
    var contextService: (any ContextServiceProtocol)?
    weak var settings: AppSettings?

    nonisolated var tools: [MCPToolInfo] {
        [
            // Persona
            MCPToolInfo(
                id: "builtin:agent.persona_get",
                name: "agent.persona_get",
                description: "Get persona.md for an agent. Defaults to active agent.",
                inputSchema: [
                    "type": "object",
                    "properties": ["name": ["type": "string"]]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.persona_search",
                name: "agent.persona_search",
                description: "Search persona.md and return matching lines with indices.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string"],
                        "name": ["type": "string"]
                    ],
                    "required": ["query"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.persona_replace",
                name: "agent.persona_replace",
                description: "Replace occurrences of 'find' with 'replace' in persona.md.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "find": ["type": "string"],
                        "replace": ["type": "string"],
                        "name": ["type": "string"]
                    ],
                    "required": ["find", "replace"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.persona_delete_lines",
                name: "agent.persona_delete_lines",
                description: "Delete lines in persona.md that contain the substring.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "contains": ["type": "string"],
                        "name": ["type": "string"]
                    ],
                    "required": ["contains"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.persona_update",
                name: "agent.persona_update",
                description: "Update persona.md (replace or append). Defaults to active agent.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "mode": ["type": "string", "enum": ["replace", "append"]],
                        "content": ["type": "string"],
                        "name": ["type": "string"]
                    ],
                    "required": ["mode", "content"]
                ]
            ),

            // Memory
            MCPToolInfo(
                id: "builtin:agent.memory_get",
                name: "agent.memory_get",
                description: "Get memory.md for an agent. Defaults to active agent.",
                inputSchema: [
                    "type": "object",
                    "properties": ["name": ["type": "string"]]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.memory_append",
                name: "agent.memory_append",
                description: "Append content to memory.md (prepends '- ' if needed). Defaults to active agent.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "content": ["type": "string"],
                        "name": ["type": "string"]
                    ],
                    "required": ["content"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.memory_replace",
                name: "agent.memory_replace",
                description: "Replace memory.md entirely. Defaults to active agent.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "content": ["type": "string"],
                        "name": ["type": "string"]
                    ],
                    "required": ["content"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.memory_update",
                name: "agent.memory_update",
                description: "Update or delete a single line in memory.md. Replaces the first line containing 'find' with '- replace'. If replace is empty, deletes the line.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "find": ["type": "string"],
                        "replace": ["type": "string"],
                        "name": ["type": "string"]
                    ],
                    "required": ["find", "replace"]
                ]
            ),

            // Config
            MCPToolInfo(
                id: "builtin:agent.config_get",
                name: "agent.config_get",
                description: "Get agent config (wakeWord, description). Defaults to active agent.",
                inputSchema: ["type": "object", "properties": ["name": ["type": "string"]]]
            ),
            MCPToolInfo(
                id: "builtin:agent.config_update",
                name: "agent.config_update",
                description: "Update agent config fields. Defaults to active agent.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "wake_word": ["type": "string"],
                        "description": ["type": "string"]
                    ]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String : Any]) async throws -> MCPToolResult {
        guard let contextService, let settings else {
            return MCPToolResult(content: "Agent editor requires contextService and settings", isError: true)
        }
        switch name {
        case "agent.persona_get":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            let text = wsId != nil
                ? contextService.loadAgentPersona(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentPersona(agentName: agentName)
            return MCPToolResult(content: text, isError: false)

        case "agent.persona_update":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            guard let mode = arguments["mode"] as? String, let content = arguments["content"] as? String else {
                return MCPToolResult(content: "mode and content are required", isError: true)
            }
            let current = wsId != nil
                ? contextService.loadAgentPersona(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentPersona(agentName: agentName)
            let updated: String
            if mode == "replace" { updated = content }
            else if mode == "append" {
                updated = current.isEmpty ? content : current + "\n\n" + content
            } else { return MCPToolResult(content: "mode must be replace|append", isError: true) }
            if let wsId {
                contextService.saveAgentPersona(workspaceId: wsId, agentName: agentName, content: updated)
            } else {
                contextService.saveAgentPersona(agentName: agentName, content: updated)
            }
            return MCPToolResult(content: "Persona updated (mode=\(mode))", isError: false)

        case "agent.persona_search":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            guard let query = arguments["query"] as? String, !query.isEmpty else {
                return MCPToolResult(content: "query is required", isError: true)
            }
            let text = wsId != nil
                ? contextService.loadAgentPersona(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentPersona(agentName: agentName)
            let lines = text.components(separatedBy: "\n")
            var matches: [[String: Any]] = []
            for (idx, line) in lines.enumerated() where line.localizedCaseInsensitiveContains(query) {
                matches.append(["index": idx, "line": line])
            }
            let data = try? JSONSerialization.data(withJSONObject: matches, options: [.prettyPrinted])
            return MCPToolResult(content: String(data: data ?? Data()) , isError: false)

        case "agent.persona_replace":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            guard let find = arguments["find"] as? String, let replace = arguments["replace"] as? String else {
                return MCPToolResult(content: "find and replace are required", isError: true)
            }
            let text = wsId != nil
                ? contextService.loadAgentPersona(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentPersona(agentName: agentName)
            let replaced = text.replacingOccurrences(of: find, with: replace, options: [.caseInsensitive])
            if let wsId {
                contextService.saveAgentPersona(workspaceId: wsId, agentName: agentName, content: replaced)
            } else {
                contextService.saveAgentPersona(agentName: agentName, content: replaced)
            }
            return MCPToolResult(content: "Persona replaced occurrences", isError: false)

        case "agent.persona_delete_lines":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            guard let contains = arguments["contains"] as? String, !contains.isEmpty else {
                return MCPToolResult(content: "contains is required", isError: true)
            }
            let text = wsId != nil
                ? contextService.loadAgentPersona(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentPersona(agentName: agentName)
            let lines = text.components(separatedBy: "\n")
            let filtered = lines.filter { !$0.localizedCaseInsensitiveContains(contains) }
            if let wsId {
                contextService.saveAgentPersona(workspaceId: wsId, agentName: agentName, content: filtered.joined(separator: "\n"))
            } else {
                contextService.saveAgentPersona(agentName: agentName, content: filtered.joined(separator: "\n"))
            }
            let removed = lines.count - filtered.count
            return MCPToolResult(content: "Deleted \(removed) lines", isError: false)

        case "agent.memory_get":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            let text = wsId != nil
                ? contextService.loadAgentMemory(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentMemory(agentName: agentName)
            return MCPToolResult(content: text, isError: false)

        case "agent.memory_append":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            guard let content = arguments["content"] as? String else {
                return MCPToolResult(content: "content is required", isError: true)
            }
            let entry = content.hasPrefix("-") ? content : "- \(content)"
            if let wsId {
                contextService.appendAgentMemory(workspaceId: wsId, agentName: agentName, content: entry)
            } else {
                contextService.appendAgentMemory(agentName: agentName, content: entry)
            }
            return MCPToolResult(content: "Memory appended", isError: false)

        case "agent.memory_replace":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            guard let content = arguments["content"] as? String else {
                return MCPToolResult(content: "content is required", isError: true)
            }
            if let wsId {
                contextService.saveAgentMemory(workspaceId: wsId, agentName: agentName, content: content)
            } else {
                contextService.saveAgentMemory(agentName: agentName, content: content)
            }
            return MCPToolResult(content: "Memory replaced", isError: false)

        case "agent.memory_update":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            guard let find = arguments["find"] as? String, let replace = arguments["replace"] as? String else {
                return MCPToolResult(content: "find and replace are required", isError: true)
            }
            let text = wsId != nil
                ? contextService.loadAgentMemory(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentMemory(agentName: agentName)
            var lines = text.components(separatedBy: "\n")
            if let idx = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(find) }) {
                if replace.isEmpty {
                    lines.remove(at: idx)
                } else {
                    let newLine = replace.hasPrefix("-") ? replace : "- \(replace)"
                    lines[idx] = newLine
                }
                let newText = lines.joined(separator: "\n")
                if let wsId {
                    contextService.saveAgentMemory(workspaceId: wsId, agentName: agentName, content: newText)
                } else {
                    contextService.saveAgentMemory(agentName: agentName, content: newText)
                }
                return MCPToolResult(content: replace.isEmpty ? "Deleted 1 line" : "Updated 1 line", isError: false)
            } else {
                return MCPToolResult(content: "No line found containing '\(find)'", isError: true)
            }

        case "agent.config_get":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            let cfg = wsId != nil
                ? contextService.loadAgentConfig(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentConfig(agentName: agentName)
            let dict: [String: Any] = [
                "name": cfg?.name ?? agentName,
                "wakeWord": cfg?.wakeWord ?? settings.wakeWord,
                "description": cfg?.description ?? ""
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]), let str = String(data: data, encoding: .utf8) {
                return MCPToolResult(content: str, isError: false)
            }
            return MCPToolResult(content: "{}", isError: false)

        case "agent.config_update":
            let (agentName, wsId) = resolveAgentNameAndWorkspace(settings: settings, args: arguments)
            let wake = (arguments["wake_word"] as? String)
            let desc = (arguments["description"] as? String)
            var cfg = wsId != nil
                ? contextService.loadAgentConfig(workspaceId: wsId!, agentName: agentName)
                : contextService.loadAgentConfig(agentName: agentName)
            if cfg == nil { cfg = AgentConfig(name: agentName, wakeWord: wake ?? settings.wakeWord, description: desc ?? "") }
            if let wake { cfg!.wakeWord = wake }
            if let desc { cfg!.description = desc }
            if let wsId {
                contextService.saveAgentConfig(workspaceId: wsId, config: cfg!)
            } else {
                contextService.saveAgentConfig(cfg!)
            }
            return MCPToolResult(content: "Config updated for \(agentName)", isError: false)

        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    // MARK: - Helpers
    private func resolveAgentNameAndWorkspace(settings: AppSettings, args: [String: Any]) -> (String, UUID?) {
        let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let agentName = (name?.isEmpty ?? true) ? settings.activeAgentName : name!
        return (agentName, settings.currentWorkspaceId)
    }
}
