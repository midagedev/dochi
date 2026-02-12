import Foundation
import os

// MARK: - context.update_base_system_prompt

@MainActor
final class UpdateBaseSystemPromptTool: BuiltInToolProtocol {
    let name = "context.update_base_system_prompt"
    let category: ToolCategory = .sensitive
    let description = "기본 시스템 프롬프트를 수정합니다."
    let isBaseline = false

    private let contextService: ContextServiceProtocol

    init(contextService: ContextServiceProtocol) {
        self.contextService = contextService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "mode": [
                    "type": "string",
                    "enum": ["replace", "append"],
                    "description": "수정 모드: replace (전체 교체) 또는 append (뒤에 추가)"
                ],
                "content": ["type": "string", "description": "프롬프트 내용"]
            ],
            "required": ["mode", "content"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let mode = arguments["mode"] as? String,
              mode == "replace" || mode == "append" else {
            return ToolResult(toolCallId: "", content: "오류: mode는 'replace' 또는 'append'여야 합니다.", isError: true)
        }
        guard let content = arguments["content"] as? String, !content.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: content는 필수입니다.", isError: true)
        }

        let updatedPrompt: String

        switch mode {
        case "replace":
            contextService.saveBaseSystemPrompt(content)
            updatedPrompt = content
            Log.tool.info("Replaced base system prompt (\(content.count) chars)")

        case "append":
            let existing = contextService.loadBaseSystemPrompt() ?? ""
            let combined = existing.isEmpty ? content : existing + "\n" + content
            contextService.saveBaseSystemPrompt(combined)
            updatedPrompt = combined
            Log.tool.info("Appended to base system prompt (+\(content.count) chars, total \(combined.count) chars)")

        default:
            return ToolResult(toolCallId: "", content: "오류: mode는 'replace' 또는 'append'여야 합니다.", isError: true)
        }

        // Return a preview (truncate if very long)
        let maxPreviewLength = 500
        let preview: String
        if updatedPrompt.count > maxPreviewLength {
            let truncated = String(updatedPrompt.prefix(maxPreviewLength))
            preview = truncated + "\n... (\(updatedPrompt.count)자 중 \(maxPreviewLength)자 표시)"
        } else {
            preview = updatedPrompt
        }

        return ToolResult(toolCallId: "", content: "시스템 프롬프트를 \(mode == "replace" ? "교체" : "추가")했습니다.\n\n---\n\(preview)")
    }
}
