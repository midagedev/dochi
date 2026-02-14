import SwiftUI

/// 대화 목록 (즐겨찾기/폴더/미분류 섹션)
struct ConversationListView: View {
    @Bindable var viewModel: DochiViewModel
    let conversations: [Conversation]
    let filter: ConversationFilter
    @Binding var selectedSection: ContentView.MainSection
    @State private var showTagManagement = false

    private var profileMap: [String: String] {
        Dictionary(
            uniqueKeysWithValues: viewModel.contextService.loadProfiles()
                .map { ($0.id.uuidString, $0.name) }
        )
    }

    private var favoriteConversations: [Conversation] {
        conversations.filter(\.isFavorite)
    }

    private var hasFolders: Bool {
        !viewModel.conversationFolders.isEmpty
    }

    private func conversationsInFolder(_ folderId: UUID) -> [Conversation] {
        conversations.filter { $0.folderId == folderId }
    }

    private var uncategorizedConversations: [Conversation] {
        if hasFolders {
            return conversations.filter { !$0.isFavorite && $0.folderId == nil }
        } else {
            return conversations.filter { !$0.isFavorite }
        }
    }

    var body: some View {
        if conversations.isEmpty {
            emptyFilterState
        } else {
            List(selection: Binding(
                get: { viewModel.currentConversation?.id },
                set: { id in
                    if let id, !viewModel.isMultiSelectMode {
                        selectedSection = .chat
                        viewModel.selectConversation(id: id)
                    }
                }
            )) {
                // Favorites section
                if !favoriteConversations.isEmpty && !filter.showFavoritesOnly {
                    Section {
                        ForEach(favoriteConversations) { conversation in
                            conversationRow(conversation)
                        }
                    } header: {
                        Label("즐겨찾기", systemImage: "star.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.yellow)
                    }
                }

                // Folder sections
                if hasFolders {
                    ForEach(viewModel.conversationFolders.sorted(by: { $0.sortOrder < $1.sortOrder })) { folder in
                        let folderConvs = conversationsInFolder(folder.id)
                        Section {
                            if folderConvs.isEmpty {
                                Text("대화를 여기로 드래그하세요")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(folderConvs) { conversation in
                                    conversationRow(conversation)
                                }
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: folder.icon)
                                    .font(.system(size: 10))
                                Text(folder.name)
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("\(folderConvs.count)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button("이름 변경") {
                                    // Inline rename handled via alert or edit in place
                                }
                                Button(role: .destructive) {
                                    viewModel.deleteFolder(id: folder.id)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            for item in items {
                                if let id = UUID(uuidString: item) {
                                    viewModel.moveConversationToFolder(conversationId: id, folderId: folder.id)
                                }
                            }
                            return true
                        }
                    }
                }

                // Uncategorized / flat list
                let uncategorized = filter.showFavoritesOnly ? conversations : uncategorizedConversations
                if !uncategorized.isEmpty {
                    if hasFolders || (!favoriteConversations.isEmpty && !filter.showFavoritesOnly) {
                        Section {
                            ForEach(uncategorized) { conversation in
                                conversationRow(conversation)
                            }
                        } header: {
                            if hasFolders {
                                Text("미분류")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        ForEach(uncategorized) { conversation in
                            conversationRow(conversation)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .sheet(isPresented: $showTagManagement) {
                TagManagementView(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var emptyFilterState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("조건에 맞는 대화가 없습니다")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if filter.isActive {
                Button("필터 초기화") {
                    // handled by parent via binding
                }
                .font(.system(size: 12))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        HStack(spacing: 4) {
            // Multi-select checkbox
            if viewModel.isMultiSelectMode {
                Button {
                    viewModel.toggleConversationSelection(id: conversation.id)
                } label: {
                    Image(systemName: viewModel.selectedConversationIds.contains(conversation.id)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(viewModel.selectedConversationIds.contains(conversation.id)
                                         ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // Favorite icon
                    if conversation.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }

                    if conversation.source == .telegram {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                    Text(conversation.title)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    if let userId = conversation.userId,
                       let userName = profileMap[userId] {
                        Text(userName)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 4) {
                    Text(conversation.updatedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    // Tag chips (max 2 + overflow)
                    if !conversation.tags.isEmpty {
                        tagChips(conversation.tags)
                    }
                }
            }
        }
        .tag(conversation.id)
        .draggable(conversation.id.uuidString)
        .contextMenu {
            // Favorite toggle
            Button {
                viewModel.toggleFavorite(id: conversation.id)
            } label: {
                Label(
                    conversation.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                    systemImage: conversation.isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            // Tags submenu
            Menu("태그") {
                ForEach(viewModel.conversationTags) { tag in
                    Button {
                        viewModel.toggleTagOnConversation(conversationId: conversation.id, tagName: tag.name)
                    } label: {
                        HStack {
                            Circle()
                                .fill(tagColor(tag.color))
                                .frame(width: 8, height: 8)
                            Text(tag.name)
                            if conversation.tags.contains(tag.name) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button {
                    showTagManagement = true
                } label: {
                    Label("태그 관리...", systemImage: "tag")
                }
            }

            // Folder submenu
            if !viewModel.conversationFolders.isEmpty {
                Menu("폴더로 이동") {
                    ForEach(viewModel.conversationFolders) { folder in
                        Button {
                            viewModel.moveConversationToFolder(conversationId: conversation.id, folderId: folder.id)
                        } label: {
                            HStack {
                                Image(systemName: folder.icon)
                                Text(folder.name)
                                if conversation.folderId == folder.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        viewModel.moveConversationToFolder(conversationId: conversation.id, folderId: nil)
                    } label: {
                        Label("폴더에서 제거", systemImage: "folder.badge.minus")
                    }
                }
            }

            Divider()

            Button("이름 변경") {
                viewModel.renameConversation(id: conversation.id, title: "")
            }

            Menu("내보내기") {
                Button {
                    viewModel.exportConversation(id: conversation.id, format: .markdown)
                } label: {
                    Label("마크다운 (.md)", systemImage: "doc.text")
                }
                Button {
                    viewModel.exportConversation(id: conversation.id, format: .json)
                } label: {
                    Label("JSON (.json)", systemImage: "doc.badge.gearshape")
                }
            }

            Divider()

            Button(role: .destructive) {
                viewModel.deleteConversation(id: conversation.id)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func tagChips(_ tags: [String]) -> some View {
        let displayTags = Array(tags.prefix(2))
        let overflow = tags.count - 2

        HStack(spacing: 2) {
            ForEach(displayTags, id: \.self) { tagName in
                if let tag = viewModel.conversationTags.first(where: { $0.name == tagName }) {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(tagColor(tag.color))
                            .frame(width: 5, height: 5)
                        Text(tag.name)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(tagColor(tag.color).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}

/// 일괄 선택 모드 하단 툴바
struct BulkActionToolbarView: View {
    @Bindable var viewModel: DochiViewModel
    @State private var showDeleteConfirm = false

    var body: some View {
        if viewModel.isMultiSelectMode {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Text("\(viewModel.selectedConversationIds.count)개 선택")
                        .font(.system(size: 12, weight: .medium))

                    Spacer()

                    Button {
                        if viewModel.selectedConversationIds.count == viewModel.conversations.count {
                            viewModel.deselectAllConversations()
                        } else {
                            viewModel.selectAllConversations()
                        }
                    } label: {
                        Image(systemName: viewModel.selectedConversationIds.count == viewModel.conversations.count
                              ? "checkmark.circle" : "checkmark.circle.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("전체 선택/해제")

                    if !viewModel.conversationFolders.isEmpty {
                        Menu {
                            ForEach(viewModel.conversationFolders) { folder in
                                Button {
                                    viewModel.bulkMoveToFolder(folderId: folder.id)
                                } label: {
                                    Label(folder.name, systemImage: folder.icon)
                                }
                            }
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 13))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        .help("폴더로 이동")
                    }

                    if !viewModel.conversationTags.isEmpty {
                        Menu {
                            ForEach(viewModel.conversationTags) { tag in
                                Button {
                                    viewModel.bulkAddTag(tagName: tag.name)
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(tagColor(tag.color))
                                            .frame(width: 8, height: 8)
                                        Text(tag.name)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "tag")
                                .font(.system(size: 13))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        .help("태그 추가")
                    }

                    Button {
                        viewModel.bulkSetFavorite(true)
                    } label: {
                        Image(systemName: "star")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("즐겨찾기 설정")

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("삭제")
                    .disabled(viewModel.selectedConversationIds.isEmpty)
                    .alert("대화 삭제", isPresented: $showDeleteConfirm) {
                        Button("취소", role: .cancel) {}
                        Button("삭제", role: .destructive) {
                            viewModel.bulkDelete()
                        }
                    } message: {
                        Text("\(viewModel.selectedConversationIds.count)개 대화를 삭제합니다.")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
            }
        }
    }
}
