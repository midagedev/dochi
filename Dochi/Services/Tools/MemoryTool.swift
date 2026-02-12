import Foundation
import os

@MainActor
final class SaveMemoryTool: BuiltInToolProtocol {
    let name = "save_memory"
    let category: ToolCategory = .safe
    let description = "워크스페이스 또는 개인 메모리에 내용을 저장합니다."
    let isBaseline = true

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext

    init(contextService: ContextServiceProtocol, sessionContext: SessionContext) {
        self.contextService = contextService
        self.sessionContext = sessionContext
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "content": ["type": "string", "description": "저장할 내용"],
                "scope": [
                    "type": "string",
                    "enum": ["workspace", "personal"],
                    "description": "저장 범위: workspace (워크스페이스 공유) 또는 personal (개인)"
                ]
            ],
            "required": ["content", "scope"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let content = arguments["content"] as? String, !content.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: content는 필수입니다.", isError: true)
        }
        guard let scope = arguments["scope"] as? String,
              scope == "workspace" || scope == "personal" else {
            return ToolResult(toolCallId: "", content: "오류: scope는 'workspace' 또는 'personal'이어야 합니다.", isError: true)
        }

        if scope == "workspace" {
            contextService.appendWorkspaceMemory(workspaceId: sessionContext.workspaceId, content: content)
            Log.tool.info("Saved workspace memory")
            return ToolResult(toolCallId: "", content: "워크스페이스 메모리에 저장했습니다.")
        } else {
            guard let userId = sessionContext.currentUserId else {
                return ToolResult(toolCallId: "", content: "오류: 현재 사용자가 설정되지 않았습니다. set_current_user를 먼저 사용해주세요.", isError: true)
            }
            contextService.appendUserMemory(userId: userId, content: content)
            Log.tool.info("Saved personal memory for user: \(userId)")
            return ToolResult(toolCallId: "", content: "개인 메모리에 저장했습니다.")
        }
    }
}

@MainActor
final class UpdateMemoryTool: BuiltInToolProtocol {
    let name = "update_memory"
    let category: ToolCategory = .safe
    let description = "워크스페이스 또는 개인 메모리의 특정 내용을 수정합니다."
    let isBaseline = true

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext

    init(contextService: ContextServiceProtocol, sessionContext: SessionContext) {
        self.contextService = contextService
        self.sessionContext = sessionContext
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "old_content": ["type": "string", "description": "찾을 기존 내용"],
                "new_content": ["type": "string", "description": "대체할 새 내용"],
                "scope": [
                    "type": "string",
                    "enum": ["workspace", "personal"],
                    "description": "수정 범위: workspace 또는 personal"
                ]
            ],
            "required": ["old_content", "new_content", "scope"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let oldContent = arguments["old_content"] as? String, !oldContent.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: old_content는 필수입니다.", isError: true)
        }
        guard let newContent = arguments["new_content"] as? String else {
            return ToolResult(toolCallId: "", content: "오류: new_content는 필수입니다.", isError: true)
        }
        guard let scope = arguments["scope"] as? String,
              scope == "workspace" || scope == "personal" else {
            return ToolResult(toolCallId: "", content: "오류: scope는 'workspace' 또는 'personal'이어야 합니다.", isError: true)
        }

        if scope == "workspace" {
            guard let existing = contextService.loadWorkspaceMemory(workspaceId: sessionContext.workspaceId) else {
                return ToolResult(toolCallId: "", content: "오류: 워크스페이스 메모리가 비어 있습니다.", isError: true)
            }
            guard existing.contains(oldContent) else {
                return ToolResult(toolCallId: "", content: "오류: 워크스페이스 메모리에서 해당 내용을 찾을 수 없습니다.", isError: true)
            }
            let updated = existing.replacingOccurrences(of: oldContent, with: newContent)
            contextService.saveWorkspaceMemory(workspaceId: sessionContext.workspaceId, content: updated)
            Log.tool.info("Updated workspace memory")
            return ToolResult(toolCallId: "", content: "워크스페이스 메모리를 수정했습니다.")
        } else {
            guard let userId = sessionContext.currentUserId else {
                return ToolResult(toolCallId: "", content: "오류: 현재 사용자가 설정되지 않았습니다. set_current_user를 먼저 사용해주세요.", isError: true)
            }
            guard let existing = contextService.loadUserMemory(userId: userId) else {
                return ToolResult(toolCallId: "", content: "오류: 개인 메모리가 비어 있습니다.", isError: true)
            }
            guard existing.contains(oldContent) else {
                return ToolResult(toolCallId: "", content: "오류: 개인 메모리에서 해당 내용을 찾을 수 없습니다.", isError: true)
            }
            let updated = existing.replacingOccurrences(of: oldContent, with: newContent)
            contextService.saveUserMemory(userId: userId, content: updated)
            Log.tool.info("Updated personal memory for user: \(userId)")
            return ToolResult(toolCallId: "", content: "개인 메모리를 수정했습니다.")
        }
    }
}
