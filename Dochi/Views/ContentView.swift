import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: DochiViewModel

    @State private var showSettings = false
    @State private var inputText = ""

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
    }

    // MARK: - Toolbar

    private var toolbarArea: some View {
        HStack(spacing: 12) {
            // Mode toggle
            Picker("모드", selection: modeBinding) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

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

    private var modeBinding: Binding<AppMode> {
        Binding(
            get: { viewModel.settings.appMode },
            set: { viewModel.switchMode(to: $0) }
        )
    }

    private var connectionColor: Color {
        if viewModel.isTextMode {
            switch viewModel.supertonicService.state {
            case .unloaded: return .red
            case .loading: return .yellow
            case .ready:
                switch viewModel.textModeState {
                case .idle: return .green
                case .listening: return .orange
                case .processing: return .blue
                case .speaking: return .purple
                }
            case .synthesizing: return .blue
            case .playing: return .purple
            }
        } else {
            switch viewModel.realtime.state {
            case .disconnected: return .red
            case .connecting: return .yellow
            case .connected: return .green
            case .listening: return .orange
            case .responding: return .blue
            }
        }
    }

    private var connectionLabel: String {
        if viewModel.isTextMode {
            switch viewModel.supertonicService.state {
            case .unloaded: return "연결"
            case .loading: return "로딩 중..."
            case .ready, .synthesizing, .playing: return "연결됨"
            }
        } else {
            return viewModel.isConnected ? "연결됨" : "연결"
        }
    }

    private var stateLabel: String {
        if viewModel.isTextMode {
            switch viewModel.textModeState {
            case .idle: return "대기 중"
            case .listening: return "듣는 중..."
            case .processing: return "응답 생성 중..."
            case .speaking: return "음성 재생 중..."
            }
        } else {
            switch viewModel.realtime.state {
            case .connected: return "대기 중 — 말하면 자동 인식"
            case .listening: return "듣는 중..."
            case .responding: return "응답 생성 중..."
            default: return ""
            }
        }
    }

    private var currentError: String? {
        viewModel.errorMessage ?? (viewModel.isRealtimeMode ? viewModel.realtime.error : viewModel.llmService.error ?? viewModel.supertonicService.error)
    }

    private var isWakeWordActive: Bool {
        viewModel.isTextMode && viewModel.speechService.state == .waitingForWakeWord
    }

    private var isResponding: Bool {
        if viewModel.isTextMode {
            return viewModel.textModeState == .processing || viewModel.textModeState == .speaking
        } else {
            return viewModel.realtime.state == .responding
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            // Text mode: Push-to-talk mic button
            if viewModel.isTextMode && viewModel.isConnected {
                Button {
                    if viewModel.textModeState == .listening {
                        viewModel.stopTextModeListening()
                    } else {
                        viewModel.startTextModeListening()
                    }
                } label: {
                    Image(systemName: viewModel.textModeState == .listening ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundStyle(viewModel.textModeState == .listening ? .orange : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.textModeState == .processing || viewModel.textModeState == .speaking)
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
        if viewModel.isTextMode {
            // 텍스트 모드: API 키만 있으면 전송 가능 (Supertonic 미로드 시 텍스트만 표시)
            let provider = viewModel.settings.llmProvider
            let hasKey = !viewModel.settings.apiKey(for: provider).isEmpty
            return empty || !hasKey || viewModel.textModeState == .processing
        } else {
            return empty || !viewModel.isConnected
        }
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
    @State private var showInstructionEditor = false
    @State private var showContextEditor = false

    var body: some View {
        List {
            // MARK: - 초기 프롬프트
            Section("초기 프롬프트") {
                Button {
                    showInstructionEditor = true
                } label: {
                    HStack {
                        Image(systemName: "text.quote")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("인스트럭션")
                                .font(.body)
                            Text(viewModel.settings.instructions.isEmpty
                                 ? "설정되지 않음"
                                 : viewModel.settings.instructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // MARK: - 장기 기억
            Section("장기 기억") {
                Button {
                    showContextEditor = true
                } label: {
                    HStack {
                        Image(systemName: "brain")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("context.md")
                                .font(.body)
                            let context = ContextService.load()
                            Text(context.isEmpty ? "비어 있음" : "\(context.components(separatedBy: .newlines).filter { !$0.isEmpty }.count)개 항목")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // MARK: - 대화
            Section("대화") {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Label("새 대화", systemImage: "plus.circle")
                }
                if !viewModel.messages.isEmpty {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(.secondary)
                        Text("현재 대화")
                            .font(.body)
                        Spacer()
                        Text("\(viewModel.messages.count)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showInstructionEditor) {
            InstructionEditorView(instructions: $viewModel.settings.instructions)
        }
        .sheet(isPresented: $showContextEditor) {
            ContextEditorView()
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
