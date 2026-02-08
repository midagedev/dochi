import Foundation
import os

/// 기억 관리 도구 (save_memory, update_memory)
@MainActor
final class MemoryTool: BuiltInTool {
    var contextService: ContextServiceProtocol?
    var currentUserId: UUID?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:save_memory",
                name: "save_memory",
                description: "Save a new memory about the user or family. Use scope 'family' for shared family information, 'personal' for individual user information.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "content": [
                            "type": "string",
                            "description": "The memory content to save"
                        ],
                        "scope": [
                            "type": "string",
                            "enum": ["family", "personal"],
                            "description": "Where to save: 'family' for shared family memory, 'personal' for current user's personal memory"
                        ]
                    ],
                    "required": ["content", "scope"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:update_memory",
                name: "update_memory",
                description: "Update or delete an existing memory. Find the line containing old_content and replace it with new_content. If new_content is empty, the line is deleted.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "old_content": [
                            "type": "string",
                            "description": "Text to find in existing memory (partial match)"
                        ],
                        "new_content": [
                            "type": "string",
                            "description": "Replacement text. Empty string to delete the line."
                        ],
                        "scope": [
                            "type": "string",
                            "enum": ["family", "personal"],
                            "description": "Which memory to update: 'family' or 'personal'"
                        ]
                    ],
                    "required": ["old_content", "new_content", "scope"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let contextService else {
            throw BuiltInToolError.invalidArguments("ContextService not configured")
        }

        switch name {
        case "save_memory":
            return try saveMemory(arguments: arguments, contextService: contextService)
        case "update_memory":
            return try updateMemory(arguments: arguments, contextService: contextService)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    private func saveMemory(arguments: [String: Any], contextService: ContextServiceProtocol) throws -> MCPToolResult {
        guard let content = arguments["content"] as? String, !content.isEmpty else {
            throw BuiltInToolError.invalidArguments("content is required")
        }
        guard let scope = arguments["scope"] as? String else {
            throw BuiltInToolError.invalidArguments("scope is required")
        }

        let entry = "- \(content)"

        switch scope {
        case "family":
            contextService.appendFamilyMemory(entry)
            Log.tool.info("가족 기억 저장: \(content.prefix(50))")
            return MCPToolResult(content: "가족 기억에 저장했습니다: \(content)", isError: false)

        case "personal":
            guard let userId = currentUserId else {
                return MCPToolResult(content: "현재 사용자가 식별되지 않아 개인 기억을 저장할 수 없습니다. set_current_user를 먼저 호출해주세요.", isError: true)
            }
            contextService.appendUserMemory(userId: userId, content: entry)
            Log.tool.info("개인 기억 저장 (user: \(userId)): \(content.prefix(50))")
            return MCPToolResult(content: "개인 기억에 저장했습니다: \(content)", isError: false)

        default:
            throw BuiltInToolError.invalidArguments("scope must be 'family' or 'personal'")
        }
    }

    private func updateMemory(arguments: [String: Any], contextService: ContextServiceProtocol) throws -> MCPToolResult {
        guard let oldContent = arguments["old_content"] as? String, !oldContent.isEmpty else {
            throw BuiltInToolError.invalidArguments("old_content is required")
        }
        guard let newContent = arguments["new_content"] as? String else {
            throw BuiltInToolError.invalidArguments("new_content is required")
        }
        guard let scope = arguments["scope"] as? String else {
            throw BuiltInToolError.invalidArguments("scope is required")
        }

        let isDelete = newContent.isEmpty

        switch scope {
        case "family":
            let memory = contextService.loadFamilyMemory()
            guard let updated = replaceLineContaining(oldContent, with: newContent, in: memory) else {
                return MCPToolResult(content: "가족 기억에서 '\(oldContent)'를 찾을 수 없습니다.", isError: true)
            }
            contextService.saveFamilyMemory(updated)
            Log.tool.info("가족 기억 \(isDelete ? "삭제" : "수정"): \(oldContent.prefix(50))")
            return MCPToolResult(content: isDelete ? "가족 기억에서 삭제했습니다." : "가족 기억을 수정했습니다.", isError: false)

        case "personal":
            guard let userId = currentUserId else {
                return MCPToolResult(content: "현재 사용자가 식별되지 않아 개인 기억을 수정할 수 없습니다.", isError: true)
            }
            let memory = contextService.loadUserMemory(userId: userId)
            guard let updated = replaceLineContaining(oldContent, with: newContent, in: memory) else {
                return MCPToolResult(content: "개인 기억에서 '\(oldContent)'를 찾을 수 없습니다.", isError: true)
            }
            contextService.saveUserMemory(userId: userId, content: updated)
            Log.tool.info("개인 기억 \(isDelete ? "삭제" : "수정") (user: \(userId)): \(oldContent.prefix(50))")
            return MCPToolResult(content: isDelete ? "개인 기억에서 삭제했습니다." : "개인 기억을 수정했습니다.", isError: false)

        default:
            throw BuiltInToolError.invalidArguments("scope must be 'family' or 'personal'")
        }
    }

    /// 텍스트에서 oldContent를 포함하는 줄을 찾아 교체 (newContent가 빈 문자열이면 삭제)
    private func replaceLineContaining(_ oldContent: String, with newContent: String, in text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(oldContent) }) else {
            return nil
        }

        if newContent.isEmpty {
            lines.remove(at: index)
        } else {
            lines[index] = "- \(newContent)"
        }

        return lines.joined(separator: "\n")
    }
}
