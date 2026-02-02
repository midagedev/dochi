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
                Text(stateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Binding var showSettings: Bool

    var body: some View {
        List {
            Section("대화") {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Label("새 대화", systemImage: "plus.circle")
                }
            }

            Section("컨텍스트") {
                ContextView()
            }
        }
        .listStyle(.sidebar)
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
