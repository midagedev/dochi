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
                            if message.toolCalls != nil {
                                ToolCallBubbleView(message: message)
                                    .id(message.id)
                            } else if message.role == .tool {
                                ToolResultBubbleView(message: message)
                                    .id(message.id)
                            } else if message.role != .system {
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }

                        // 실시간 사용자 트랜스크립트
                        if isShowingUserTranscript {
                            liveBubble(
                                label: "나",
                                text: viewModel.speechService.transcript,
                                color: Color.blue.opacity(0.1),
                                alignment: .trailing
                            )
                            .id("user-live")
                        }

                        // AI thinking / tool executing
                        if case .executingTool(let name) = viewModel.state {
                            ExecutingToolBubbleView(toolName: name).id("thinking")
                        } else if isThinking {
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

                        // 하단 여백 — 마지막 메시지가 충분히 위로 올라오도록
                        Spacer()
                            .frame(height: 120)
                            .id("bottom")
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: assistantTranscript) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
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
                    ListeningOverlay(transcript: viewModel.speechService.transcript)
                        .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isListening)
        .animation(.easeInOut(duration: 0.3), value: isWakeWordActive)
    }

    // MARK: - Computed Properties

    private var isWakeWordActive: Bool {
        viewModel.speechService.state == .waitingForWakeWord
    }

    private var isListening: Bool {
        viewModel.state == .listening
    }

    private var isShowingUserTranscript: Bool {
        viewModel.state == .listening && !viewModel.speechService.transcript.isEmpty
    }

    private var assistantTranscript: String {
        viewModel.llmService.isStreaming ? viewModel.llmService.partialResponse : ""
    }

    private var isThinking: Bool {
        viewModel.state == .processing && viewModel.llmService.partialResponse.isEmpty
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("DochiMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .opacity(0.2)
            Text("도치에게 말을 걸어보세요")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("설정에서 LLM API 키를 입력하고 연결하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var connectedEmptyState: some View {
        VStack(spacing: 16) {
            Image("DochiMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .opacity(0.2)
            Text("연결됨 — 메시지를 입력하세요")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("텍스트 입력 또는 마이크 버튼으로 음성 입력")
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
                    .font(.system(size: viewModel.settings.chatFontSize))
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

// MARK: - Tool Helpers

private enum ToolDisplay {
    static func displayName(_ name: String) -> String {
        switch name {
        case "web_search": return "웹검색"
        case "generate_image": return "이미지 생성"
        case "create_reminder": return "미리알림 생성"
        case "list_reminders": return "미리알림 조회"
        case "complete_reminder": return "미리알림 완료"
        case "set_alarm": return "알람 설정"
        case "list_alarms": return "알람 조회"
        case "cancel_alarm": return "알람 취소"
        case "print_image": return "이미지 출력"
        default: return name
        }
    }

    static func icon(_ name: String) -> String {
        switch name {
        case "web_search": return "globe.magnifyingglass"
        case "generate_image": return "photo.artframe"
        case "create_reminder", "list_reminders", "complete_reminder": return "checklist"
        case "set_alarm", "list_alarms", "cancel_alarm": return "alarm"
        case "print_image": return "printer"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Tool Call Bubble

struct ToolCallBubbleView: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(message.toolCalls ?? []) { toolCall in
                    HStack(spacing: 6) {
                        Image(systemName: ToolDisplay.icon(toolCall.name))
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                        Text(ToolDisplay.displayName(toolCall.name))
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Tool Result Bubble

struct ToolResultBubbleView: View {
    let message: Message
    @State private var isExpanded = false

    private var isError: Bool {
        message.content.hasPrefix("Error:")
    }

    private var summaryText: String {
        let firstLine = message.content.components(separatedBy: .newlines).first ?? message.content
        if firstLine.count > 80 {
            return String(firstLine.prefix(80)) + "…"
        }
        return firstLine
    }

    private var isLongContent: Bool {
        message.content.count > 80 || message.content.contains("\n")
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                if isLongContent {
                    DisclosureGroup(isExpanded: $isExpanded) {
                        Text(message.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        resultLabel
                    }
                } else {
                    resultLabel
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isError ? Color.red.opacity(0.08) : Color.cyan.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 60)
        }
    }

    private var resultLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(isError ? .red : .green)
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Executing Tool Bubble

struct ExecutingToolBubbleView: View {
    let toolName: String

    var body: some View {
        HStack(alignment: .top) {
            HStack(spacing: 6) {
                Image(systemName: ToolDisplay.icon(toolName))
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                Text(ToolDisplay.displayName(toolName))
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text("실행 중...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.cyan.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    @EnvironmentObject var viewModel: DochiViewModel
    @State private var expandedImageURL: URL?

    // ![image](url) 패턴에서 URL 추출
    private var imageURLsFromContent: [URL] {
        let pattern = #"!\[.*?\]\((.*?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(message.content.startIndex..., in: message.content)
        let matches = regex.matches(in: message.content, range: range)
        return matches.compactMap { match in
            guard let urlRange = Range(match.range(at: 1), in: message.content) else { return nil }
            return URL(string: String(message.content[urlRange]))
        }
    }

    // 마크다운 이미지 태그를 제거한 텍스트
    private var textWithoutImages: String {
        let pattern = #"\n*!\[.*?\]\(.*?\)\n*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return message.content }
        let range = NSRange(message.content.startIndex..., in: message.content)
        return regex.stringByReplacingMatches(in: message.content, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var allImageURLs: [URL] {
        var urls = message.imageURLs ?? []
        urls.append(contentsOf: imageURLsFromContent)
        return urls
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "나" : "도치")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    let displayText = allImageURLs.isEmpty ? message.content : textWithoutImages
                    if !displayText.isEmpty {
                        Text(displayText)
                            .font(.system(size: viewModel.settings.chatFontSize))
                            .textSelection(.enabled)
                    }

                    ForEach(allImageURLs, id: \.absoluteString) { imageURL in
                        GeneratedImageView(url: imageURL)
                            .onTapGesture {
                                expandedImageURL = imageURL
                            }
                    }
                }
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
        .sheet(item: $expandedImageURL) { url in
            ImagePreviewView(url: url)
        }
    }
}

// MARK: - Generated Image View

struct GeneratedImageView: View {
    let url: URL

    var body: some View {
        if url.isFileURL, let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    Label("이미지 로드 실패", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                        .frame(width: 100, height: 100)
                @unknown default:
                    ProgressView()
                        .frame(width: 100, height: 100)
                }
            }
        }
    }
}

// MARK: - Image Preview

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    saveImage()
                } label: {
                    Label("저장", systemImage: "square.and.arrow.down")
                }
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            if url.isFileURL, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding()
                    case .failure:
                        Label("이미지 로드 실패", systemImage: "exclamationmark.triangle")
                            .padding()
                    case .empty:
                        ProgressView()
                            .padding()
                    @unknown default:
                        ProgressView()
                            .padding()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.nameFieldStringValue = url.lastPathComponent
        panel.begin { result in
            if result == .OK, let destURL = panel.url {
                try? FileManager.default.copyItem(at: url, to: destURL)
            }
        }
    }
}

// MARK: - Dochi Avatar

struct DochiAvatar: View {
    let size: CGFloat

    var body: some View {
        Image("DochiMascot")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}
