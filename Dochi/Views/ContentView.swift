import SwiftUI

/// The single main window: a VRM avatar on top, the conversation transcript in
/// the middle, and a voice/text input bar at the bottom. Everything the user
/// says is transcribed locally and sent to Hermes; replies stream back as text
/// (shown here) and speech (spoken by the avatar).
struct ContentView: View {
    @Bindable var viewModel: DochiViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            avatarSection
            Divider()
            transcript
            Divider()
            inputBar
        }
        .frame(minWidth: 420, minHeight: 600)
        .alert("오류", isPresented: errorBinding) {
            Button("확인", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("도치")
                .font(.headline)
            connectionBadge
            Spacer()
            Button {
                viewModel.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("새 대화")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var connectionBadge: some View {
        let (text, color): (String, Color) = {
            switch viewModel.hermesConnection {
            case .connected(let persona): return (persona.map { "Hermes · \($0)" } ?? "Hermes 연결됨", .green)
            case .connecting: return ("연결 중…", .orange)
            case .disconnected: return ("연결 끊김", .secondary)
            case .failed: return ("연결 실패", .red)
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .help("Hermes 백엔드(dochi-hermes-bridge) 연결 상태")
    }

    // MARK: Avatar

    @ViewBuilder
    private var avatarSection: some View {
        if viewModel.settings.avatarEnabled {
            if #available(macOS 15.0, *) {
                AvatarView(
                    interactionState: viewModel.interactionState,
                    modelName: viewModel.settings.avatarModelName
                )
                .frame(height: 240)
            } else {
                stateOrb.frame(height: 240)
            }
        } else {
            stateOrb.frame(height: 160)
        }
    }

    /// Fallback "presence" indicator when no avatar is shown.
    private var stateOrb: some View {
        let color: Color = {
            switch viewModel.interactionState {
            case .idle: return .secondary
            case .listening: return .blue
            case .processing: return .orange
            case .speaking: return .green
            }
        }()
        return VStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.25))
                .overlay(Circle().stroke(color, lineWidth: 2))
                .frame(width: 96, height: 96)
                .overlay(Image(systemName: stateIcon).font(.system(size: 34)).foregroundStyle(color))
            Text(stateLabel).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var stateIcon: String {
        switch viewModel.interactionState {
        case .idle: return "moon.zzz"
        case .listening: return "mic.fill"
        case .processing: return "ellipsis"
        case .speaking: return "waveform"
        }
    }

    private var stateLabel: String {
        switch viewModel.interactionState {
        case .idle: return "대기 중"
        case .listening: return "듣는 중…"
        case .processing: return viewModel.currentToolName.map { "도구 실행: \($0)" } ?? "생각 중…"
        case .speaking: return "말하는 중…"
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ConversationView(
            messages: viewModel.messages,
            streamingText: viewModel.streamingText,
            currentToolName: viewModel.currentToolName,
            processingSubState: viewModel.processingSubState,
            fontSize: viewModel.fontSize,
            toolExecutions: viewModel.toolExecutions
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(spacing: 6) {
            if viewModel.interactionState == .listening, !viewModel.partialTranscript.isEmpty {
                Text(viewModel.partialTranscript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                micButton
                TextField("메시지를 입력하세요…", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { viewModel.sendMessage() }
                if viewModel.interactionState == .processing {
                    Button(role: .destructive) { viewModel.cancelRequest() } label: {
                        Image(systemName: "stop.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("중단")
                } else {
                    Button { viewModel.sendMessage() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var micButton: some View {
        switch viewModel.interactionState {
        case .listening:
            Button { viewModel.stopListening() } label: {
                Image(systemName: "mic.fill").font(.title2).foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("듣기 중지")
        case .speaking:
            Button { viewModel.handleBargeIn() } label: {
                Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .help("끼어들기")
        default:
            Button { viewModel.startListening() } label: {
                Image(systemName: "mic").font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.interactionState == .processing)
            .help("음성 입력 시작")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
