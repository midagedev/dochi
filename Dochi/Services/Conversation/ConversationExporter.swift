import Foundation
import os

enum ExportFormat {
    case markdown
    case json
}

struct ConversationExporter {

    // MARK: - Markdown Export

    static func toMarkdown(_ conversation: Conversation) -> String {
        var lines: [String] = []

        // Header
        lines.append("# \(conversation.title)")
        lines.append("")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")

        lines.append("- 생성: \(formatter.string(from: conversation.createdAt))")
        lines.append("- 수정: \(formatter.string(from: conversation.updatedAt))")
        if conversation.source == .telegram {
            lines.append("- 출처: Telegram")
        }
        lines.append("")
        lines.append("---")
        lines.append("")

        for message in conversation.messages {
            let roleLabel = roleDisplayName(message.role)
            let timestamp = formatter.string(from: message.timestamp)

            lines.append("### \(roleLabel) (\(timestamp))")
            lines.append("")

            if !message.content.isEmpty {
                lines.append(message.content)
                lines.append("")
            }

            // Tool calls
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                for call in toolCalls {
                    lines.append("> **도구 호출**: `\(call.name)`")
                    if !call.argumentsJSON.isEmpty, call.argumentsJSON != "{}" {
                        lines.append("> ```json")
                        // Pretty-print the JSON if possible
                        if let data = call.argumentsJSON.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data),
                           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
                           let prettyStr = String(data: pretty, encoding: .utf8) {
                            for line in prettyStr.components(separatedBy: "\n") {
                                lines.append("> \(line)")
                            }
                        } else {
                            lines.append("> \(call.argumentsJSON)")
                        }
                        lines.append("> ```")
                    }
                    lines.append("")
                }
            }

            // Tool result indicator
            if let toolCallId = message.toolCallId, !toolCallId.isEmpty, message.role == .tool {
                lines.append("> **도구 결과** (ID: `\(toolCallId)`)")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Export

    static func toJSON(_ conversation: Conversation) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(conversation)
    }

    // MARK: - File Name

    static func suggestedFileName(for conversation: Conversation, format: ExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateStr = formatter.string(from: conversation.createdAt)

        // Sanitize title for filename
        let safeTitle = conversation.title
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .prefix(40)

        let ext = format == .markdown ? "md" : "json"
        return "\(dateStr)_\(safeTitle).\(ext)"
    }

    // MARK: - Helpers

    private static func roleDisplayName(_ role: MessageRole) -> String {
        switch role {
        case .system: return "시스템"
        case .user: return "사용자"
        case .assistant: return "어시스턴트"
        case .tool: return "도구"
        }
    }
}
