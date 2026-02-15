import SwiftUI

/// 메뉴바 팝업 전체 SwiftUI 뷰 (H-1)
/// 헤더 + 대화 영역 + 입력바 + 푸터
struct MenuBarPopoverView: View {
    @Bindable var viewModel: DochiViewModel
    var onClose: () -> Void
    var onOpenMainApp: () -> Void

    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    // MARK: - Computed

    /// 최근 메시지 10개 (user + assistant만)
    private var recentMessages: [Message] {
        let messages = viewModel.currentConversation?.messages
            .filter { $0.role == .user || $0.role == .assistant } ?? []
        return Array(messages.suffix(10))
    }

    private var isProcessing: Bool {
        viewModel.interactionState == .processing
    }

    private var currentModelName: String {
        viewModel.settings.llmModel
    }

    private var currentAgentName: String {
        viewModel.settings.activeAgentName
    }

    private var currentWorkspaceName: String {
        let wsId = viewModel.sessionContext.workspaceId
        if wsId == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
            return "기본"
        }
        return String(wsId.uuidString.prefix(8))
    }

    // MARK: - Suggestion Chips

    private let suggestionChips = [
        "오늘 할 일 정리",
        "간단한 질문하기",
        "일정 확인"
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            conversationArea
            Divider()
            inputBarView
            Divider()
            footerView
        }
        .frame(width: 380, height: 480)
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Header (36pt)

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(currentAgentName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(currentWorkspaceName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("닫기 (Esc)")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    // MARK: - Conversation Area

    @ViewBuilder
    private var conversationArea: some View {
        if recentMessages.isEmpty && !isProcessing {
            emptyStateView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(recentMessages) { message in
                            compactBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming text
                        if isProcessing && !viewModel.streamingText.isEmpty {
                            streamingBubble
                                .id("streaming")
                        } else if isProcessing {
                            processingIndicator
                                .id("processing")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.streamingText) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        if isProcessing {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: recentMessages.count) { _, _ in
                    if let lastId = recentMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "bubble.left.fill")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)

            Text("무엇이든 물어보세요")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            // Suggestion chips
            VStack(spacing: 6) {
                ForEach(suggestionChips, id: \.self) { chip in
                    Button {
                        inputText = chip
                        sendMessage()
                    } label: {
                        Text(chip)
                            .font(.system(size: 11))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Compact Bubble

    private func compactBubble(message: Message) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if message.role == .assistant {
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            Text(message.content)
                .font(.callout)
                .foregroundStyle(message.role == .user ? .primary : .primary)
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(message.role == .user
                      ? Color.accentColor.opacity(0.08)
                      : Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Streaming Bubble

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 9))
                .foregroundStyle(.blue)
                .padding(.top, 3)

            Text(viewModel.streamingText)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.06))
        )
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("생각하는 중...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Input Bar (44pt)

    private var inputBarView: some View {
        HStack(spacing: 8) {
            TextField("메시지 입력...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...3)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            if isProcessing {
                Button {
                    viewModel.cancelRequest()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("중지")
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("전송 (Enter)")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }

    // MARK: - Footer (30pt)

    private var footerView: some View {
        HStack(spacing: 8) {
            Text(currentModelName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                viewModel.newConversation()
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("새 대화 (Cmd+N)")

            Button {
                onOpenMainApp()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("메인 앱 열기 (Cmd+O)")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        viewModel.inputText = text
        inputText = ""
        viewModel.sendMessage()
    }
}
