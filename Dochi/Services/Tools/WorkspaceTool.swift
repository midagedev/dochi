import Foundation
import os

// MARK: - workspace.create

@MainActor
final class WorkspaceCreateTool: BuiltInToolProtocol {
    let name = "workspace.create"
    let category: ToolCategory = .sensitive
    let description = "새 워크스페이스를 생성합니다."
    let isBaseline = false

    private let supabaseService: SupabaseServiceProtocol
    private let settings: AppSettings

    init(supabaseService: SupabaseServiceProtocol, settings: AppSettings) {
        self.supabaseService = supabaseService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "워크스페이스 이름"]
            ],
            "required": ["name"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String, !name.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: name은 필수입니다.", isError: true)
        }

        do {
            let workspace = try await supabaseService.createWorkspace(name: name)
            Log.tool.info("Created workspace: \(workspace.name) (\(workspace.id))")
            var result = "워크스페이스를 생성했습니다.\n"
            result += "- 이름: \(workspace.name)\n"
            result += "- ID: \(workspace.id)\n"
            if let inviteCode = workspace.inviteCode {
                result += "- 초대 코드: \(inviteCode)"
            }
            return ToolResult(toolCallId: "", content: result)
        } catch {
            Log.tool.error("Failed to create workspace: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 워크스페이스 생성 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - workspace.join_by_invite

@MainActor
final class WorkspaceJoinByInviteTool: BuiltInToolProtocol {
    let name = "workspace.join_by_invite"
    let category: ToolCategory = .sensitive
    let description = "초대 코드로 워크스페이스에 참여합니다."
    let isBaseline = false

    private let supabaseService: SupabaseServiceProtocol
    private let settings: AppSettings

    init(supabaseService: SupabaseServiceProtocol, settings: AppSettings) {
        self.supabaseService = supabaseService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "invite_code": ["type": "string", "description": "초대 코드"]
            ],
            "required": ["invite_code"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let inviteCode = arguments["invite_code"] as? String, !inviteCode.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: invite_code는 필수입니다.", isError: true)
        }

        do {
            let workspace = try await supabaseService.joinWorkspace(inviteCode: inviteCode)
            Log.tool.info("Joined workspace: \(workspace.name) (\(workspace.id))")
            return ToolResult(toolCallId: "", content: "워크스페이스 '\(workspace.name)'에 참여했습니다. (ID: \(workspace.id))")
        } catch {
            Log.tool.error("Failed to join workspace: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 워크스페이스 참여 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - workspace.list

@MainActor
final class WorkspaceListTool: BuiltInToolProtocol {
    let name = "workspace.list"
    let category: ToolCategory = .sensitive
    let description = "참여 중인 워크스페이스 목록을 조회합니다."
    let isBaseline = false

    private let supabaseService: SupabaseServiceProtocol
    private let settings: AppSettings

    init(supabaseService: SupabaseServiceProtocol, settings: AppSettings) {
        self.supabaseService = supabaseService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [String: Any]()
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        do {
            let workspaces = try await supabaseService.listWorkspaces()

            if workspaces.isEmpty {
                return ToolResult(toolCallId: "", content: "참여 중인 워크스페이스가 없습니다.")
            }

            let currentId = settings.currentWorkspaceId
            var lines: [String] = []

            for ws in workspaces {
                let isCurrent = ws.id.uuidString == currentId
                let marker = isCurrent ? " ★ (현재)" : ""
                var parts: [String] = ["• \(ws.name)\(marker)"]
                parts.append("  ID: \(ws.id)")
                if let inviteCode = ws.inviteCode {
                    parts.append("  초대 코드: \(inviteCode)")
                }
                lines.append(parts.joined(separator: "\n"))
            }

            Log.tool.info("Listed \(workspaces.count) workspaces")
            return ToolResult(toolCallId: "", content: "워크스페이스 목록 (\(workspaces.count)개):\n\(lines.joined(separator: "\n"))")
        } catch {
            Log.tool.error("Failed to list workspaces: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 워크스페이스 목록 조회 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - workspace.switch

@MainActor
final class WorkspaceSwitchTool: BuiltInToolProtocol {
    let name = "workspace.switch"
    let category: ToolCategory = .sensitive
    let description = "활성 워크스페이스를 변경합니다. 다음 대화부터 적용됩니다."
    let isBaseline = false

    private let supabaseService: SupabaseServiceProtocol
    private let settings: AppSettings

    init(supabaseService: SupabaseServiceProtocol, settings: AppSettings) {
        self.supabaseService = supabaseService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "전환할 워크스페이스 UUID"]
            ],
            "required": ["id"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let idString = arguments["id"] as? String, let id = UUID(uuidString: idString) else {
            return ToolResult(toolCallId: "", content: "오류: 유효한 UUID 형식의 id가 필요합니다.", isError: true)
        }

        settings.currentWorkspaceId = id.uuidString
        Log.tool.info("Switched workspace to: \(id)")
        return ToolResult(toolCallId: "", content: "워크스페이스를 '\(id)'(으)로 변경했습니다. 다음 대화부터 적용됩니다.")
    }
}

// MARK: - workspace.regenerate_invite_code

@MainActor
final class WorkspaceRegenerateInviteCodeTool: BuiltInToolProtocol {
    let name = "workspace.regenerate_invite_code"
    let category: ToolCategory = .sensitive
    let description = "워크스페이스의 초대 코드를 재생성합니다."
    let isBaseline = false

    private let supabaseService: SupabaseServiceProtocol
    private let settings: AppSettings

    init(supabaseService: SupabaseServiceProtocol, settings: AppSettings) {
        self.supabaseService = supabaseService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "워크스페이스 UUID"]
            ],
            "required": ["id"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let idString = arguments["id"] as? String, let id = UUID(uuidString: idString) else {
            return ToolResult(toolCallId: "", content: "오류: 유효한 UUID 형식의 id가 필요합니다.", isError: true)
        }

        do {
            let newCode = try await supabaseService.regenerateInviteCode(workspaceId: id)
            Log.tool.info("Regenerated invite code for workspace: \(id)")
            return ToolResult(toolCallId: "", content: "새 초대 코드: \(newCode)")
        } catch {
            Log.tool.error("Failed to regenerate invite code: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 초대 코드 재생성 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}
