import SwiftUI

/// 빠른 전환 시트 (에이전트/워크스페이스/사용자)
/// Generic over any Identifiable item.
struct QuickSwitcherView<Item: Identifiable>: View where Item.ID: Hashable {
    let title: String
    let items: [Item]
    let currentId: Item.ID?
    let label: (Item) -> String
    let icon: (Item) -> String
    let onSelect: (Item) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredItems: [Item] {
        if searchText.isEmpty {
            return items
        }
        return items.filter {
            label($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var showSearch: Bool {
        items.count >= 4
    }

    var body: some View {
        VStack(spacing: 0) {
            // 제목
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // 검색 (4개 이상일 때)
            if showSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    TextField("검색...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            // 아이템 목록
            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Text("항목 없음")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 20)
            } else {
                List {
                    ForEach(filteredItems, id: \.id) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: icon(item))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                Text(label(item))
                                    .font(.system(size: 13))

                                Spacer()

                                if item.id == currentId {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 320, height: min(CGFloat(items.count) * 36 + 120, 400))
    }
}
