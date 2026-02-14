import Foundation
import os
import AppKit

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case json
    case pdf
    case plainText

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .pdf: return "PDF"
        case .plainText: return "텍스트"
        }
    }

    var icon: String {
        switch self {
        case .markdown: return "doc.text"
        case .json: return "doc.badge.gearshape"
        case .pdf: return "doc.richtext"
        case .plainText: return "doc.plaintext"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .pdf: return "pdf"
        case .plainText: return "txt"
        }
    }
}

struct ExportOptions: Sendable {
    var includeSystemMessages: Bool = false
    var includeToolMessages: Bool = true
    var includeMetadata: Bool = false

    static let `default` = ExportOptions()
}

struct ConversationExporter {

    // MARK: - Filtered Messages

    private static func filteredMessages(_ conversation: Conversation, options: ExportOptions) -> [Message] {
        conversation.messages.filter { message in
            switch message.role {
            case .system:
                return options.includeSystemMessages
            case .tool:
                return options.includeToolMessages
            case .user, .assistant:
                return true
            }
        }
    }

    // MARK: - Markdown Export

    static func toMarkdown(_ conversation: Conversation, options: ExportOptions = .default) -> String {
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

        let messages = filteredMessages(conversation, options: options)

        for message in messages {
            let roleLabel = roleDisplayName(message.role)
            let timestamp = formatter.string(from: message.timestamp)

            lines.append("### \(roleLabel) (\(timestamp))")
            lines.append("")

            if !message.content.isEmpty {
                lines.append(message.content)
                lines.append("")
            }

            // Tool calls
            if options.includeToolMessages, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
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

            // Metadata
            if options.includeMetadata, let metadata = message.metadata {
                lines.append("> *\(metadata.model) | \(metadata.latencyDisplay)*")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Export

    static func toJSON(_ conversation: Conversation, options: ExportOptions = .default) throws -> Data {
        let filtered = filterConversationForExport(conversation, options: options)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(filtered)
    }

    // MARK: - Plain Text Export

    static func toPlainText(_ conversation: Conversation, options: ExportOptions = .default) -> String {
        var lines: [String] = []

        // Header
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")

        lines.append(conversation.title)
        lines.append(String(repeating: "=", count: conversation.title.count))
        lines.append("생성: \(formatter.string(from: conversation.createdAt))")
        lines.append("수정: \(formatter.string(from: conversation.updatedAt))")
        if conversation.source == .telegram {
            lines.append("출처: Telegram")
        }
        lines.append("")

        let messages = filteredMessages(conversation, options: options)

        for message in messages {
            let roleLabel = roleDisplayName(message.role)
            let timestamp = formatter.string(from: message.timestamp)

            lines.append("[\(roleLabel)] (\(timestamp))")

            if !message.content.isEmpty {
                lines.append(message.content)
            }

            if options.includeToolMessages, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                for call in toolCalls {
                    lines.append("  [도구 호출: \(call.name)]")
                    if !call.argumentsJSON.isEmpty, call.argumentsJSON != "{}" {
                        lines.append("  \(call.argumentsJSON)")
                    }
                }
            }

            if options.includeMetadata, let metadata = message.metadata {
                lines.append("  (\(metadata.model) | \(metadata.latencyDisplay))")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - PDF Export

    static func toPDF(_ conversation: Conversation, options: ExportOptions = .default) -> Data? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")

        let messages = filteredMessages(conversation, options: options)

        let attributed = NSMutableAttributedString()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        attributed.append(NSAttributedString(string: "\(conversation.title)\n\n", attributes: titleAttrs))

        // Header info
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        var headerText = "생성: \(formatter.string(from: conversation.createdAt))\n"
        headerText += "수정: \(formatter.string(from: conversation.updatedAt))\n"
        if conversation.source == .telegram {
            headerText += "출처: Telegram\n"
        }
        headerText += "\n"
        attributed.append(NSAttributedString(string: headerText, attributes: headerAttrs))

        // Messages
        let roleLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let contentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        for message in messages {
            let roleLabel = roleDisplayName(message.role)
            let timestamp = formatter.string(from: message.timestamp)

            attributed.append(NSAttributedString(string: "\(roleLabel) (\(timestamp))\n", attributes: roleLabelAttrs))

            if !message.content.isEmpty {
                attributed.append(NSAttributedString(string: "\(message.content)\n", attributes: contentAttrs))
            }

            if options.includeToolMessages, let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                for call in toolCalls {
                    let toolAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                        .foregroundColor: NSColor.systemOrange
                    ]
                    attributed.append(NSAttributedString(string: "  [도구: \(call.name)]\n", attributes: toolAttrs))
                }
            }

            if options.includeMetadata, let metadata = message.metadata {
                attributed.append(NSAttributedString(string: "  \(metadata.model) | \(metadata.latencyDisplay)\n", attributes: metaAttrs))
            }

            attributed.append(NSAttributedString(string: "\n", attributes: contentAttrs))
        }

        // Render to PDF
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842) // A4
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let printableWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let printableHeight = printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: printableWidth, height: .greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)

        // Force layout
        layoutManager.ensureLayout(for: textContainer)

        let totalHeight = layoutManager.usedRect(for: textContainer).height
        let pageCount = max(1, Int(ceil(totalHeight / printableHeight)))

        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: printInfo.paperSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            let offsetY = CGFloat(page) * printableHeight

            NSGraphicsContext.saveGraphicsState()
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsContext

            // Transform: origin at top-left margin
            context.translateBy(x: printInfo.leftMargin, y: printInfo.paperSize.height - printInfo.topMargin)
            context.scaleBy(x: 1, y: -1)

            // Clip to page
            let clipRect = CGRect(x: 0, y: 0, width: printableWidth, height: printableHeight)
            context.clip(to: clipRect)

            // Offset for current page
            context.translateBy(x: 0, y: -offsetY)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }

