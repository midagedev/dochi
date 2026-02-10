import Foundation
import os

/// 워크스페이스 관리 도구 (Supabase 연동 필요)
@MainActor
final class WorkspaceTool: BuiltInTool {
    weak var settings: AppSettings?
    var supabase: (any SupabaseServiceProtocol)?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:workspace.create",
                name: "workspace.create",
                description: "Create a new workspace (requires auth).",
                inputSchema: [
                    "type": "object",
                    "properties": ["name": ["type": "string"]],
                    "required": ["name"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:workspace.join_by_invite",
                name: "workspace.join_by_invite",
                description: "Join a workspace using invite code.",
                inputSchema: [
                    "type": "object",
                    "properties": ["invite_code": ["type": "string"]],
                    "required": ["invite_code"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:workspace.list",
                name: "workspace.list",
                description: "List workspaces for current user.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:workspace.switch",
                name: "workspace.switch",
                description: "Switch current workspace by id.",
                inputSchema: [
                    "type": "object",
                    "properties": ["id": ["type": "string"]],
                    "required": ["id"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:workspace.regenerate_invite_code",
                name: "workspace.regenerate_invite_code",
                description: "Regenerate invite code (owner permission required).",
                inputSchema: [
                    "type": "object",
                    "properties": ["id": ["type": "string"]],
                    "required": ["id"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let supabase else {
            return MCPToolResult(content: "Supabase is not configured", isError: true)
        }
        switch name {
        case "workspace.create":
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                return MCPToolResult(content: "name is required", isError: true)
            }
            do {
                let ws = try await supabase.createWorkspace(name: name)
                return MCPToolResult(content: "Created workspace \(ws.name) (id=\(ws.id), invite=\(ws.inviteCode ?? ""))", isError: false)
            } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "workspace.join_by_invite":
            guard let code = arguments["invite_code"] as? String, !code.isEmpty else {
                return MCPToolResult(content: "invite_code is required", isError: true)
            }
            do {
                let ws = try await supabase.joinWorkspace(inviteCode: code)
                return MCPToolResult(content: "Joined workspace \(ws.name) (id=\(ws.id))", isError: false)
            } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "workspace.list":
            do {
                let wss = try await supabase.listWorkspaces()
                let arr = wss.map { ["id": $0.id.uuidString, "name": $0.name] }
                let data = try JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted])
                return MCPToolResult(content: String(data: data, encoding: .utf8) ?? "", isError: false)
            } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "workspace.switch":
            guard let idStr = arguments["id"] as? String, let id = UUID(uuidString: idStr) else {
                return MCPToolResult(content: "id must be UUID", isError: true)
            }
            do {
                // Fetch details and set current
                let all = try await supabase.listWorkspaces()
                if let ws = all.first(where: { $0.id == id }) {
                    supabase.setCurrentWorkspace(ws)
                    return MCPToolResult(content: "Switched workspace to \(ws.name)", isError: false)
                } else {
                    return MCPToolResult(content: "Workspace not found: \(idStr)", isError: true)
                }
            } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "workspace.regenerate_invite_code":
            guard let idStr = arguments["id"] as? String, let id = UUID(uuidString: idStr) else {
                return MCPToolResult(content: "id must be UUID", isError: true)
            }
            do {
                let code = try await supabase.regenerateInviteCode(workspaceId: id)
                return MCPToolResult(content: "New invite code: \(code)", isError: false)
            } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }
}

