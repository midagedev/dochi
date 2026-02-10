import SwiftUI

struct BadgeView: View {
    enum Style { case mutedCount, status(Color) }
    let style: Style
    let text: String

    var body: some View {
        switch style {
        case .mutedCount:
            Text(text)
                .compact(AppFont.caption)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 1)
                .background(AppColor.subtle, in: Capsule())
                .foregroundStyle(.secondary)
        case .status(let color):
            HStack(spacing: AppSpacing.xs) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(text).compact(AppFont.caption)
            }
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
        }
    }
}

