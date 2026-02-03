import SwiftUI

struct ConversationView: View {
    @EnvironmentObject var viewModel: DochiViewModel

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if viewModel.messages.isEmpty && !viewModel.isConnected {
                            emptyState
                        } else if viewModel.messages.isEmpty && viewModel.isConnected {
                            connectedEmptyState
                        }

                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        // 실시간 사용자 트랜스크립트
                        if isShowingUserTranscript {
                            liveBubble(
                                label: "나",
                                text: userTranscript,
                                color: Color.blue.opacity(0.1),
                                alignment: .trailing
                            )
                            .id("user-live")
                        }

                        // AI thinking
                        if isThinking {
                            thinkingBubble.id("thinking")
                        }

                        // AI 응답 트랜스크립트 (실시간)
                        if !assistantTranscript.isEmpty {
                            liveBubble(
                                label: "도치",
                                text: assistantTranscript,
                                color: Color(.controlBackgroundColor),
                                alignment: .leading
                            )
                            .id("assistant-live")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: assistantTranscript) {
                    withAnimation {
                        proxy.scrollTo("assistant-live", anchor: .bottom)
                    }
                }
            }

            // Wake word monitor
            if isWakeWordActive {
                VStack {
                    Spacer()
                    WakeWordMonitor(
                        variations: viewModel.wakeWordVariations,
                        transcript: viewModel.speechService.wakeWordTranscript
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Listening overlay
            if isListening {
                VStack {
                    Spacer()
                    ListeningOverlay(transcript: userTranscript)
                        .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isListening)
        .animation(.easeInOut(duration: 0.3), value: isWakeWordActive)
    }

    // MARK: - Mode-aware Computed Properties

    private var isWakeWordActive: Bool {
        viewModel.isTextMode && viewModel.speechService.state == .waitingForWakeWord
    }

    private var isListening: Bool {
        if viewModel.isTextMode {
            return viewModel.textModeState == .listening
        } else {
            return viewModel.realtime.state == .listening
        }
    }

    private var isShowingUserTranscript: Bool {
        if viewModel.isTextMode {
            return viewModel.textModeState == .listening && !viewModel.speechService.transcript.isEmpty
        } else {
            return viewModel.realtime.state == .listening && !viewModel.realtime.userTranscript.isEmpty
        }
    }

    private var userTranscript: String {
        if viewModel.isTextMode {
            return viewModel.speechService.transcript
        } else {
            return viewModel.realtime.userTranscript
        }
    }

    private var assistantTranscript: String {
        if viewModel.isTextMode {
            return viewModel.llmService.isStreaming ? viewModel.llmService.partialResponse : ""
        } else {
            return viewModel.realtime.state == .responding ? viewModel.realtime.assistantTranscript : ""
        }
    }

    private var isThinking: Bool {
        if viewModel.isTextMode {
            return viewModel.textModeState == .processing && viewModel.llmService.partialResponse.isEmpty
        } else {
            return viewModel.realtime.state == .responding && viewModel.realtime.assistantTranscript.isEmpty
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("도치에게 말을 걸어보세요")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(viewModel.isTextMode
                 ? "설정에서 LLM API 키를 입력하고 연결하세요"
                 : "설정에서 OpenAI API 키를 입력하고 연결하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var connectedEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.isTextMode ? "text.bubble.fill" : "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("연결됨 — \(viewModel.isTextMode ? "메시지를 입력하세요" : "말해보세요")")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(viewModel.isTextMode
                 ? "텍스트 입력 또는 마이크 버튼으로 음성 입력"
                 : "음성을 자동으로 감지합니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Bubbles

    private var thinkingBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("도치")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ThinkingDotsView()
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer(minLength: 60)
        }
    }

    private func liveBubble(label: String, text: String, color: Color, alignment: HorizontalAlignment) -> some View {
        HStack(alignment: .top) {
            if alignment == .trailing { Spacer(minLength: 60) }
            VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .padding(12)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if alignment == .leading { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Wake Word Monitor

struct WakeWordMonitor: View {
    let variations: [String]
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 실시간 인식 텍스트
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.mint)
                    .font(.caption)
                if transcript.isEmpty {
                    Text("음성 대기 중...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(transcript)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Spacer()
            }

            // 등록된 변형 목록
            if !variations.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(variations, id: \.self) { word in
                        let matched = !transcript.isEmpty
                            && transcript.replacingOccurrences(of: " ", with: "")
                                .contains(word.replacingOccurrences(of: " ", with: ""))
                        Text(word)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(matched ? Color.mint.opacity(0.3) : Color.secondary.opacity(0.1))
                            .foregroundStyle(matched ? .mint : .secondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for (i, row) in rows.enumerated() {
            if i > 0 { y += spacing }
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Listening Overlay

struct ListeningOverlay: View {
    let transcript: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("듣는 중...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.body)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
            }
            Spacer()
            AudioBarsView()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .orange.opacity(0.2), radius: 8, y: 4)
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Animations

struct AudioBarsView: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: 4, height: animating ? CGFloat.random(in: 8...24) : 8)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.1),
                        value: animating
                    )
            }
        }
        .frame(height: 24)
        .onAppear { animating = true }
    }
}

struct ThinkingDotsView: View {
    @State private var active = 0
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(active == i ? 1.4 : 1.0)
                    .opacity(active == i ? 1.0 : 0.4)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    active = (active + 1) % 3
                }
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "나" : "도치")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        message.role == .user
                            ? Color.blue.opacity(0.15)
                            : Color(.controlBackgroundColor)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
