import SwiftUI

/// 슬래시 명령 자동완성 팝업
struct SlashCommandPopoverView: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void

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
                            .frame(minWidth: 80, alignment: .leading)

                        Text(command.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < commands.prefix(8).count - 1 {
                    Divider()
                        .padding(.leading, 10)
                }
            }
        }
        .frame(minWidth: 280, maxWidth: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
