import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: DochiViewModel

    @State private var showSettings = false
    @State private var showChangelog = false
    @State private var inputText = ""

    private let changelogService = ChangelogService()

    var body: some View {
        NavigationSplitView {
            SidebarView(showSettings: $showSettings)
        } detail: {
            VStack(spacing: 0) {
                toolbarArea
                Divider()
                ConversationView()
                Divider()
                inputArea
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogView(changelogService: changelogService, showFullChangelog: false)
        }
        .onAppear {
            viewModel.connectOnLaunch()
            checkForNewVersion()
        }
    }

    private func checkForNewVersion() {
        if changelogService.hasNewVersion {
            // 약간 딜레이 후 표시 (앱 로딩 완료 후)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showChangelog = true
            }
        } else if changelogService.isFirstLaunch {
            // 첫 실행 시에는 버전만 기록
            changelogService.markCurrentVersionAsSeen()
        }
    }

    // MARK: - Toolbar

    private var toolbarArea: some View {
        HStack(spacing: 12) {
            // Connection toggle
            Button {
                viewModel.toggleConnection()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)
                    Text(connectionLabel)
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)

            // State indicator
            if viewModel.isConnected {
                if isWakeWordActive {
                    WakeWordIndicator(wakeWord: viewModel.settings.wakeWord)
                } else {
                    Text(stateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let error = currentError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            // Voice indicator
            if isResponding {
                HStack(spacing: 4) {
                    AudioBarsView()
                    Text("응답 중")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var connectionColor: Color {
        switch viewModel.supertonicService.state {
        case .unloaded: return .red
        case .loading: return .yellow
        case .ready:
            switch viewModel.state {
            case .idle: return .green
            case .listening: return .orange
            case .processing: return .blue
            case .executingTool: return .cyan
            case .speaking: return .purple
            }
        case .synthesizing: return .blue
        case .playing: return .purple
        }
    }

    private var connectionLabel: String {
        switch viewModel.supertonicService.state {
        case .unloaded: return "연결"
        case .loading: return "로딩 중..."
        case .ready, .synthesizing, .playing: return "연결됨"
        }
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle: return "대기 중"
        case .listening: return "듣는 중..."
        case .processing: return "응답 생성 중..."
        case .executingTool(let name): return "\(name) 실행 중..."
        case .speaking: return "음성 재생 중..."
        }
    }

    private var currentError: String? {
        viewModel.errorMessage ?? viewModel.llmService.error ?? viewModel.supertonicService.error
    }

    private var isWakeWordActive: Bool {
        viewModel.speechService.state == .waitingForWakeWord
    }

    private var isResponding: Bool {
        switch viewModel.state {
        case .processing, .executingTool, .speaking: return true
        case .idle, .listening: return false
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            // Push-to-talk mic button
            if viewModel.isConnected {
                Button {
                    if viewModel.state == .listening {
                        viewModel.stopListening()
                    } else {
                        viewModel.startListening()
                    }
                } label: {
                    Image(systemName: viewModel.state == .listening ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundStyle(viewModel.state == .listening ? .orange : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.state == .processing || viewModel.state == .speaking)
            }

            TextField("메시지를 입력하세요...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit { submitText() }

            if isResponding {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    submitText()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary : Color.blue
                        )
                }
                .buttonStyle(.borderless)
                .disabled(sendDisabled)
            }
        }
        .padding()
    }

    private var sendDisabled: Bool {
        let empty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let provider = viewModel.settings.llmProvider
        let hasKey = !viewModel.settings.apiKey(for: provider).isEmpty
        return empty || !hasKey || viewModel.state == .processing
    }

    private func submitText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        viewModel.sendMessage(text)
    }
}

// MARK: - Wake Word Indicator

struct WakeWordIndicator: View {
    let wakeWord: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.mint.opacity(0.25))
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
                Image(systemName: "ear")
                    .font(.caption)
                    .foregroundStyle(.mint)
            }
            Text("\"\(wakeWord)\" 대기 중")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .onDisappear { pulse = false }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Binding var showSettings: Bool
    @State private var showSystemEditor = false
    @State private var showMemoryEditor = false

    private var contextService: ContextServiceProtocol {
        viewModel.settings.contextService
    }

    var body: some View {
        List {
            Section("시스템 프롬프트") {
                Button {
                    showSystemEditor = true
                } label: {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("system.md")
                                .font(.body)
                            let system = contextService.loadSystem()
                            Text(system.isEmpty ? "설정되지 않음" : system)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Section("사용자 기억") {
                Button {
                    showMemoryEditor = true
                } label: {
                    HStack {
                        Image(systemName: "brain")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("memory.md")
                                .font(.body)
                            let memory = contextService.loadMemory()
                            Text(memory.isEmpty ? "비어 있음" : "\(memory.components(separatedBy: .newlines).filter { !$0.isEmpty }.count)개 항목")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Section("대화") {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Label("새 대화", systemImage: "plus.circle")
                }
                if !viewModel.messages.isEmpty {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(.blue)
                        Text("현재 대화")
                            .font(.body)
                        Spacer()
                        Text("\(viewModel.messages.count)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("대화 기록") {
                if viewModel.conversations.isEmpty {
                    Text("저장된 대화가 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.conversations) { conv in
                        Button {
                            viewModel.loadConversation(conv)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conv.title)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(conv.updatedAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.currentConversationId == conv.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteConversation(id: conv.id)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showSystemEditor) {
            SystemEditorView(contextService: contextService)
        }
        .sheet(isPresented: $showMemoryEditor) {
            MemoryEditorView(contextService: contextService)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showSettings = true
            } label: {
                Label("설정", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }
}
