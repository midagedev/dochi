import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: DochiViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            VStack(spacing: 0) {
                // Status bar
                if viewModel.interactionState == .processing {
                    StatusBarView(
                        processingSubState: viewModel.processingSubState,
                        currentToolName: viewModel.currentToolName
                    )
                }

                // Error banner
                if let error = viewModel.errorMessage {
                    ErrorBannerView(message: error) {
                        viewModel.errorMessage = nil
                    }
                }

                // Conversation area
                ConversationView(
                    messages: viewModel.currentConversation?.messages ?? [],
                    streamingText: viewModel.streamingText,
                    currentToolName: viewModel.currentToolName,
                    processingSubState: viewModel.processingSubState,
                    fontSize: viewModel.settings.chatFontSize
                )

                Divider()

                // Input area
                InputBarView(viewModel: viewModel)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            viewModel.loadConversations()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var viewModel: DochiViewModel

    var body: some View {
        List(selection: Binding(
            get: { viewModel.currentConversation?.id },
            set: { id in
                if let id { viewModel.selectConversation(id: id) }
            }
        )) {
            ForEach(viewModel.conversations) { conversation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(conversation.updatedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .tag(conversation.id)
                .contextMenu {
                    Button(role: .destructive) {
                        viewModel.deleteConversation(id: conversation.id)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.newConversation()
                } label: {
                    Label("새 대화", systemImage: "plus")
                }
                .help("새 대화")
            }
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    let processingSubState: ProcessingSubState?
    let currentToolName: String?

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var statusText: String {
        switch processingSubState {
        case .streaming:
            return "응답 생성 중..."
        case .toolCalling:
            if let name = currentToolName {
                return "도구 실행 중: \(name)"
            }
            return "도구 실행 중..."
        case .toolError:
            return "도구 오류 — 재시도 중..."
        case .complete:
            return "완료"
        case nil:
            return "처리 중..."
        }
    }
}

// MARK: - Error Banner

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Input Bar

struct InputBarView: View {
    @Bindable var viewModel: DochiViewModel

    var body: some View {
        HStack(spacing: 8) {
            TextField("메시지를 입력하세요...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(8)
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        viewModel.sendMessage()
                    }
                }

            if viewModel.interactionState == .processing {
                Button {
                    viewModel.cancelRequest()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("취소")
            } else {
                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSend ? Color.accentColor : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("전송")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
