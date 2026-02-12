import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let fontSize: Double

    init(message: Message, fontSize: Double = 14.0) {
        self.message = message
        self.fontSize = fontSize
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label for non-user messages
                if message.role == .tool {
                    Label(toolLabel, systemImage: "wrench")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Content
                contentView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(backgroundColor)
                    .cornerRadius(12)
                    .foregroundStyle(foregroundColor)

                // Tool calls display (for assistant messages that include tool calls)
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls, id: \.id) { call in
                        toolCallView(call)
                    }
                }

                // Image URLs
                if let imageURLs = message.imageURLs, !imageURLs.isEmpty {
                    ForEach(imageURLs, id: \.absoluteString) { url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 300, maxHeight: 300)
                                    .cornerRadius(8)
                            case .failure:
                                Label("이미지 로드 실패", systemImage: "photo.badge.exclamationmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .empty:
                                ProgressView()
                                    .frame(width: 100, height: 100)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }

                // Timestamp
                Text(relativeTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if message.content.isEmpty && message.toolCalls != nil {
            // Assistant message with only tool calls, no text content
            EmptyView()
                .frame(width: 0, height: 0)
        } else {
            Text(renderedContent)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
        }
    }

    private var renderedContent: AttributedString {
        // Try markdown rendering, fall back to plain text
        if let attributed = try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(message.content)
    }

    // MARK: - Tool Call Display

    private func toolCallView(_ call: CodableToolCall) -> some View {
        DisclosureGroup {
            Text(call.argumentsJSON)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        } label: {
            Label(call.name, systemImage: "function")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.orange.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private var toolLabel: String {
        if let callId = message.toolCallId {
            return callId
        }
        return "도구 결과"
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: message.timestamp, relativeTo: Date())
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: .blue.opacity(0.8)
        case .assistant: .secondary.opacity(0.12)
        case .system: .orange.opacity(0.12)
        case .tool: .green.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}
