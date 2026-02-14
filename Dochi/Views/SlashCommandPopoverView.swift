import SwiftUI

/// 슬래시 명령 자동완성 팝업
struct SlashCommandPopoverView: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void
    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commands.prefix(8).enumerated()), id: \.element.id) { index, command in
                Button {
                    onSelect(command)
                } label: {
                    HStack(spacing: 8) {
                        Text(command.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(width: 80, alignment: .leading)

                        Text(command.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(index == selectedIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < commands.prefix(8).count - 1 {
                    Divider()
                        .padding(.leading, 10)
                }
            }
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    /// 키보드로 선택 항목 이동
    func moveSelection(direction: Int) -> Int {
        let maxIndex = min(commands.count, 8) - 1
        var newIndex = selectedIndex + direction
        if newIndex < 0 { newIndex = maxIndex }
        if newIndex > maxIndex { newIndex = 0 }
        return newIndex
    }
}
