import SwiftUI

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .compact(AppFont.body)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .compact(AppFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }
}

