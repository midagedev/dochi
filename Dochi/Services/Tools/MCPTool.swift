import Foundation
import os

// MARK: - UserDefaults Key

private let mcpServersStorageKey = "mcp_server_configs"

// MARK: - Persistence Helpers

private func loadStoredConfigs() -> [MCPServerConfig] {
    guard let data = UserDefaults.standard.data(forKey: mcpServersStorageKey) else { return [] }
    do {
        return try JSONDecoder().decode([MCPServerConfig].self, from: data)
    } catch {
        Log.tool.error("Failed to decode stored MCP configs: \(error.localizedDescription)")
        return []
    }
}

private func saveStoredConfigs(_ configs: [MCPServerConfig]) {
    do {
        let data = try JSONEncoder().encode(configs)
        UserDefaults.standard.set(data, forKey: mcpServersStorageKey)
    } catch {
        Log.tool.error("Failed to encode MCP configs: \(error.localizedDescription)")
    }
}

// MARK: - settings.mcp_add_server

@MainActor
final class MCPAddServerTool: BuiltInToolProtocol {
    let name = "settings.mcp_add_server"
    let category: ToolCategory = .sensitive
    let description = "MCP 서버를 추가합니다."
    let isBaseline = false

    private let mcpService: MCPServiceProtocol

    init(mcpService: MCPServiceProtocol) {
        self.mcpService = mcpService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "서버 이름"],
                "command": ["type": "string", "description": "실행 명령어"],
                "arguments": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "명령어 인자 (선택)"
                ],
                "environment": [
                    "type": "object",
                    "additionalProperties": ["type": "string"],
                    "description": "환경 변수 (선택)"
                ],
                "is_enabled": ["type": "boolean", "description": "활성화 여부 (선택, 기본값 true)"]
            ],
            "required": ["name", "command"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: name은 필수입니다.", isError: true)
        }

        guard let command = arguments["command"] as? String, !command.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: command는 필수입니다.", isError: true)
        }

        let args = arguments["arguments"] as? [String] ?? []
        let env = arguments["environment"] as? [String: String] ?? [:]
        let isEnabled = arguments["is_enabled"] as? Bool ?? true

        let config = MCPServerConfig(
            name: name,
            command: command,
            arguments: args,
            environment: env,
            isEnabled: isEnabled
        )

        mcpService.addServer(config: config)

        // Persist to UserDefaults
        var stored = loadStoredConfigs()
        stored.append(config)
        saveStoredConfigs(stored)

        Log.tool.info("Added MCP server: \(name) (\(config.id))")
        return ToolResult(toolCallId: "", content: "MCP 서버 '\(name)'을(를) 추가했습니다. (ID: \(config.id))")
    }
}

// MARK: - settings.mcp_update_server

@MainActor
final class MCPUpdateServerTool: BuiltInToolProtocol {
    let name = "settings.mcp_update_server"
    let category: ToolCategory = .sensitive
    let description = "MCP 서버 설정을 수정합니다."
    let isBaseline = false

    private let mcpService: MCPServiceProtocol

    init(mcpService: MCPServiceProtocol) {
        self.mcpService = mcpService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "서버 UUID"],
                "name": ["type": "string", "description": "서버 이름 (선택)"],
                "command": ["type": "string", "description": "실행 명령어 (선택)"],
                "arguments": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "명령어 인자 (선택)"
                ],
                "environment": [
                    "type": "object",
                    "additionalProperties": ["type": "string"],
                    "description": "환경 변수 (선택)"
                ],
                "is_enabled": ["type": "boolean", "description": "활성화 여부 (선택)"]
            ],
            "required": ["id"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let idString = arguments["id"] as? String, let id = UUID(uuidString: idString) else {
            return ToolResult(toolCallId: "", content: "오류: 유효한 UUID 형식의 id가 필요합니다.", isError: true)
        }

        guard let existing = mcpService.getServer(id: id) else {
            return ToolResult(toolCallId: "", content: "오류: ID '\(id)'에 해당하는 MCP 서버를 찾을 수 없습니다.", isError: true)
        }

        let updatedConfig = MCPServerConfig(
            id: existing.id,
            name: (arguments["name"] as? String) ?? existing.name,
            command: (arguments["command"] as? String) ?? existing.command,
            arguments: (arguments["arguments"] as? [String]) ?? existing.arguments,
            environment: (arguments["environment"] as? [String: String]) ?? existing.environment,
            isEnabled: (arguments["is_enabled"] as? Bool) ?? existing.isEnabled
        )

        // Remove old, add updated
        mcpService.removeServer(id: id)
        mcpService.addServer(config: updatedConfig)

        // Update persisted configs
        var stored = loadStoredConfigs()
        stored.removeAll { $0.id == id }
        stored.append(updatedConfig)
        saveStoredConfigs(stored)

        Log.tool.info("Updated MCP server: \(updatedConfig.name) (\(id))")
        return ToolResult(toolCallId: "", content: "MCP 서버 '\(updatedConfig.name)' 설정을 수정했습니다.")
    }
}

// MARK: - settings.mcp_remove_server

@MainActor
final class MCPRemoveServerTool: BuiltInToolProtocol {
    let name = "settings.mcp_remove_server"
    let category: ToolCategory = .sensitive
    let description = "MCP 서버를 제거합니다."
    let isBaseline = false

    private let mcpService: MCPServiceProtocol

    init(mcpService: MCPServiceProtocol) {
        self.mcpService = mcpService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "제거할 서버 UUID"]
            ],
            "required": ["id"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let idString = arguments["id"] as? String, let id = UUID(uuidString: idString) else {
            return ToolResult(toolCallId: "", content: "오류: 유효한 UUID 형식의 id가 필요합니다.", isError: true)
        }

        guard mcpService.getServer(id: id) != nil else {
            return ToolResult(toolCallId: "", content: "오류: ID '\(id)'에 해당하는 MCP 서버를 찾을 수 없습니다.", isError: true)
        }

        mcpService.disconnect(serverId: id)
        mcpService.removeServer(id: id)

        // Remove from persisted configs
        var stored = loadStoredConfigs()
        stored.removeAll { $0.id == id }
        saveStoredConfigs(stored)

        Log.tool.info("Removed MCP server: \(id)")
        return ToolResult(toolCallId: "", content: "MCP 서버를 제거했습니다. (ID: \(id))")
    }
}
