import SwiftUI

/// 필터 팝오버 내용
struct ConversationFilterView: View {
    @Binding var filter: ConversationFilter
    let tags: [ConversationTag]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("필터")
                .font(.system(size: 13, weight: .semibold))

            // Favorites
            Toggle(isOn: $filter.showFavoritesOnly) {
                Label("즐겨찾기만", systemImage: "star.fill")
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)

            // Tags
            if !tags.isEmpty {
                Divider()
                Text("태그")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 4) {
                    ForEach(tags) { tag in
                        tagChip(tag)
                    }
                }
            }

            // Source
            Divider()
            Text("소스")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                sourceButton(nil, label: "전체")
                sourceButton(.local, label: "로컬")
                sourceButton(.telegram, label: "텔레그램")
            }

            if filter.isActive {
                Divider()
                Button {
                    filter.reset()
                } label: {
                    Label("필터 초기화", systemImage: "xmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    @ViewBuilder
    private func tagChip(_ tag: ConversationTag) -> some View {
        let isSelected = filter.selectedTags.contains(tag.name)
        Button {
            if isSelected {
                filter.selectedTags.remove(tag.name)
            } else {
                filter.selectedTags.insert(tag.name)
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(tagColor(tag.color))
                    .frame(width: 6, height: 6)
                Text(tag.name)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? tagColor(tag.color).opacity(0.15) : Color.secondary.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sourceButton(_ source: ConversationSource?, label: String) -> some View {
        let isSelected = filter.source == source
        Button {
            filter.source = source
        } label: {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 활성 필터 칩 가로 스크롤
struct ConversationFilterChipsView: View {
    @Binding var filter: ConversationFilter

    var body: some View {
        if filter.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if filter.showFavoritesOnly {
                        chipView("즐겨찾기", icon: "star.fill") {
                            filter.showFavoritesOnly = false
                        }
                    }
                    ForEach(Array(filter.selectedTags), id: \.self) { tagName in
                        chipView(tagName, icon: "tag.fill") {
                            filter.selectedTags.remove(tagName)
                        }
                    }
                    if let source = filter.source {
                        chipView(source == .local ? "로컬" : "텔레그램", icon: "paperplane") {
                            filter.source = nil
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func chipView(_ label: String, icon: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(label)
                .font(.system(size: 10))
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

/// 태그 칩 등을 줄바꿈 가능한 레이아웃으로 배치
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x)
            totalHeight = y + rowHeight
        }

        return LayoutResult(
            positions: positions,
            size: CGSize(width: totalWidth, height: totalHeight)
        )
    }
}

// MARK: - Tag Color Helper

func tagColor(_ name: String) -> Color {
    switch name {
    case "red": return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green": return .green
    case "blue": return .blue
    case "purple": return .purple
    case "pink": return .pink
    case "brown": return .brown
    case "gray": return .gray
    default: return .blue
    }
}
