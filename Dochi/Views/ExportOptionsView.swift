import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 내보내기 옵션 시트 (400x480pt)
struct ExportOptionsView: View {
    let conversation: Conversation
    let onExportFile: (ExportFormat, ExportOptions) -> Void
    let onCopyClipboard: (ExportFormat, ExportOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .markdown
    @State private var options = ExportOptions()
    @State private var showCopiedFeedback = false
    @State private var showShareError = false
    @State private var shareErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Format selection
                    formatSection

                    Divider()

                    // Options
                    optionsSection

                    Divider()

                    // Preview info
                    previewSection
                }
                .padding(20)
            }

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(width: 400, height: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("대화 내보내기")
                    .font(.system(size: 16, weight: .semibold))
                Text(conversation.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("닫기 (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Format Selection

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("형식")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(ExportFormat.allCases) { format in
                    formatCard(format)
                }
            }
        }
    }

    private func formatCard(_ format: ExportFormat) -> some View {
        let isSelected = selectedFormat == format

        return Button {
            selectedFormat = format
        } label: {
            VStack(spacing: 6) {
                Image(systemName: format.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(format.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text(".\(format.fileExtension)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("옵션")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle(isOn: $options.includeSystemMessages) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("시스템 메시지 포함")
                        .font(.system(size: 13))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $options.includeToolMessages) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("도구 호출 포함")
                        .font(.system(size: 13))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $options.includeMetadata) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                    Text("메타데이터 포함")
                        .font(.system(size: 13))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("미리보기")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            let messageCount = filteredMessageCount
            let fileName = ConversationExporter.suggestedFileName(for: conversation, format: selectedFormat)

            HStack(spacing: 12) {
                Label("\(messageCount)개 메시지", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Label(fileName, systemImage: "doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var filteredMessageCount: Int {
        conversation.messages.filter { message in
            switch message.role {
            case .system: return options.includeSystemMessages
            case .tool: return options.includeToolMessages
            case .user, .assistant: return true
            }
        }.count
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            // Clipboard copy
            Button {
                if selectedFormat == .pdf {
                    showShareError = true
                } else {
                    onCopyClipboard(selectedFormat, options)
                    showCopiedFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopiedFeedback = false
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 12))
                    Text(showCopiedFeedback ? "복사 완료!" : "클립보드 복사")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(selectedFormat == .pdf)
            .alert("PDF 복사 불가", isPresented: $showShareError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("PDF는 클립보드에 복사할 수 없습니다. 파일로 저장하거나 공유해주세요.")
            }

            // Share
            Button {
                shareViaService()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                    Text("공유...")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            .alert("공유 실패", isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { if !$0 { shareErrorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(shareErrorMessage ?? "")
            }

            // Save to file
            Button {
                onExportFile(selectedFormat, options)
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                    Text("파일 저장")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Share

    private func shareViaService() {
        guard let data = ConversationExporter.exportToData(conversation, format: selectedFormat, options: options) else {
            Log.app.error("공유 실패: 내보내기 데이터 생성 실패 (format: \(selectedFormat.rawValue))")
            shareErrorMessage = "내보내기 데이터를 생성할 수 없습니다."
            return
        }

        let fileName = ConversationExporter.suggestedFileName(for: conversation, format: selectedFormat)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            Log.app.error("공유 실패: 임시 파일 쓰기 실패 — \(error.localizedDescription)")
            shareErrorMessage = "임시 파일을 생성할 수 없습니다: \(error.localizedDescription)"
            return
        }

        guard let window = NSApp.keyWindow else { return }
        guard let contentView = window.contentView else { return }

        let picker = NSSharingServicePicker(items: [tempURL])
        let buttonFrame = CGRect(x: window.frame.width / 2, y: 40, width: 1, height: 1)
        picker.show(relativeTo: buttonFrame, of: contentView, preferredEdge: .maxY)
    }
}
