import AgentRuntimeCore
import SwiftUI
import UIKit

struct MobileChatView: View {
    private enum AccessibilityTarget: Hashable {
        case profileSettings
        case settings
        case composer
    }

    let controller: MobileAgentController
    let preferences: MobileAgentPreferences

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var isShowingSettings = false
    @State private var settingsReturnFocus: AccessibilityTarget = .settings
    @State private var isConfirmingNewConversation = false
    @State private var isSpeechDraftActive = false
    @State private var speechRecognition = MobileSpeechRecognitionService()
    @State private var speechOutput = MobileSpeechOutputService()
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityTarget?

    var body: some View {
        NavigationStack {
            ZStack {
                background
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if controller.messages.isEmpty, controller.streamingText.isEmpty {
                                emptyConversation
                            } else {
                                conversation(proxy: proxy)
                            }
                        }
                        .frame(maxWidth: 760)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: controller.messages.last?.id) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: controller.streamingText) { _, _ in
                        scrollToBottom(proxy)
                    }
                }
            }
            .navigationTitle("도치")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { headerToolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
        .tint(.indigo)
        .sheet(isPresented: $isShowingSettings, onDismiss: restoreSettingsFocus) {
            MobileSettingsView(controller: controller, preferences: preferences)
        }
        .confirmationDialog(
            "새 대화를 시작할까요?",
            isPresented: $isConfirmingNewConversation,
            titleVisibility: .visible
        ) {
            Button("새 대화 시작", role: .destructive) {
                speechOutput.stop()
                speechRecognition.stopListening(cancelRecognition: true)
                isSpeechDraftActive = false
                draft = ""
                controller.newConversation()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 대화는 기기에서 비워지며, 새로운 기억 범위로 대화를 시작합니다.")
        }
        .sheet(item: approvalPresentation) { request in
            MobileToolApprovalSheet(request: request, controller: controller)
        }
        .alert("문제가 생겼어요", isPresented: errorPresentation) {
            Button("확인") { controller.dismissError() }
            Button("설정 열기") {
                controller.dismissError()
                presentSettings(returnFocusTo: .settings)
            }
        } message: {
            Text(controller.errorMessage ?? "설정을 확인한 뒤 다시 시도해 주세요.")
        }
        .onAppear {
            controller.onAssistantReply = { text in
                guard preferences.speakReplies else { return }
                speechOutput.speak(text)
            }
        }
        .onDisappear {
            controller.onAssistantReply = nil
            speechRecognition.stopListening(cancelRecognition: true)
            speechOutput.stop()
        }
        .onChange(of: speechRecognition.transcript) { _, newValue in
            guard isSpeechDraftActive else { return }
            draft = newValue
        }
        .onChange(of: controller.completionFeedbackCounter) { _, _ in
            guard preferences.hapticsEnabled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement, argument: "도치의 답변이 도착했습니다.")
        }
        .onChange(of: controller.pendingToolApproval?.id) { _, newValue in
            guard newValue != nil else { return }
            UIAccessibility.post(notification: .announcement, argument: "도구 사용 승인이 필요합니다.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            speechRecognition.stopListening(cancelRecognition: true)
            speechOutput.stop()
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: controller.phase)
    }

    private var background: some View {
        Group {
            if reduceTransparency {
                Color(uiColor: .systemGroupedBackground)
            } else {
                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.10),
                        Color(uiColor: .systemGroupedBackground),
                        Color.orange.opacity(0.06),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var headerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                presentSettings(returnFocusTo: .profileSettings)
            } label: {
                HStack(spacing: 9) {
                    Image(preferences.selectedAvatar.assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("도치")
                            .font(.headline)
                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(contrast == .increased ? .primary : .secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityLabel("도치 프로필 설정")
            .accessibilityValue(statusText)
            .accessibilityHint("아바타와 에이전트 설정을 엽니다.")
            .accessibilityInputLabels(["프로필 설정", "도치 프로필"])
            .accessibilityFocused($accessibilityFocus, equals: .profileSettings)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                isConfirmingNewConversation = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("새 대화")
            .accessibilityHint("현재 대화를 비우고 새 대화를 시작합니다.")
            .accessibilityInputLabels(["새 대화", "대화 새로 시작"])

            Button {
                presentSettings(returnFocusTo: .settings)
            } label: {
                Image(systemName: "gearshape")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("에이전트 설정")
            .accessibilityIdentifier("mobile-agent-settings-button")
            .accessibilityInputLabels(["에이전트 설정", "톱니바퀴 설정"])
            .accessibilityFocused($accessibilityFocus, equals: .settings)
        }
    }

    private var statusText: String {
        if let tool = controller.activeToolName {
            return "\(MobileToolPresentation.friendlyName(tool)) 사용 중"
        }
        return controller.phase.statusText
    }

    private var emptyConversation: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 28)
            Image(preferences.selectedAvatar.assetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 210, maxHeight: 210)
                .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                .shadow(color: .indigo.opacity(0.16), radius: 22, y: 10)
                .accessibilityLabel("선택한 도치 아바타, \(preferences.selectedAvatar.displayName)")
                .accessibilityIdentifier("mobile-empty-avatar")

            VStack(spacing: 7) {
                Text("무슨 이야기를 해볼까요?")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("일상적인 질문부터 기억해 둘 일까지 편하게 말해 주세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { suggestionButtons }
                VStack(spacing: 10) { suggestionButtons }
            }
            Spacer(minLength: 20)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, minHeight: 460)
    }

    @ViewBuilder
    private var suggestionButtons: some View {
        suggestion("오늘 할 일을 정리해줘", icon: "checklist")
        suggestion("이걸 기억해줘", icon: "brain.head.profile")
    }

    private func suggestion(_ text: String, icon: String) -> some View {
        Button {
            draft = text
            accessibilityFocus = .composer
        } label: {
            Label(text, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("메시지 입력란에 넣습니다.")
    }

    @ViewBuilder
    private func conversation(proxy: ScrollViewProxy) -> some View {
        ForEach(controller.messages) { message in
            MobileMessageBubble(
                message: message,
                avatar: preferences.selectedAvatar,
                reduceTransparency: reduceTransparency,
                increasedContrast: contrast == .increased
            )
            .id(message.id)
        }

        if !controller.streamingText.isEmpty {
            MobileStreamingBubble(
                text: controller.streamingText,
                avatar: preferences.selectedAvatar,
                reduceMotion: reduceMotion
            )
            .id("streaming-reply")
        }

        if controller.phase == .thinking || controller.phase == .usingTool {
            MobileActivityPill(
                text: statusText,
                systemImage: controller.phase == .usingTool ? "wrench.and.screwdriver" : "ellipsis.bubble",
                reduceTransparency: reduceTransparency
            )
            .id("agent-activity")
        }

        Color.clear
            .frame(height: 1)
            .id("conversation-bottom")
            .accessibilityHidden(true)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let speechError = speechRecognition.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label {
                        Text(speechError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 4)
                    Button("닫기") { speechRecognition.clearError() }
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("음성 인식 오류 닫기")
                        .accessibilityInputLabels(["음성 오류 닫기", "오류 닫기"])
                }
                .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 8) {
                if preferences.speechInputEnabled {
                    Button(action: toggleSpeechRecognition) {
                        Image(systemName: speechRecognition.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                            .foregroundStyle(speechRecognition.isListening ? .red : .indigo)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(speechRecognition.isListening ? "음성 입력 멈추기" : "음성으로 입력")
                    .accessibilityValue(speechRecognition.permissionDescription)
                    .accessibilityHint(speechRecognition.isListening ? "현재까지 들은 내용을 입력란에 남깁니다." : "필요한 권한은 처음 사용할 때만 요청합니다.")
                    .accessibilityInputLabels(["음성 입력", "마이크"])
                }

                TextField("도치에게 메시지 보내기", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(contrast == .increased ? Color.primary.opacity(0.45) : Color.clear, lineWidth: 1)
                    }
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                    .accessibilityLabel("메시지")
                    .accessibilityIdentifier("mobile-message-composer")
                    .accessibilityHint("도치에게 보낼 내용을 입력합니다.")
                    .accessibilityFocused($accessibilityFocus, equals: .composer)

                if controller.isRunning {
                    Button(action: controller.cancel) {
                        Image(systemName: "stop.fill")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.red, in: Circle())
                    }
                    .accessibilityLabel("답변 중단")
                    .accessibilityHint("현재 모델 응답과 도구 실행을 취소합니다.")
                    .accessibilityInputLabels(["답변 중단", "중단"])
                } else {
                    Button(action: sendDraft) {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(canSend ? Color.indigo : Color.secondary, in: Circle())
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("메시지 보내기")
                    .accessibilityHint(canSend ? "입력한 메시지를 도치에게 보냅니다." : "먼저 메시지를 입력해 주세요.")
                    .accessibilityInputLabels(["메시지 보내기", "보내기"])
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(
            reduceTransparency
                ? Color(uiColor: .systemBackground)
                : Color(uiColor: .systemBackground).opacity(0.94)
        )
        .overlay(alignment: .top) { Divider() }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !controller.isRunning
    }

    private var approvalPresentation: Binding<AgentToolApprovalRequest?> {
        Binding(
            get: { controller.pendingToolApproval },
            set: { request in
                guard request == nil, let pending = controller.pendingToolApproval else { return }
                controller.resolveApproval(
                    .deny(reason: "승인 화면이 닫혔습니다."),
                    requestID: pending.id
                )
            }
        )
    }

    private var errorPresentation: Binding<Bool> {
        Binding(
            get: { controller.errorMessage != nil },
            set: { isPresented in
                if !isPresented { controller.dismissError() }
            }
        )
    }

    private func toggleSpeechRecognition() {
        speechOutput.stop()
        if speechRecognition.isListening {
            speechRecognition.stopListening()
        } else {
            isSpeechDraftActive = true
            Task { await speechRecognition.startListening(existingText: draft) }
        }
    }

    private func sendDraft() {
        guard canSend else { return }
        speechRecognition.stopListening(cancelRecognition: true)
        speechOutput.stop()
        isSpeechDraftActive = false
        let text = draft
        draft = ""
        controller.send(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
        }
    }

    private func restoreSettingsFocus() {
        let target = settingsReturnFocus
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            accessibilityFocus = target
        }
    }

    private func presentSettings(returnFocusTo target: AccessibilityTarget) {
        settingsReturnFocus = target
        isShowingSettings = true
    }

}

private struct MobileToolApprovalSheet: View {
    let request: AgentToolApprovalRequest
    let controller: MobileAgentController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(
                        MobileToolPresentation.friendlyName(request.call.name),
                        systemImage: request.descriptor.risk == .restricted
                            ? "exclamationmark.shield.fill"
                            : "checkmark.shield.fill"
                    )
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                    Text(MobileToolPresentation.approvalMessage(for: request))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("승인 세부 정보. \(MobileToolPresentation.approvalMessage(for: request))")
                }
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("도구 사용 승인")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    Button("이번만 허용") { resolve(.allowOnce) }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, minHeight: 44)

                    if MobileToolPresentation.allowsSessionApproval(request) {
                        Button("이 대화에서 허용") { resolve(.allowForSession) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }

                    Button("허용하지 않음", role: .destructive) {
                        resolve(.deny(reason: "사용자가 허용하지 않았습니다."))
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func resolve(_ decision: AgentToolApprovalDecision) {
        controller.resolveApproval(decision, requestID: request.id)
        dismiss()
    }
}

private struct MobileMessageBubble: View {
    let message: MobileChatMessage
    let avatar: MobileAvatar
    let reduceTransparency: Bool
    let increasedContrast: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if message.role == .assistant {
                Image(avatar.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else {
                Spacer(minLength: 52)
            }

            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay {
                    if increasedContrast, message.role == .assistant {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(Color.primary.opacity(0.35), lineWidth: 1)
                    }
                }

            if message.role == .assistant {
                Spacer(minLength: 38)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.role == .user ? "나" : "도치"): \(message.text)")
        .accessibilityCustomContent("보낸 시각", message.createdAt.formatted(date: .omitted, time: .shortened))
    }

    private var bubbleBackground: Color {
        if message.role == .user { return .indigo }
        if reduceTransparency { return Color(uiColor: .secondarySystemGroupedBackground) }
        return Color(uiColor: .secondarySystemGroupedBackground).opacity(0.88)
    }
}

private struct MobileStreamingBubble: View {
    let text: String
    let avatar: MobileAvatar
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Image(avatar.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            Spacer(minLength: 38)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("도치가 답변하는 중: \(text)")
    }
}

private struct MobileActivityPill: View {
    let text: String
    let systemImage: String
    let reduceTransparency: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .background(
                reduceTransparency
                    ? Color(uiColor: .secondarySystemGroupedBackground)
                    : Color(uiColor: .secondarySystemGroupedBackground).opacity(0.88),
                in: Capsule()
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 41)
            .accessibilityLabel(text)
    }
}
