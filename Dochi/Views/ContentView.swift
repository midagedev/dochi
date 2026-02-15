import SwiftUI

struct ContentView: View {
    enum MainSection: String, CaseIterable {
        case chat = "대화"
        case kanban = "칸반"
    }

    @Bindable var viewModel: DochiViewModel
    var supabaseService: SupabaseServiceProtocol?
    var heartbeatService: HeartbeatService?
    @State private var showContextInspector = false
    @State private var showCapabilityCatalog = false
    @State private var showSystemStatusSheet = false
    @State private var selectedSection: MainSection = .chat

    // UX-3: 키보드 단축키 체계
    @State private var showCommandPalette = false
    @State private var showShortcutHelp = false
    @State private var showAgentSwitcher = false
    @State private var showWorkspaceSwitcher = false
    @State private var showUserSwitcher = false
    @State private var showTagManagementFromPalette = false

    // UX-5: 내보내기/공유
    @State private var showExportOptions = false

    // UX-6: 에이전트 위저드
    @State private var showAgentWizard = false

    // UX-8: 메모리 패널
    @State private var showMemoryPanel = false

    // UX-9: 기능 투어
    @State private var showFeatureTour = false

    // UX-10: 빠른 모델 팝오버
    @State private var showQuickModelPopover = false

    var body: some View {
        mainContent
            .onAppear {
                viewModel.loadConversations()
            }
            .sheet(isPresented: $showContextInspector) {
                ContextInspectorView(
                    contextService: viewModel.contextService,
                    settings: viewModel.settings,
                    sessionContext: viewModel.sessionContext
                )
            }
            .sheet(isPresented: $showCapabilityCatalog) {
                CapabilityCatalogView(
                    toolInfos: viewModel.allToolInfos,
                    onSelectPrompt: { prompt in
                        viewModel.inputText = prompt
                        viewModel.sendMessage()
                    }
                )
            }
            .sheet(isPresented: $showSystemStatusSheet) {
                SystemStatusSheetView(
                    metricsCollector: viewModel.metricsCollector,
                    settings: viewModel.settings,
                    heartbeatService: heartbeatService,
                    supabaseService: supabaseService
                )
            }
            .sheet(isPresented: $showShortcutHelp) {
                KeyboardShortcutHelpView()
            }
            .sheet(isPresented: $showAgentSwitcher) {
                agentSwitcherSheet
            }
            .sheet(isPresented: $showWorkspaceSwitcher) {
                workspaceSwitcherSheet
            }
            .sheet(isPresented: $showUserSwitcher) {
                userSwitcherSheet
            }
            .sheet(isPresented: $showTagManagementFromPalette) {
                TagManagementView(viewModel: viewModel)
            }
            .sheet(isPresented: $showExportOptions) {
                if let conversation = viewModel.currentConversation {
                    ExportOptionsView(
                        conversation: conversation,
                        onExportFile: { format, options in
                            viewModel.exportConversationToFile(conversation, format: format, options: options)
                        },
                        onCopyClipboard: { format, options in
                            viewModel.exportConversationToClipboard(conversation, format: format, options: options)
                        }
                    )
                }
            }
            .sheet(isPresented: $showAgentWizard) {
                AgentWizardView(viewModel: viewModel)
            }
            .sheet(isPresented: $showFeatureTour) {
                FeatureTourView(
                    onComplete: {
                        viewModel.settings.featureTourCompleted = true
                        showFeatureTour = false
                    },
                    onSkip: {
                        viewModel.settings.featureTourCompleted = true
                        viewModel.settings.featureTourSkipped = true
                        showFeatureTour = false
                    }
                )
            }
    }

    // MARK: - Main Content (split to help type checker)

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            navigationContent

