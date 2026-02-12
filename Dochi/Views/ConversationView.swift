import SwiftUI

struct ConversationView: View {
    let messages: [Message]
    let streamingText: String
    let currentToolName: String?
    let processingSubState: ProcessingSubState?
    let fontSize: Double

    init(
        messages: [Message],
        streamingText: String,
        currentToolName: String? = nil,
        processingSubState: ProcessingSubState? = nil,
        fontSize: Double = 14.0
    ) {
        self.messages = messages
        self.streamingText = streamingText
        self.currentToolName = currentToolName
        self.processingSubState = processingSubState
        self.fontSize = fontSize
    }

    var body: some View {
        if visibleMessages.isEmpty && streamingText.isEmpty {
            emptyState
        } else {
            messageList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("대화를 시작해보세요")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleMessages) { message in
                        MessageBubbleView(message: message, fontSize: fontSize)
                            .id(message.id)
                    }

                    // Streaming text as temporary assistant bubble
                    if !streamingText.isEmpty {
                        let streamMsg = Message(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                            role: .assistant,
                            content: streamingText
                        )
                        MessageBubbleView(message: streamMsg, fontSize: fontSize)
                            .id("streaming")
                    }

                    // Tool progress indicator
                    if processingSubState == .toolCalling, let toolName = currentToolName {
                        toolProgressView(toolName)
                            .id("tool-progress")
                    }

                    // Scroll anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: streamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // MARK: - Tool Progress

    private func toolProgressView(_ toolName: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("\(toolName) 실행 중...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.green.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    /// Filter out system messages from display.
    private var visibleMessages: [Message] {
        messages.filter { $0.role != .system }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if !streamingText.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = visibleMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
