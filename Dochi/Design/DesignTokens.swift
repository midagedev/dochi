import SwiftUI

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum AppRadius {
    static let small: CGFloat = 4
    static let medium: CGFloat = 6
    static let large: CGFloat = 12
}

enum AppFont {
    static let caption2 = Font.system(size: 11)
    static let caption = Font.system(size: 12.5)
    static let body = Font.system(size: 13)
    static let title = Font.system(size: 15, weight: .semibold)
}

enum AppColor {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let subtle = Color.primary.opacity(0.06)
    static let border = Color(nsColor: .separatorColor)
    static let muted = Color.secondary
    static let accent = Color.accentColor
    static let danger = Color.red
    static let success = Color.green
    static let warning = Color.orange
}

struct CompactText: ViewModifier {
    let font: Font
    func body(content: Content) -> some View {
        content
            .font(font)
            .lineSpacing(0)
    }
}

extension View {
    func compact(_ font: Font) -> some View { modifier(CompactText(font: font)) }
    func hairlineDivider() -> some View { Rectangle().fill(AppColor.border).frame(height: 1) }
}