            // Command palette overlay (ZStack)
            if showCommandPalette {
                CommandPaletteView(
                    items: paletteItems,
                    onExecute: { item in
                        executePaletteAction(item.action)
                        showCommandPalette = false
                    },
                    onDismiss: { showCommandPalette = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            // UX-8: Memory toast overlay
            MemoryToastContainerView(
                events: viewModel.memoryToastEvents,
                onViewMemory: { showMemoryPanel = true },
                onDismiss: { id in viewModel.dismissMemoryToast(id: id) }
            )
        }
        // Hidden buttons for keyboard shortcuts
        .background { hiddenShortcutButtons }
        // Keyboard shortcut: Escape to cancel, deny confirmation, or close palette
        .onKeyPress(.escape) {
            if showCommandPalette {
                showCommandPalette = false
                return .handled
            }
            // UX-7: Escape to deny tool confirmation
            if viewModel.pendingToolConfirmation != nil {
                viewModel.respondToToolConfirmation(approved: false)
                return .handled
            }
            if selectedSection == .chat, viewModel.interactionState == .processing {
                viewModel.cancelRequest()
                return .handled
            }
            return .ignored
        }
        // UX-7: Enter/Return to approve tool confirmation
        .onKeyPress(.return) {
            if viewModel.pendingToolConfirmation != nil {
                viewModel.respondToToolConfirmation(approved: true)
                return .handled
            }
            return .ignored
        }
        // ⌘K: Command palette, ⌘⇧K: Toggle kanban/chat, ⌘1~9: conversation switch
        .onKeyPress(phases: .down) { press in
            handleKeyPress(press)
        }
    }

    @ViewBuilder
    private var navigationContent: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: viewModel,
                supabaseService: supabaseService,
                selectedSection: $selectedSection
            )
        } detail: {
            detailContent
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if selectedSection == .chat {
                            HStack(spacing: 4) {
                                Button {
                                    showExportOptions = true
                                } label: {
                                    Label("내보내기", systemImage: "square.and.arrow.up")
                                }
                                .help("내보내기 옵션 (⌘⇧E)")
                                .keyboardShortcut("e", modifiers: [.command, .shift])
                                .disabled(viewModel.currentConversation == nil)

                                Button {
                                    showSystemStatusSheet = true
                                } label: {
                                    Label("상태", systemImage: "heart.text.square")
                                }
                                .help("시스템 상태 (⌘⇧S)")
                                .keyboardShortcut("s", modifiers: [.command, .shift])

                                Button {
                                    showCapabilityCatalog = true
                                } label: {
                                    Label("기능", systemImage: "square.grid.2x2")
                                }
                                .help("기능 카탈로그 (⌘⇧F)")
                                .keyboardShortcut("f", modifiers: [.command, .shift])

                                Button {
                                    showMemoryPanel.toggle()
                                } label: {
                                    Label("메모리", systemImage: "brain")
                                }
                                .help("메모리 인스펙터 (⌘I)")
                                .keyboardShortcut("i", modifiers: .command)
                            }
                        }
                    }
                }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .inspector(isPresented: $showMemoryPanel) {
            MemoryPanelView(
                contextService: viewModel.contextService,
                settings: viewModel.settings,
                sessionContext: viewModel.sessionContext
            )
            .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    @ViewBuilder
    private var detailContent: some View {
        if selectedSection == .chat {
            chatDetailView
        } else {
            KanbanWorkspaceView()
        }
    }

    @ViewBuilder
    private var chatDetailView: some View {
        VStack(spacing: 0) {
            // Status bar
            if viewModel.interactionState != .idle {
                StatusBarView(
                    interactionState: viewModel.interactionState,
                    sessionState: viewModel.sessionState,
                    processingSubState: viewModel.processingSubState,
                    currentToolName: viewModel.currentToolName,
                    partialTranscript: viewModel.partialTranscript,
                    lastInputTokens: viewModel.lastInputTokens,
                    lastOutputTokens: viewModel.lastOutputTokens,
                    contextWindowTokens: viewModel.contextWindowTokens
                )
            }

            // System health bar (always visible)
            SystemHealthBarView(
                settings: viewModel.settings,
                metricsCollector: viewModel.metricsCollector,
                heartbeatService: heartbeatService,
                supabaseService: supabaseService,
                isOfflineFallbackActive: viewModel.isOfflineFallbackActive,
                localServerStatus: viewModel.localServerStatus,
                onModelTap: { showQuickModelPopover = true },
                onSyncTap: { showSystemStatusSheet = true },
                onHeartbeatTap: { showSystemStatusSheet = true },
                onTokenTap: { showSystemStatusSheet = true }
            )
            .popover(isPresented: $showQuickModelPopover) {
                QuickModelPopoverView(
                    settings: viewModel.settings,
                    keychainService: viewModel.keychainService,
                    isOfflineFallbackActive: viewModel.isOfflineFallbackActive
                )
            }

            // Tool confirmation banner
            if let confirmation = viewModel.pendingToolConfirmation {
                ToolConfirmationBannerView(
                    toolName: confirmation.toolName,
                    toolDescription: confirmation.toolDescription,
                    onApprove: { viewModel.respondToToolConfirmation(approved: true) },
                    onDeny: { viewModel.respondToToolConfirmation(approved: false) }
                )
            }

            // Offline fallback banner
            if viewModel.isOfflineFallbackActive {
                OfflineFallbackBannerView(
                    modelName: viewModel.settings.llmModel,
                    onRestore: { viewModel.restoreOriginalModel() }
                )
            }

            // TTS fallback banner
            if viewModel.isTTSFallbackActive {
                TTSFallbackBannerView(
                    providerName: viewModel.ttsFallbackProviderName ?? "로컬",
                    onRestore: { viewModel.restoreTTSProvider() }
                )
            }

            // UX-8: System prompt banner
            SystemPromptBannerView(contextService: viewModel.contextService)

            // Error banner
            if let error = viewModel.errorMessage {
                ErrorBannerView(message: error) {
                    viewModel.errorMessage = nil
                }
            }

            // Avatar view
            if viewModel.settings.avatarEnabled {
                if #available(macOS 15.0, *) {
                    AvatarView(
                        interactionState: viewModel.interactionState
                    )
                    .frame(height: 250)
                }
            }

            // Conversation area
            if viewModel.currentConversation == nil || (viewModel.currentConversation?.messages.isEmpty == true) {
                EmptyConversationView(
                    onSelectPrompt: { prompt in
                        viewModel.inputText = prompt
                        viewModel.sendMessage()
                    },
                    onShowCatalog: { showCapabilityCatalog = true },
                    onCreateAgent: { showAgentWizard = true },
                    onShowTour: { showFeatureTour = true },
                    agentCount: viewModel.contextService.listAgents(workspaceId: viewModel.sessionContext.workspaceId).count,
                    isFirstConversation: viewModel.conversations.isEmpty
                )
            } else {
                ConversationView(
                    messages: viewModel.currentConversation?.messages ?? [],
                    streamingText: viewModel.streamingText,
                    currentToolName: viewModel.currentToolName,
                    processingSubState: viewModel.processingSubState,
                    fontSize: viewModel.settings.chatFontSize,
                    toolExecutions: viewModel.toolExecutions
                )
            }

            Divider()

            // Input area
            if viewModel.currentConversation?.source == .telegram {
                TelegramReadOnlyBarView()
            } else {
                InputBarView(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var hiddenShortcutButtons: some View {
        Group {
            // ⌘E: Export conversation
            Button("") {
                if let id = viewModel.currentConversation?.id {
                    viewModel.exportConversation(id: id, format: .markdown)
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .hidden()

            // ⌘/: Shortcut help
            Button("") {
                showShortcutHelp.toggle()
            }
            .keyboardShortcut("/", modifiers: .command)
            .hidden()

            // ⌘⇧A: Agent switcher
            Button("") {
                showAgentSwitcher = true
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .hidden()

            // ⌘⇧W: Workspace switcher
            Button("") {
                showWorkspaceSwitcher = true
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .hidden()

            // ⌘⇧T: Toggle all tool cards (UX-7)
            Button("") {
                viewModel.toggleAllToolCards()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .hidden()

            // ⌘⇧U: User switcher
            Button("") {
                showUserSwitcher = true
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .hidden()

            // ⌘⌥I: Context inspector sheet (기존)
            Button("") {
                showContextInspector = true
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .hidden()
        }
    }

    // MARK: - Key Press Handler

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let hasCommand = press.modifiers.contains(.command)
        let hasShift = press.modifiers.contains(.shift)
        let chars = press.characters

        // ⌘⇧K: Toggle kanban/chat (check before ⌘K)
        if hasCommand && hasShift && chars == "k" {
            selectedSection = selectedSection == .chat ? .kanban : .chat
            return .handled
        }

        // ⌘⇧L: Toggle favorites filter
        if hasCommand && hasShift && chars == "l" {
            viewModel.toggleFavoritesFilter()
            return .handled
        }

        // ⌘⇧M: Quick model popover (UX-10)
        if hasCommand && hasShift && chars == "m" {
            showQuickModelPopover.toggle()
            return .handled
        }

        // ⌘K: Command palette
        if hasCommand && !hasShift && chars == "k" {
            withAnimation(.easeOut(duration: 0.15)) {
                showCommandPalette.toggle()
            }
            return .handled
        }

        // ⌘1~9: Switch conversation by index
        if hasCommand && !hasShift, chars.count == 1,
           let digit = Int(chars), digit >= 1, digit <= 9 {
            viewModel.selectConversationByIndex(digit)
            return .handled
        }

        return .ignored
    }

    // MARK: - Palette Items

    private var paletteItems: [CommandPaletteItem] {
        let wsId = viewModel.sessionContext.workspaceId
        return CommandPaletteRegistry.allItems(
            conversations: viewModel.conversations,
            agents: viewModel.contextService.listAgents(workspaceId: wsId),
            workspaceIds: viewModel.contextService.listLocalWorkspaces(),
            profiles: viewModel.userProfiles,
            currentAgentName: viewModel.settings.activeAgentName,
            currentWorkspaceId: wsId,
            currentUserId: viewModel.sessionContext.currentUserId
        )
    }

    // MARK: - Palette Action Execution

    private func executePaletteAction(_ action: CommandPaletteItem.PaletteAction) {
        switch action {
        case .newConversation:
            viewModel.newConversation()
        case .selectConversation(let id):
            selectedSection = .chat
            viewModel.selectConversation(id: id)
        case .switchAgent(let name):
            viewModel.switchAgent(name: name)
        case .openSettings:
            // macOS handles ⌘, natively via Settings scene
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .openContextInspector:
            showContextInspector = true
        case .openMemoryPanel:
            showMemoryPanel.toggle()
        case .openCapabilityCatalog:
            showCapabilityCatalog = true
        case .openSystemStatus:
            showSystemStatusSheet = true
        case .openShortcutHelp:
            showShortcutHelp = true
        case .exportConversation:
            if let id = viewModel.currentConversation?.id {
                viewModel.exportConversation(id: id, format: .markdown)
            }
        case .openExportOptions:
            if viewModel.currentConversation != nil {
                showExportOptions = true
            }
        case .toggleKanban:
            selectedSection = selectedSection == .chat ? .kanban : .chat
        case .openTagManagement:
            showTagManagementFromPalette = true
        case .toggleMultiSelect:
            viewModel.toggleMultiSelectMode()
        case .createAgent:
            showAgentWizard = true
        case .openFeatureTour:
            viewModel.settings.resetFeatureTour()
            showFeatureTour = true
        case .resetHints:
            viewModel.settings.resetAllHints()
            HintManager.shared.resetAllHints()
        case .openQuickModelPopover:
            showQuickModelPopover = true
        case .openSettingsSection:
            // Open settings window (the section deep-link is handled by Settings scene)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .custom(let id):
            if id.hasPrefix("switchUser-") {
                let userIdStr = String(id.dropFirst("switchUser-".count))
                if let profile = viewModel.userProfiles.first(where: { $0.id.uuidString == userIdStr }) {
                    viewModel.switchUser(profile: profile)
                }
            }
        }
    }

    // MARK: - Quick Switcher Sheets

    /// Helper struct for workspace items in QuickSwitcher
    private struct WorkspaceItem: Identifiable {
        let id: UUID
        var displayName: String {
            if id == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
                return "기본 워크스페이스"
            }
            return String(id.uuidString.prefix(8)) + "..."
        }
    }

    /// Helper struct for agent items in QuickSwitcher
    private struct AgentItem: Identifiable {
        let id: String
        let name: String
    }

    @ViewBuilder
    private var agentSwitcherSheet: some View {
        let wsId = viewModel.sessionContext.workspaceId
        let agents = viewModel.contextService.listAgents(workspaceId: wsId)
            .map { AgentItem(id: $0, name: $0) }

        QuickSwitcherView(
            title: "에이전트 전환",
            items: agents,
            currentId: viewModel.settings.activeAgentName,
            label: { $0.name },
            icon: { $0.name == viewModel.settings.activeAgentName ? "person.fill.checkmark" : "person.fill" },
            onSelect: { viewModel.switchAgent(name: $0.name) }
        )
    }

    @ViewBuilder
    private var workspaceSwitcherSheet: some View {
        let workspaces = viewModel.contextService.listLocalWorkspaces()
            .map { WorkspaceItem(id: $0) }

        QuickSwitcherView(
            title: "워크스페이스 전환",
            items: workspaces,
            currentId: viewModel.sessionContext.workspaceId,
            label: { $0.displayName },
            icon: { $0.id == viewModel.sessionContext.workspaceId ? "square.grid.2x2.fill" : "square.grid.2x2" },
            onSelect: { viewModel.switchWorkspace(id: $0.id) }
        )
    }

    @ViewBuilder
    private var userSwitcherSheet: some View {
        QuickSwitcherView(
            title: "사용자 전환",
            items: viewModel.userProfiles,
            currentId: viewModel.sessionContext.currentUserId.flatMap { UUID(uuidString: $0) },
            label: { $0.name },
            icon: { profile in
                profile.id.uuidString == viewModel.sessionContext.currentUserId
                    ? "person.crop.circle.fill.badge.checkmark"
                    : "person.crop.circle"
            },
            onSelect: { viewModel.switchUser(profile: $0) }
        )
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var viewModel: DochiViewModel
    var supabaseService: SupabaseServiceProtocol?
    @Binding var selectedSection: ContentView.MainSection
    @State private var searchText: String = ""
    @State private var showFilterPopover = false
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showTagManagement = false

    private var filteredConversations: [Conversation] {
        var result = viewModel.conversations

        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { conversation in
                conversation.title.lowercased().contains(query) ||
                conversation.messages.contains { $0.content.lowercased().contains(query) }
            }
        }

        // Filter
        if viewModel.conversationFilter.isActive {
            result = result.filter { viewModel.conversationFilter.matches($0) }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeaderView(viewModel: viewModel)

            Divider()

            Picker("", selection: $selectedSection) {
                ForEach(ContentView.MainSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .pickerStyle(.segmented)

            if selectedSection == .chat {
                // Header with search + filter + multi-select
                ConversationListHeaderView(
                    searchText: $searchText,
                    filter: $viewModel.conversationFilter,
                    showFilterPopover: $showFilterPopover,
                    viewModel: viewModel
                )
                .popover(isPresented: $showFilterPopover) {
                    ConversationFilterView(
                        filter: $viewModel.conversationFilter,
                        tags: viewModel.conversationTags
                    )
                }

                // Active filter chips
                ConversationFilterChipsView(filter: $viewModel.conversationFilter)

                // Conversation list
                ConversationListView(
                    viewModel: viewModel,
                    conversations: filteredConversations,
                    filter: $viewModel.conversationFilter,
                    selectedSection: $selectedSection
                )

                // Bulk action toolbar
                BulkActionToolbarView(viewModel: viewModel)

                // Folder creation / Tag management
                HStack(spacing: 6) {
                    Button {
                        showNewFolderAlert = true
                    } label: {
                        Label("폴더", systemImage: "folder.badge.plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button {
                        showTagManagement = true
                    } label: {
                        Label("태그", systemImage: "tag")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .alert("새 폴더", isPresented: $showNewFolderAlert) {
                    TextField("폴더 이름", text: $newFolderName)
                    Button("취소", role: .cancel) { newFolderName = "" }
                    Button("생성") {
                        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            viewModel.addFolder(ConversationFolder(name: name))
                        }
                        newFolderName = ""
                    }
                }
                .sheet(isPresented: $showTagManagement) {
                    TagManagementView(viewModel: viewModel)
                }

                // Auth/sync status
                if let service = supabaseService, service.authState.isSignedIn {
                    Divider()
                    SidebarAuthStatusView(authState: service.authState)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("칸반 보드", systemImage: "rectangle.3.group")
                        .font(.system(size: 13, weight: .semibold))
                    Text("오른쪽 패널에서 보드/카드를 직접 관리할 수 있습니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                Spacer()
            }
        }
        .toolbar {
            if selectedSection == .chat {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.newConversation()
                    } label: {
                        Label("새 대화", systemImage: "plus")
                    }
                    .help("새 대화 (⌘N)")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
        .onAppear {
            viewModel.loadOrganizationData()
        }
    }
}

// MARK: - Sidebar Auth Status

struct SidebarAuthStatusView: View {
    let authState: AuthState

    var body: some View {
        VStack(spacing: 4) {
            if case .signedIn(_, let email) = authState {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text(email ?? "로그인됨")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    let interactionState: InteractionState
    let sessionState: SessionState
    let processingSubState: ProcessingSubState?
    let currentToolName: String?
    let partialTranscript: String
    var lastInputTokens: Int?
    var lastOutputTokens: Int?
    var contextWindowTokens: Int = 128_000

    private var usedTokens: Int {
        (lastInputTokens ?? 0) + (lastOutputTokens ?? 0)
    }

    private var tokenRatio: Double {
        guard contextWindowTokens > 0 else { return 0 }
        return Double(lastInputTokens ?? 0) / Double(contextWindowTokens)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
                .frame(width: 14, height: 14)

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            // Token usage indicator (from last API response)
            if let input = lastInputTokens {
                HStack(spacing: 3) {
                    Text("\(formatTokens(input))/\(formatTokens(contextWindowTokens))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(tokenRatio < 0.5 ? .green : tokenRatio < 0.75 ? .orange : .red)
                    if let output = lastOutputTokens {
                        Text("(+\(formatTokens(output)))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if sessionState == .active {
                Text("연속 대화")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if sessionState == .ending {
                Text("종료 대기")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch interactionState {
        case .listening:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .font(.system(size: 10))
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 10))
        default:
            ProgressView()
                .scaleEffect(0.6)
        }
    }

    private var statusText: String {
        switch interactionState {
        case .listening:
            if !partialTranscript.isEmpty {
                return partialTranscript
            }
            return "듣고 있습니다..."
        case .speaking:
            return "말하는 중..."
        case .processing:
            switch processingSubState {
            case .streaming: return "응답 생성 중..."
            case .toolCalling:
                if let name = currentToolName { return "도구 실행 중: \(name)" }
                return "도구 실행 중..."
            case .toolError: return "도구 오류 — 재시도 중..."
            case .complete: return "완료"
            case nil: return "처리 중..."
            }
        case .idle:
            return ""
        }
    }
}

// MARK: - Tool Confirmation Banner

struct ToolConfirmationBannerView: View {
    let toolName: String
    let toolDescription: String
    let onApprove: () -> Void
    let onDeny: () -> Void
    let timeoutSeconds: TimeInterval

    @State private var remainingSeconds: Int
    @State private var timerActive = true
    @State private var showTimeoutMessage = false

    init(toolName: String, toolDescription: String, onApprove: @escaping () -> Void, onDeny: @escaping () -> Void, timeoutSeconds: TimeInterval = 30) {
        self.toolName = toolName
        self.toolDescription = toolDescription
        self.onApprove = onApprove
        self.onDeny = onDeny
        self.timeoutSeconds = timeoutSeconds
        self._remainingSeconds = State(initialValue: Int(timeoutSeconds))
    }

    private var isUrgent: Bool { remainingSeconds <= 10 }
    private var progress: Double { Double(remainingSeconds) / timeoutSeconds }

    var body: some View {
        if showTimeoutMessage {
            timeoutMessageView
        } else {
            bannerContent
        }
    }

    private var bannerContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(toolName)")
                    .font(.system(size: 12, weight: .semibold))
                Text(toolDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Countdown timer badge
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(isUrgent ? Color.red : Color.orange, lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remainingSeconds)
                Text("\(remainingSeconds)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isUrgent ? .red : .secondary)
            }

            Button {
                timerActive = false
                onDeny()
            } label: {
                Text("거부")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)

            Button {
                timerActive = false
                onApprove()
            } label: {
                Text("허용")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isUrgent ? Color.red.opacity(0.12) : Color.orange.opacity(0.08))
        .animation(.easeInOut(duration: 0.3), value: isUrgent)
        .onAppear {
            startCountdown()
        }
    }

    private var timeoutMessageView: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.xmark")
                .foregroundStyle(.red)
            Text("시간 초과로 자동 거부됨")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .transition(.opacity)
    }

    private func startCountdown() {
        Task { @MainActor in
            while timerActive && remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard timerActive else { return }
                remainingSeconds -= 1
            }

            guard timerActive else { return }
            timerActive = false

            // Timeout reached — show message then deny
            withAnimation(.easeInOut(duration: 0.3)) {
                showTimeoutMessage = true
            }

            // Brief delay so user sees the timeout message
            try? await Task.sleep(for: .seconds(2))

            // Notify ViewModel to auto-deny (also cancels ViewModel's timeout task)
            onDeny()
        }
    }
}

// MARK: - Error Banner

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Input Bar

struct InputBarView: View {
    @Bindable var viewModel: DochiViewModel
    @State private var showSlashCommands = false

    private var matchingCommands: [SlashCommand] {
        FeatureCatalog.matchingCommands(for: viewModel.inputText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 슬래시 명령 팝업
            if showSlashCommands && !matchingCommands.isEmpty {
                SlashCommandPopoverView(
                    commands: matchingCommands,
                    onSelect: { command in
                        applySlashCommand(command)
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                // Microphone button (voice mode)
                if viewModel.isVoiceMode {
                    microphoneButton
                }

                TextField("메시지 입력... \u{2318}K 빠른 명령 \u{00B7} /로 명령어", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(8)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            if showSlashCommands && !matchingCommands.isEmpty {
                                applySlashCommand(matchingCommands[0])
                            } else {
                                viewModel.sendMessage()
                            }
                        }
                    }
                    .onChange(of: viewModel.inputText) { _, newValue in
                        withAnimation(.easeOut(duration: 0.15)) {
                            showSlashCommands = newValue.hasPrefix("/") && viewModel.interactionState == .idle
                        }
                    }

                if viewModel.interactionState == .processing {
                    Button {
                        viewModel.cancelRequest()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("취소")
                } else if viewModel.interactionState == .speaking {
                    Button {
                        viewModel.handleBargeIn()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("말하기 중단")
                } else {
                    Button {
                        viewModel.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(canSend ? Color.accentColor : .secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("전송")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var microphoneButton: some View {
        if viewModel.interactionState == .listening {
            Button {
                viewModel.stopListening()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("듣기 중지")
        } else if viewModel.interactionState == .idle {
            Button {
                viewModel.startListening()
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("음성 입력")
        }
    }

    private var canSend: Bool {
        viewModel.interactionState == .idle &&
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applySlashCommand(_ command: SlashCommand) {
        showSlashCommands = false
        if command.name == "/도움말" {
            // 도움말은 특별 처리 — 카탈로그 열기가 아닌 간단한 안내 메시지
            viewModel.inputText = "사용 가능한 기능 전체 목록 보여줘"
        } else if !command.example.isEmpty {
            viewModel.inputText = command.example
        } else {
            viewModel.inputText = command.description
        }
        viewModel.sendMessage()
    }
}

// MARK: - Empty Conversation View

struct EmptyConversationView: View {
    let onSelectPrompt: (String) -> Void
    var onShowCatalog: (() -> Void)?
    var onCreateAgent: (() -> Void)?
    var onShowTour: (() -> Void)?
    var agentCount: Int = 1
    var isFirstConversation: Bool = false

    private var contextualSuggestions: [FeatureSuggestion] {
        FeatureCatalog.contextualSuggestions()
    }

    /// 투어를 건너뛴 사용자를 위한 재안내 배너 표시 여부
    private var showTourBanner: Bool {
        UserDefaults.standard.bool(forKey: "featureTourSkipped")
        && !UserDefaults.standard.bool(forKey: "featureTourBannerDismissed")
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // 투어 재안내 배너
            if showTourBanner, let onShowTour {
                tourReminderBanner(onShowTour: onShowTour)
            }

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("대화를 시작해보세요")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("아래에서 골라보거나, 자유롭게 입력하세요. / 로 시작하면 명령 목록이 나타납니다.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .hintBubble(
                    id: "firstConversation",
                    title: "첫 대화를 시작해보세요",
                    message: "아래 제안을 클릭하거나, 궁금한 것을 자유롭게 입력하세요. /로 시작하면 명령 목록도 볼 수 있어요.",
                    edge: .bottom,
                    condition: isFirstConversation
                )

            // Agent hint card (when no agents)
            if agentCount == 0, let onCreateAgent {
                agentHintCard(onCreateAgent: onCreateAgent)
            }

            // 카테고리별 제안
            HStack(alignment: .top, spacing: 12) {
                ForEach(contextualSuggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.accentColor)
                            Text(suggestion.category)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(suggestion.prompts, id: \.self) { prompt in
                            Button {
                                onSelectPrompt(prompt)
                            } label: {
                                Text(prompt)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.quaternary.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 200)
                }
            }
            .padding(.horizontal, 20)

            // 기능 카탈로그 링크 + 단축키 힌트
            VStack(spacing: 6) {
                if let onShowCatalog {
                    Button {
                        onShowCatalog()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 11))
                            Text("모든 기능 보기")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Text("\u{2318}K로 빠른 명령, \u{2318}/로 모든 단축키를 확인하세요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func tourReminderBanner(onShowTour: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
                .font(.system(size: 14))

            Text("기능 투어를 아직 보지 않았어요.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("둘러보기") {
                onShowTour()
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            Button {
                UserDefaults.standard.set(true, forKey: "featureTourBannerDismissed")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private func agentHintCard(onCreateAgent: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                Text("에이전트를 만들어보세요")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("템플릿으로 코딩, 리서치, 일정 관리 등 특화된 AI 비서를 빠르게 구성할 수 있습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onCreateAgent()
            } label: {
                Text("에이전트 만들기")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 40)
    }
}

// MARK: - Offline Fallback Banner

struct OfflineFallbackBannerView: View {
    let modelName: String
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            Text("인터넷 연결이 끊어져 로컬 모델로 전환되었습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(modelName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.orange)

            Spacer()

            Button("원래 모델로 복구") {
                onRestore()
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - TTS Fallback Banner

struct TTSFallbackBannerView: View {
    let providerName: String
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.circle")
                .foregroundStyle(.purple)
                .font(.system(size: 12))

            Text("음성 합성: \(providerName)로 전환됨")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button("원래 TTS로 복구") {
                onRestore()
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.1))
    }
}

// MARK: - Telegram Read-Only Bar

struct TelegramReadOnlyBarView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("텔레그램 대화는 읽기 전용입니다")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
