import SwiftUI

/// VS Code 스타일 커맨드 팔레트 오버레이
struct CommandPaletteView: View {
    let items: [CommandPaletteItem]
    let onExecute: (CommandPaletteItem) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [CommandPaletteItem] {
        let recentIds = CommandPaletteRegistry.recentIds()
        return FuzzyMatcher.filter(
            items: items,
            query: searchText,
            keyPath: \.title,
            recentIds: recentIds,
            idKeyPath: \.id
        )
    }

    /// 그룹화된 아이템 (최대 15개)
    private var groupedItems: [(category: CommandPaletteItem.Category, items: [CommandPaletteItem])] {
        let limited = Array(filteredItems.prefix(15))
        let recentIds = Set(CommandPaletteRegistry.recentIds())

        // 최근 사용 아이템 분리
        let recentItems = limited.filter { recentIds.contains($0.id) && searchText.isEmpty }
        let otherItems = limited.filter { !recentIds.contains($0.id) || !searchText.isEmpty }

        var groups: [(category: CommandPaletteItem.Category, items: [CommandPaletteItem])] = []

        if !recentItems.isEmpty {
            groups.append((.recentCommand, recentItems))
        }

        // 나머지를 카테고리별로 그룹화
        let categoryOrder: [CommandPaletteItem.Category] = [
            .navigation, .conversation, .agent, .workspace, .user, .settings, .tool,
        ]
        for category in categoryOrder {
            let categoryItems = otherItems.filter { $0.category == category }
            if !categoryItems.isEmpty {
                groups.append((category, categoryItems))
            }
        }

        return groups
    }

    /// 플랫 리스트 (키보드 네비게이션용)
    private var flatItems: [CommandPaletteItem] {
        groupedItems.flatMap(\.items)
    }

    var body: some View {
        ZStack {
            // 배경 딤
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // 팔레트 본체
            VStack(spacing: 0) {
                // 검색 필드
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    TextField("명령 검색...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isSearchFocused)
                        .onSubmit {
                            executeSelected()
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                if flatItems.isEmpty {
                    // 빈 상태
                    VStack(spacing: 8) {
                        Text("'\(searchText)'에 해당하는 명령이 없습니다")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                } else {
                    // 아이템 목록
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(groupedItems, id: \.category) { group in
                                    // 섹션 헤더
                                    Text(group.category.rawValue)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 14)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)

                                    ForEach(group.items) { item in
                                        let isSelected = flatItems.indices.contains(selectedIndex) && flatItems[selectedIndex].id == item.id
                                        CommandPaletteRow(
                                            item: item,
                                            isSelected: isSelected
                                        )
                                        .id(item.id)
                                        .onTapGesture {
                                            executeItem(item)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 360)
                        .onChange(of: selectedIndex) { _, newIndex in
                            if flatItems.indices.contains(newIndex) {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    proxy.scrollTo(flatItems[newIndex].id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 480)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 80)
            .onKeyPress(.upArrow) {
                moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
        }
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    private func moveSelection(by delta: Int) {
        let count = flatItems.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func executeSelected() {
        guard flatItems.indices.contains(selectedIndex) else { return }
        executeItem(flatItems[selectedIndex])
    }

    private func executeItem(_ item: CommandPaletteItem) {
        CommandPaletteRegistry.recordRecent(id: item.id)
        onExecute(item)
    }
}

// MARK: - 아이템 행

struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20)

            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)

            Spacer()

            Text(item.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
