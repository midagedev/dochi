import SwiftUI

struct SectionHeader: View {
    let title: String
    var compact: Bool = true
    var trailing: AnyView? = nil

    init(_ title: String, compact: Bool = true, trailing: AnyView? = nil) {
        self.title = title
        self.compact = compact
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .compact(AppFont.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, compact ? AppSpacing.xs : AppSpacing.s)
        .background(AppColor.background)
    }
}

