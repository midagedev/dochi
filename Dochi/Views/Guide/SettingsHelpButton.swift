import SwiftUI

// MARK: - SettingsHelpButton

/// 설정 섹션 헤더에 사용하는 "?" 도움말 팝오버 버튼.
/// 클릭 시 해당 섹션에 대한 설명을 팝오버로 표시한다.
struct SettingsHelpButton: View {
    let title: String
    let content: String

    @State private var isHovering = false
    @State private var showPopover = false

    init(title: String = "", content: String) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(isHovering ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 280)
        }
        .accessibilityLabel("\(title.isEmpty ? "도움말" : title) 도움말")
        .accessibilityHint("클릭하면 도움말을 표시합니다")
    }
}

// MARK: - Section Header with Help

/// 도움말 버튼이 포함된 설정 섹션 헤더를 편리하게 생성하는 뷰.
struct SettingsSectionHeader: View {
    let title: String
    let helpContent: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            SettingsHelpButton(title: title, content: helpContent)
        }
    }
}