        context.closePDF()

        return pdfData as Data
    }

    // MARK: - Export to String (for clipboard)

    static func exportToString(_ conversation: Conversation, format: ExportFormat, options: ExportOptions = .default) -> String? {
        switch format {
        case .markdown:
            return toMarkdown(conversation, options: options)
        case .plainText:
            return toPlainText(conversation, options: options)
        case .json:
            if let data = try? toJSON(conversation, options: options) {
                return String(data: data, encoding: .utf8)
            }
            return nil
        case .pdf:
            return nil // PDF cannot be represented as string
        }
    }

    // MARK: - Export to Data

    static func exportToData(_ conversation: Conversation, format: ExportFormat, options: ExportOptions = .default) -> Data? {
        switch format {
        case .markdown:
            return toMarkdown(conversation, options: options).data(using: .utf8)
        case .plainText:
            return toPlainText(conversation, options: options).data(using: .utf8)
        case .json:
            return try? toJSON(conversation, options: options)
        case .pdf:
            return toPDF(conversation, options: options)
        }
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

        return "\(dateStr)_\(safeTitle).\(format.fileExtension)"
    }

    // MARK: - Merge Multiple Conversations

    static func mergeToMarkdown(_ conversations: [Conversation], options: ExportOptions = .default) -> String {
        var lines: [String] = []
        lines.append("# 대화 모음 (\(conversations.count)개)")
        lines.append("")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")

        lines.append("- 내보내기 시각: \(formatter.string(from: Date()))")
        lines.append("")
        lines.append("---")
        lines.append("")

        for (index, conversation) in conversations.enumerated() {
            lines.append("## \(index + 1). \(conversation.title)")
            lines.append("")
            lines.append(toMarkdown(conversation, options: options))
            lines.append("")
            if index < conversations.count - 1 {
                lines.append("---")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
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

    private static func filterConversationForExport(_ conversation: Conversation, options: ExportOptions) -> Conversation {
        let filtered = filteredMessages(conversation, options: options)
        return Conversation(
            id: conversation.id,
            title: conversation.title,
            messages: filtered,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            userId: conversation.userId,
            summary: conversation.summary,
            source: conversation.source,
            telegramChatId: conversation.telegramChatId,
            isFavorite: conversation.isFavorite,
            tags: conversation.tags,
            folderId: conversation.folderId
        )
    }
}
