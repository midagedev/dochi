import AgentRuntimeCore
import SwiftUI

/// The single main window: a VRM avatar on top, the conversation transcript in
/// the middle, and a voice/text input bar at the bottom. Everything the user
/// says is transcribed locally and sent to the selected agent backend; replies
/// stream back as text (shown here) and speech (spoken by the avatar).
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
        .confirmationDialog(
            "도구 실행 승인",
            isPresented: toolApprovalBinding,
            titleVisibility: .visible
        ) {
            Button("한 번 허용") {
                viewModel.resolvePendingToolApproval(.allowOnce)
            }
            if let request = viewModel.pendingToolApproval,
               allowsSessionApproval(request) {
                Button("이번 대화에서 허용") {
                    viewModel.resolvePendingToolApproval(.allowForSession)
                }
            }
            Button("거부", role: .cancel) {
                viewModel.resolvePendingToolApproval(.deny(reason: "사용자가 거부했습니다."))
            }
        } message: {
            if let request = viewModel.pendingToolApproval {
                Text(toolApprovalMessage(for: request))
                    .privacySensitive()
            }
        }
    }

    // MARK: Header

    private var toolApprovalBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingToolApproval != nil },
            set: { isPresented in
                if !isPresented, viewModel.pendingToolApproval != nil {
                    viewModel.resolvePendingToolApproval(.deny(reason: "승인 창을 닫았습니다."))
                }
            }
        )
    }

    private func allowsSessionApproval(_ request: AgentToolApprovalRequest) -> Bool {
        request.call.name != "memory.persist_sensitive"
            && request.descriptor.risk != .restricted
            && request.descriptor.sideEffect != .nonIdempotent
    }

    private func toolApprovalMessage(for request: AgentToolApprovalRequest) -> String {
        var lines = [
            approvalToolName(request.call.name),
            request.descriptor.description,
        ]

        switch request.descriptor.risk {
        case .safe:
            break
        case .sensitive:
            lines.append("민감한 데이터에 접근하거나 변경할 수 있습니다.")
        case .restricted:
            lines.append("제한된 기능입니다. 실행 결과를 되돌리기 어려울 수 있습니다.")
        }

        switch request.descriptor.sideEffect {
        case .none:
            break
        case .idempotent:
            lines.append("같은 요청을 다시 실행해도 결과가 중복되지 않는 변경입니다.")
        case .nonIdempotent:
            lines.append("외부 상태를 변경하며 반복 실행 시 결과가 달라질 수 있습니다.")
        }

        if request.call.name == "memory.persist_sensitive" {
            let scope = request.call.arguments["scope"]?.stringValue ?? "알 수 없음"
            let kind = request.call.arguments["kind"]?.stringValue ?? "알 수 없음"
            let sensitivity = request.call.arguments["sensitivity"]?.stringValue ?? "알 수 없음"
            lines.append("기억 범위: \(scope) · 종류: \(kind) · 민감도: \(sensitivity)")
            if let content = request.call.arguments["content"]?.stringValue {
                let previewLimit = 400
                let preview = content.count > previewLimit
                    ? String(content.prefix(previewLimit)) + "…"
                    : content
                lines.append("저장할 내용: \(preview)")
            }
            lines.append("위 내용은 이 승인 화면에만 표시되며 감사 로그에는 기록되지 않습니다.")
        }

        if !request.reason.isEmpty {
            lines.append("승인 사유: \(request.reason)")
        }
        return lines.joined(separator: "\n")
    }

    private func approvalToolName(_ name: String) -> String {
        switch name {
        case "memory.persist_sensitive": "민감한 장기 기억 저장"
        case "memory.archive": "장기 기억 보관 처리"
        default: "도구: \(name)"
        }
    }

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
            .disabled(viewModel.interactionState != .idle || viewModel.pendingToolApproval != nil)
            .help("새 대화")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var connectionBadge: some View {
        let (text, color): (String, Color) = {
            switch viewModel.agentConnection {
            case .connected(let name): return (name.map { "\($0) 연결됨" } ?? "에이전트 연결됨", .green)
            case .connecting: return ("연결 중…", .orange)
            case .disconnected: return ("연결 끊김", .secondary)
            case .failed: return ("연결 실패", .red)
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .help("선택한 에이전트 백엔드 연결 상태")
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
