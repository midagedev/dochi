import SwiftUI

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss
    let changelogService: ChangelogService
    let showFullChangelog: Bool

    @State private var content: String = ""

    init(changelogService: ChangelogService = ChangelogService(), showFullChangelog: Bool = false) {
        self.changelogService = changelogService
        self.showFullChangelog = showFullChangelog
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(showFullChangelog ? "버전 기록" : "새로운 기능")
                        .font(.headline)
                    Text("v\(changelogService.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기") {
                    changelogService.markCurrentVersionAsSeen()
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ChangelogContentView(markdown: content)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            content = showFullChangelog
                ? changelogService.loadChangelog()
                : changelogService.loadCurrentVersionChanges()
        }
    }
}

/// 마크다운을 파싱하여 표시하는 뷰
struct ChangelogContentView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseMarkdown(markdown), id: \.id) { block in
                switch block.type {
                case .h1:
                    Text(block.content)
                        .font(.title.bold())
                case .h2:
                    Text(block.content)
                        .font(.title2.bold())
                        .padding(.top, 8)
                case .h3:
                    Text(block.content)
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .padding(.top, 4)
                case .listItem:
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(block.content)
                            .font(.body)
                    }
                    .padding(.leading, 8)
                case .paragraph:
                    Text(block.content)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Markdown Parsing

    private struct MarkdownBlock: Identifiable {
        let id = UUID()
        let type: BlockType
        let content: String

        enum BlockType {
            case h1, h2, h3, listItem, paragraph
        }
    }

    private func parseMarkdown(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("# ") {
                blocks.append(MarkdownBlock(type: .h1, content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(MarkdownBlock(type: .h2, content: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("### ") {
                blocks.append(MarkdownBlock(type: .h3, content: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("- ") {
                blocks.append(MarkdownBlock(type: .listItem, content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("* ") {
                blocks.append(MarkdownBlock(type: .listItem, content: String(trimmed.dropFirst(2))))
            } else {
                blocks.append(MarkdownBlock(type: .paragraph, content: trimmed))
            }
        }

        return blocks
    }
}
