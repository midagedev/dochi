import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: Message
    let fontSize: Double
    @State private var isHovering = false
    @State private var showCopied = false

    init(message: Message, fontSize: Double = 14.0) {
        self.message = message
        self.fontSize = fontSize
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label for non-user messages
                if message.role == .tool {
                    Label(toolLabel, systemImage: "wrench")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Content
                contentView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(backgroundColor)
                    .cornerRadius(12)
                    .foregroundStyle(foregroundColor)
                    .overlay(alignment: .topTrailing) {
                        copyButton
                    }
                    .onHover { hovering in
                        isHovering = hovering
                    }

                // UX-7: Archived tool execution records (preferred over raw tool calls)
                if let records = message.toolExecutionRecords, !records.isEmpty {
                    ForEach(records) { record in
                        ToolExecutionRecordCardView(record: record)
                    }
                }
                // Fallback: Raw tool calls display (for messages without execution records)
                else if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls, id: \.id) { call in
                        toolCallView(call)
                    }
                }

                // I-3: Inline base64 images (Vision)
                if let images = message.imageData, !images.isEmpty {
                    inlineImageDataView(images: images)
                }

                // Image URLs
                if let imageURLs = message.imageURLs, !imageURLs.isEmpty {
                    ForEach(imageURLs, id: \.absoluteString) { url in
                        if url.isFileURL, let nsImage = NSImage(contentsOf: url) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 300, maxHeight: 300)
                                .cornerRadius(8)
                        } else {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 300, maxHeight: 300)
                                        .cornerRadius(8)
                                case .failure:
                                    Label("이미지 로드 실패", systemImage: "photo.badge.exclamationmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                case .empty:
                                    ProgressView()
                                        .frame(width: 100, height: 100)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                }

                // Metadata badges (assistant messages only)
                if message.role == .assistant {
                    HStack(spacing: 4) {
                        if let metadata = message.metadata {
                            MessageMetadataBadgeView(metadata: metadata)
                        }

                        // UX-8: Memory reference badge
                        if let memoryInfo = message.memoryContextInfo {
                            MemoryReferenceBadgeView(info: memoryInfo)
                        }

                        // I-1: RAG context badge
                        if let ragInfo = message.ragContextInfo, ragInfo.hasReferences {
                            RAGContextBadgeView(info: ragInfo)
                        }
                    }
                }

                // Timestamp
                Text(relativeTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    // MARK: - Copy Button

    @ViewBuilder
    private var copyButton: some View {
        if !message.content.isEmpty {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCopied = false
                    }
                }
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(showCopied ? .green : (message.role == .user ? .white.opacity(0.7) : .secondary))
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .padding(4)
            .opacity(isHovering || showCopied ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .help("메시지 복사")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if message.content.isEmpty && message.toolCalls != nil {
            // Assistant message with only tool calls, no text content
            EmptyView()
                .frame(width: 0, height: 0)
        } else {
            Text(renderedContent)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
        }
    }

    private var renderedContent: AttributedString {
        // Try markdown rendering, fall back to plain text
        if let attributed = try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(message.content)
    }

    // MARK: - Inline Image Data Display (I-3)

    @ViewBuilder
    private func inlineImageDataView(images: [ImageContent]) -> some View {
        let columns = images.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, imageContent in
                InlineImageContentView(imageContent: imageContent)
            }
        }
    }

    // MARK: - Tool Call Display

    private func toolCallView(_ call: CodableToolCall) -> some View {
        DisclosureGroup {
            Text(call.argumentsJSON)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        } label: {
            Label(call.name, systemImage: "function")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.orange.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private var toolLabel: String {
        if let callId = message.toolCallId {
            return callId
        }
        return "도구 결과"
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: message.timestamp, relativeTo: Date())
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: .blue.opacity(0.8)
        case .assistant: .secondary.opacity(0.12)
        case .system: .orange.opacity(0.12)
        case .tool: .green.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}

// MARK: - Inline Image Content View (I-3)

/// Displays a single base64-encoded image from ImageContent with click-to-enlarge.
struct InlineImageContentView: View {
    let imageContent: ImageContent
    @State private var showFullSize = false
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let image = nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        showFullSize = true
                    }
                    .popover(isPresented: $showFullSize) {
                        VStack(spacing: 8) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 600, maxHeight: 600)

                            HStack(spacing: 12) {
                                Text("\(imageContent.width) x \(imageContent.height)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Text(imageContent.mimeType)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(12)
                    }
                    .help("클릭하여 원본 크기로 보기")
            } else {
                Label("이미지 표시 불가", systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard let data = Data(base64Encoded: imageContent.base64Data) else { return }
            nsImage = NSImage(data: data)
        }
    }
}

// MARK: - Message Metadata Badge

struct MessageMetadataBadgeView: View {
    let metadata: MessageMetadata
    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 4) {
            if metadata.wasFallback {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }

            Text(metadata.shortDisplay)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            showPopover = hovering
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            metadataPopover
        }
    }

    private var metadataPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("응답 상세")
                .font(.system(size: 12, weight: .semibold))

            Divider()

            metadataRow("프로바이더", metadata.provider)
            metadataRow("모델", metadata.model)

            if let input = metadata.inputTokens {
                metadataRow("입력 토큰", "\(input)")
            }
            if let output = metadata.outputTokens {
                metadataRow("출력 토큰", "\(output)")
            }
            if let latency = metadata.totalLatency {
                metadataRow("응답 시간", String(format: "%.1f초", latency))
            }
            if metadata.wasFallback {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("폴백 모델 사용됨")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .frame(minWidth: 180)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}
