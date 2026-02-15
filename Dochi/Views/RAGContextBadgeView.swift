import SwiftUI

/// assistant 메시지에 "문서 N건 참조" 배지 + 호버 팝오버
struct RAGContextBadgeView: View {
    let info: RAGContextInfo
    @State private var showPopover = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 9))
                .foregroundStyle(.blue)

            Text("문서 \(info.referenceCount)건 참조")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.blue.opacity(0.06))
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
            Text("문서 참조")
                .font(.system(size: 12, weight: .semibold))

            Divider()

            ForEach(Array(info.references.enumerated()), id: \.offset) { _, ref in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(ref.fileName)
                            .font(.system(size: 11, weight: .medium))

                        if let section = ref.sectionTitle {
                            Text(section)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Text(ref.snippetPreview)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(String(format: "%.0f%%", ref.similarity * 100))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Text("주입된 컨텍스트")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(info.totalCharsInjected)자 (~\(info.estimatedTokens)토큰)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 280, maxWidth: 360)
    }
}
