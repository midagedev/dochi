import SwiftUI

/// 메모리 자동 정리 상태 배너
struct MemoryConsolidationBannerView: View {
    let state: ConsolidationState
    var onShowDiff: (() -> Void)?
    var onShowConflicts: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .analyzing:
            bannerContent(
                icon: "brain",
                iconColor: .purple,
                text: "메모리 정리 중...",
                showSpinner: true,
                backgroundColor: .purple.opacity(0.08)
            )

        case .completed(let added, let updated):
            bannerContent(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                text: completedText(added: added, updated: updated),
                showSpinner: false,
                backgroundColor: .green.opacity(0.08),
                actionLabel: "변경 내용",
                action: onShowDiff
            )

        case .conflict(let count):
            bannerContent(
                icon: "exclamationmark.triangle.fill",
                iconColor: .orange,
                text: "메모리 모순 \(count)건 발견",
                showSpinner: false,
                backgroundColor: .orange.opacity(0.08),
                actionLabel: "해결하기",
                action: onShowConflicts
            )

        case .failed(let message):
            bannerContent(
                icon: "xmark.circle.fill",
                iconColor: .red,
                text: "메모리 정리 실패: \(message)",
                showSpinner: false,
                backgroundColor: .red.opacity(0.08)
            )
        }
    }

    @ViewBuilder
    private func bannerContent(
        icon: String,
        iconColor: Color,
        text: String,
        showSpinner: Bool,
        backgroundColor: Color,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.system(size: 12))

            if showSpinner {
                ProgressView()
                    .controlSize(.small)
            }

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if let actionLabel, let action {
                Button(actionLabel) {
                    action()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !showSpinner, let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func completedText(added: Int, updated: Int) -> String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added)건 추가") }
        if updated > 0 { parts.append("\(updated)건 갱신") }
        if parts.isEmpty { return "변경 없음" }
        return "메모리 정리 완료: " + parts.joined(separator: ", ")
    }
}
