import Foundation
import os

/// 앱 설정 변경/조회용 내장 도구
@MainActor
final class SettingsTool: BuiltInTool {
    weak var settings: AppSettings?

    // 지원 키와 타입 정의
    private enum Key: String, CaseIterable {
        case wakeWordEnabled
        case wakeWord
        case llmProvider
        case llmModel
        case supertonicVoice
        case ttsSpeed
        case ttsDiffusionSteps
        case chatFontSize
        case sttSilenceTimeout
        case contextAutoCompress
        case contextMaxSize
        case activeAgentName
        case telegramEnabled
        case defaultUserId

        // API keys
        case openaiApiKey
        case anthropicApiKey
        case zaiApiKey
        case tavilyApiKey
        case falaiApiKey
        case telegramBotToken
    }

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:settings.set",
                name: "settings.set",
                description: "Set an application setting. Use list to discover keys and types.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "key": [
                            "type": "string",
                            "enum": Key.allCases.map { $0.rawValue },
                            "description": "Setting key to update"
                        ],
                        "value": [
                            "type": "string",
                            "description": "New value (stringified). Types are inferred per key"
                        ]
                    ],
                    "required": ["key", "value"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:settings.get",
                name: "settings.get",
                description: "Get current value of a setting key.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "key": [
                            "type": "string",
                            "enum": Key.allCases.map { $0.rawValue }
                        ]
                    ],
                    "required": ["key"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:settings.list",
                name: "settings.list",
                description: "List supported setting keys and current values.",
                inputSchema: [
                    "type": "object",
                    "properties": [:]
                ]
            ),
            // MCP servers management
            MCPToolInfo(
                id: "builtin:settings.mcp_add_server",
                name: "settings.mcp_add_server",
                description: "Add a new MCP server configuration (HTTP-only supported).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "command": ["type": "string", "description": "HTTP endpoint URL"],
                        "arguments": ["type": "array", "items": ["type": "string"]],
                        "environment": ["type": "object", "additionalProperties": ["type": "string"]],
                        "is_enabled": ["type": "boolean"]
                    ],
                    "required": ["name", "command"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:settings.mcp_update_server",
                name: "settings.mcp_update_server",
                description: "Update an existing MCP server configuration by id.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "UUID"],
                        "name": ["type": "string"],
                        "command": ["type": "string"],
                        "arguments": ["type": "array", "items": ["type": "string"]],
                        "environment": ["type": "object", "additionalProperties": ["type": "string"]],
                        "is_enabled": ["type": "boolean"]
                    ],
                    "required": ["id"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:settings.mcp_remove_server",
                name: "settings.mcp_remove_server",
                description: "Remove an MCP server by id.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "UUID"]
                    ],
                    "required": ["id"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let settings else {
            return MCPToolResult(content: "Settings are not available.", isError: true)
        }

        switch name {
        case "settings.set":
            return setSetting(settings, arguments)
        case "settings.get":
            return getSetting(settings, arguments)
        case "settings.list":
            return listSettings(settings)
        case "settings.mcp_add_server":
            return try addMCPServer(settings, arguments)
        case "settings.mcp_update_server":
            return try updateMCPServer(settings, arguments)
        case "settings.mcp_remove_server":
            return try removeMCPServer(settings, arguments)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    // MARK: - Core

    private func setSetting(_ s: AppSettings, _ args: [String: Any]) -> MCPToolResult {
        guard let keyStr = args["key"] as? String, let key = Key(rawValue: keyStr) else {
            return MCPToolResult(content: "Invalid or missing key", isError: true)
        }
        guard let valueStr = args["value"] as? String else {
            return MCPToolResult(content: "Missing value (string)", isError: true)
        }

        switch key {
        case .wakeWordEnabled:
            s.wakeWordEnabled = parseBool(valueStr)
        case .wakeWord:
            s.wakeWord = valueStr
        case .llmProvider:
            guard let provider = LLMProvider(rawValue: valueStr) else {
                return MCPToolResult(content: "Invalid provider. Allowed: \(LLMProvider.allCases.map { $0.rawValue }.joined(separator: ", "))", isError: true)
            }
            s.llmProvider = provider
        case .llmModel:
            if !s.llmProvider.models.contains(valueStr) {
                return MCPToolResult(content: "Model not in provider models: \(s.llmProvider.models)", isError: true)
            }
            s.llmModel = valueStr
        case .supertonicVoice:
            guard let voice = SupertonicVoice(rawValue: valueStr) else {
                return MCPToolResult(content: "Invalid voice. Allowed: \(SupertonicVoice.allCases.map { $0.rawValue }.joined(separator: ", "))", isError: true)
            }
            s.supertonicVoice = voice
        case .ttsSpeed:
            guard let v = Float(valueStr) else { return MCPToolResult(content: "ttsSpeed must be float", isError: true) }
            s.ttsSpeed = v
        case .ttsDiffusionSteps:
            guard let v = Int(valueStr) else { return MCPToolResult(content: "ttsDiffusionSteps must be int", isError: true) }
            s.ttsDiffusionSteps = v
        case .chatFontSize:
            guard let v = Double(valueStr) else { return MCPToolResult(content: "chatFontSize must be number", isError: true) }
            s.chatFontSize = v
        case .sttSilenceTimeout:
            guard let v = Double(valueStr) else { return MCPToolResult(content: "sttSilenceTimeout must be number", isError: true) }
            s.sttSilenceTimeout = v
        case .contextAutoCompress:
            s.contextAutoCompress = parseBool(valueStr)
        case .contextMaxSize:
            guard let v = Int(valueStr) else { return MCPToolResult(content: "contextMaxSize must be int", isError: true) }
            s.contextMaxSize = v
        case .activeAgentName:
            s.activeAgentName = valueStr
        case .telegramEnabled:
            s.telegramEnabled = parseBool(valueStr)
        case .defaultUserId:
            if valueStr.isEmpty || valueStr.lowercased() == "none" {
                s.defaultUserId = nil
            } else if let uuid = UUID(uuidString: valueStr) {
                s.defaultUserId = uuid
            } else {
                return MCPToolResult(content: "defaultUserId must be UUID or 'none'", isError: true)
            }

        case .openaiApiKey:
            s.apiKey = valueStr
        case .anthropicApiKey:
            s.anthropicApiKey = valueStr
        case .zaiApiKey:
            s.zaiApiKey = valueStr
        case .tavilyApiKey:
            s.tavilyApiKey = valueStr
        case .falaiApiKey:
            s.falaiApiKey = valueStr
        case .telegramBotToken:
            s.telegramBotToken = valueStr
        }

        Log.tool.info("설정 변경: \(key.rawValue)=\(valueStr.prefix(80))")
        return MCPToolResult(content: "Updated \(key.rawValue)", isError: false)
    }

    private func getSetting(_ s: AppSettings, _ args: [String: Any]) -> MCPToolResult {
        guard let keyStr = args["key"] as? String, let key = Key(rawValue: keyStr) else {
            return MCPToolResult(content: "Invalid or missing key", isError: true)
        }
        let value: String
        switch key {
        case .wakeWordEnabled: value = String(s.wakeWordEnabled)
        case .wakeWord: value = s.wakeWord
        case .llmProvider: value = s.llmProvider.rawValue
        case .llmModel: value = s.llmModel
        case .supertonicVoice: value = s.supertonicVoice.rawValue
        case .ttsSpeed: value = String(s.ttsSpeed)
        case .ttsDiffusionSteps: value = String(s.ttsDiffusionSteps)
        case .chatFontSize: value = String(s.chatFontSize)
        case .sttSilenceTimeout: value = String(s.sttSilenceTimeout)
        case .contextAutoCompress: value = String(s.contextAutoCompress)
        case .contextMaxSize: value = String(s.contextMaxSize)
        case .activeAgentName: value = s.activeAgentName
        case .telegramEnabled: value = String(s.telegramEnabled)
        case .defaultUserId: value = s.defaultUserId?.uuidString ?? ""
        case .openaiApiKey: value = s.apiKey.isEmpty ? "" : "***"
        case .anthropicApiKey: value = s.anthropicApiKey.isEmpty ? "" : "***"
        case .zaiApiKey: value = s.zaiApiKey.isEmpty ? "" : "***"
        case .tavilyApiKey: value = s.tavilyApiKey.isEmpty ? "" : "***"
        case .falaiApiKey: value = s.falaiApiKey.isEmpty ? "" : "***"
        case .telegramBotToken: value = s.telegramBotToken.isEmpty ? "" : "***"
        }
        return MCPToolResult(content: "{\"key\":\"\(key.rawValue)\",\"value\":\"\(value)\"}", isError: false)
    }

    private func listSettings(_ s: AppSettings) -> MCPToolResult {
        // 간단한 JSON 문자열 반환
        var items: [[String: String]] = []
        for key in Key.allCases {
            let value = getSetting(s, ["key": key.rawValue]).content
            items.append(["key": key.rawValue, "value": value])
        }
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]), let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = items.map { "\($0["key"] ?? ""): \($0["value"] ?? "")" }.joined(separator: "\n")
        }
        return MCPToolResult(content: json, isError: false)
    }

    // MARK: - MCP Servers

    private func addMCPServer(_ s: AppSettings, _ args: [String: Any]) throws -> MCPToolResult {
        guard let name = args["name"] as? String, !name.isEmpty, let command = args["command"] as? String, !command.isEmpty else {
            throw BuiltInToolError.invalidArguments("name and command are required")
        }
        let arguments = (args["arguments"] as? [Any])?.compactMap { $0 as? String } ?? []
        let env = args["environment"] as? [String: String]
        let isEnabled = (args["is_enabled"] as? Bool) ?? true

        let config = MCPServerConfig(name: name, command: command, arguments: arguments, environment: env, isEnabled: isEnabled)
        s.addMCPServer(config)
        return MCPToolResult(content: "Added MCP server id=\(config.id.uuidString)", isError: false)
    }

    private func updateMCPServer(_ s: AppSettings, _ args: [String: Any]) throws -> MCPToolResult {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            throw BuiltInToolError.invalidArguments("id must be UUID")
        }
        guard let existing = s.mcpServers.first(where: { $0.id == id }) else {
            return MCPToolResult(content: "Server not found: \(idStr)", isError: true)
        }
        var new = existing
        if let name = args["name"] as? String { new.name = name }
        if let command = args["command"] as? String { new.command = command }
        if let argArr = args["arguments"] as? [Any] { new.arguments = argArr.compactMap { $0 as? String } }
        if let env = args["environment"] as? [String: String] { new.environment = env }
        if let enabled = args["is_enabled"] as? Bool { new.isEnabled = enabled }
        s.updateMCPServer(new)
        return MCPToolResult(content: "Updated MCP server id=\(id.uuidString)", isError: false)
    }

    private func removeMCPServer(_ s: AppSettings, _ args: [String: Any]) throws -> MCPToolResult {
        guard let idStr = args["id"] as? String, let id = UUID(uuidString: idStr) else {
            throw BuiltInToolError.invalidArguments("id must be UUID")
        }
        s.removeMCPServer(id: id)
        return MCPToolResult(content: "Removed MCP server id=\(id.uuidString)", isError: false)
    }

    // MARK: - Helpers

    private func parseBool(_ str: String) -> Bool {
        let v = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["true", "1", "yes", "on", "y"].contains(v)
    }
}

