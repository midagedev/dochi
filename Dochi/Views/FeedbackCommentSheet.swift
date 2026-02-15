import SwiftUI

/// 부정 피드백 사유 입력 시트 (I-4)
struct FeedbackCommentSheet: View {
    let messageId: UUID
    let onSubmit: (FeedbackCategory?, String?) -> Void
    let onCancel: () -> Void

    @State private var selectedCategory: FeedbackCategory?
    @State private var comment: String = ""
    @FocusState private var isCommentFocused: Bool

    private static let maxCommentLength = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("어떤 점이 아쉬웠나요?")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("취소")
            }

            // Category chips
            VStack(alignment: .leading, spacing: 8) {
                Text("카테고리")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(FeedbackCategory.allCases, id: \.rawValue) { category in
                        categoryChip(category)
                    }
                }
            }

            // Comment
            VStack(alignment: .leading, spacing: 4) {
                Text("추가 의견 (선택)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextEditor(text: $comment)
                    .font(.system(size: 12))
                    .frame(height: 60)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .focused($isCommentFocused)
                    .onChange(of: comment) { _, newValue in
                        if newValue.count > Self.maxCommentLength {
                            comment = String(newValue.prefix(Self.maxCommentLength))
                        }
                    }

                HStack {
                    Spacer()
                    Text("\(comment.count)/\(Self.maxCommentLength)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Actions
            HStack {
                Button("건너뛰기") {
                    onSubmit(nil, nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("카테고리 없이 부정 피드백만 기록")

                Spacer()

                Button("제출") {
                    let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSubmit(selectedCategory, trimmedComment.isEmpty ? nil : trimmedComment)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360, height: 320)
    }

    // MARK: - Category Chip

    @ViewBuilder
    private func categoryChip(_ category: FeedbackCategory) -> some View {
        let isSelected = selectedCategory == category

        Button {
            if selectedCategory == category {
                selectedCategory = nil
            } else {
                selectedCategory = category
            }
        } label: {
            Text(category.displayName)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// Note: FlowLayout is defined in ConversationFilterView.swift and reused here.
