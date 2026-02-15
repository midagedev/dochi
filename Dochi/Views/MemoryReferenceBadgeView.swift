import SwiftUI

/// UX-8: 어시스턴트 메시지 하단에 표시되는 메모리 참조 배지
struct MemoryReferenceBadgeView: View {
    let info: MemoryContextInfo
    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 9))
                .foregroundStyle(.purple)

            Text("메모리 \(info.activeLayerCount)계층")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            showPopover = hovering
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("메모리 참조")
                .font(.system(size: 12, weight: .semibold))

            Divider()

            ForEach(info.layers) { layer in
                HStack(spacing: 6) {
                    Image(systemName: layer.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(layer.isActive ? .primary : .tertiary)
                        .frame(width: 14)

                    Text(layer.name)
                        .font(.system(size: 11))
                        .foregroundStyle(layer.isActive ? .primary : .tertiary)

                    Spacer()

                    if layer.isActive {
                        Text("\(layer.charCount)자")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                }
            }

            Divider()

            HStack {
                Text("합계")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(info.totalLength)자 (~\(info.estimatedTokens)토큰)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 200)
    }
}
