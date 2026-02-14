import AppKit
import Foundation

// MARK: - Read Clipboard

@MainActor
final class ClipboardReadTool: BuiltInToolProtocol {
    let name = "clipboard.read"
    let category: ToolCategory = .safe
    let description = "클립보드(복사된 텍스트)를 읽어옵니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [:] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return ToolResult(toolCallId: "", content: "클립보드가 비어있습니다.")
        }

        let truncated = text.count > 5000 ? String(text.prefix(5000)) + "\n…(잘림)" : text
        return ToolResult(toolCallId: "", content: "클립보드 내용:\n\(truncated)")
    }
}

// MARK: - Write Clipboard

@MainActor
final class ClipboardWriteTool: BuiltInToolProtocol {
    let name = "clipboard.write"
    let category: ToolCategory = .sensitive
    let description = "텍스트를 클립보드에 복사합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "text": ["type": "string", "description": "클립보드에 복사할 텍스트"],
            ],
            "required": ["text"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let text = arguments["text"] as? String, !text.isEmpty else {
            return ToolResult(toolCallId: "", content: "text 파라미터가 필요합니다.", isError: true)
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return ToolResult(toolCallId: "", content: "클립보드에 복사했습니다. (\(text.count)자)")
    }
}
