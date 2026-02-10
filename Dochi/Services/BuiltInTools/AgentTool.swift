import Foundation
import os

/// 에이전트 생성/목록/전환 도구
@MainActor
final class AgentTool: BuiltInTool {
    var contextService: (any ContextServiceProtocol)?
    weak var settings: AppSettings?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:agent.create",
                name: "agent.create",
                description: "Create a new agent with optional wake word and description. Workspace-aware if currentWorkspaceId is set.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "wake_word": ["type": "string"],
                        "description": ["type": "string"]
                    ],
                    "required": ["name"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.list",
                name: "agent.list",
                description: "List agent names. Workspace-aware if currentWorkspaceId is set.",
                inputSchema: [
                    "type": "object",
                    "properties": [:]
                ]
            ),
            MCPToolInfo(
                id: "builtin:agent.set_active",
                name: "agent.set_active",
                description: "Set active agent by name.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"]
                    ],
                    "required": ["name"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let contextService, let settings else {
            return MCPToolResult(content: "Agent tools require contextService and settings.", isError: true)
        }
        switch name {
        case "agent.create":
            return createAgent(contextService: contextService, settings: settings, args: arguments)
        case "agent.list":
            return listAgents(contextService: contextService, settings: settings)
        case "agent.set_active":
            return setActiveAgent(settings: settings, contextService: contextService, args: arguments)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    private func createAgent(contextService: any ContextServiceProtocol, settings: AppSettings, args: [String: Any]) -> MCPToolResult {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return MCPToolResult(content: "name is required", isError: true)
        }
        let wake = (args["wake_word"] as? String) ?? settings.wakeWord
        let desc = (args["description"] as? String) ?? ""

        if let wsId = settings.currentWorkspaceId {
            contextService.createAgent(workspaceId: wsId, name: name, wakeWord: wake, description: desc)
        } else {
            contextService.createAgent(name: name, wakeWord: wake, description: desc)
        }
        Log.tool.info("에이전트 생성: name=\(name), wake=\(wake)")
        return MCPToolResult(content: "Created agent '\(name)'", isError: false)
    }

    private func listAgents(contextService: any ContextServiceProtocol, settings: AppSettings) -> MCPToolResult {
        let names: [String]
        if let wsId = settings.currentWorkspaceId {
            names = contextService.listAgents(workspaceId: wsId)
        } else {
            names = contextService.listAgents()
        }
        if let data = try? JSONSerialization.data(withJSONObject: names, options: [.prettyPrinted]), let str = String(data: data, encoding: .utf8) {
            return MCPToolResult(content: str, isError: false)
        }
        return MCPToolResult(content: names.joined(separator: ", "), isError: false)
    }

    private func setActiveAgent(settings: AppSettings, contextService: any ContextServiceProtocol, args: [String: Any]) -> MCPToolResult {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return MCPToolResult(content: "name is required", isError: true)
        }
        let available: [String]
        if let wsId = settings.currentWorkspaceId {
            available = contextService.listAgents(workspaceId: wsId)
        } else {
            available = contextService.listAgents()
        }
        guard available.contains(name) else {
            return MCPToolResult(content: "Agent not found: \(name). Available: \(available)", isError: true)
        }
        settings.activeAgentName = name
        return MCPToolResult(content: "Active agent set to \(name)", isError: false)
    }
}

