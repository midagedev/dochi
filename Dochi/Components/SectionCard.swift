import SwiftUI

struct SectionCard<Content: View>: View {
    @EnvironmentObject var viewModel: DochiViewModel
    let title: String?
    var icon: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    init(_ title: String?, icon: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                HStack(spacing: AppSpacing.s) {
                    if let icon { Image(systemName: icon).foregroundStyle(.secondary).font(.caption) }
                    Text(title)
                        .compact(AppFont.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let trailing { trailing }
                }
                .padding(.bottom, headerBottomPadding)
            }

            content
        }
        .padding(cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.border, lineWidth: 1)
        )
    }

    private var spacing: CGFloat { viewModel.settings.uiDensity == .compact ? AppSpacing.xs : AppSpacing.s }
    private var headerBottomPadding: CGFloat { viewModel.settings.uiDensity == .compact ? AppSpacing.xs : AppSpacing.xs }
    private var cardPadding: CGFloat { viewModel.settings.uiDensity == .compact ? AppSpacing.s : AppSpacing.m }
}
