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
        }
        // Hidden buttons for keyboard shortcuts
        .background { hiddenShortcutButtons }
        // Keyboard shortcut: Escape to cancel or close palette
        .onKeyPress(.escape) {
            if showCommandPalette {
                showCommandPalette = false
                return .handled
            }
            if selectedSection == .chat, viewModel.interactionState == .processing {
                viewModel.cancelRequest()
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
                                    showContextInspector = true
                                } label: {
                                    Label("컨텍스트", systemImage: "doc.text.magnifyingglass")
                                }
                                .help("컨텍스트 인스펙터 (⌘I)")
                                .keyboardShortcut("i", modifiers: .command)
                            }
                        }
                    }
                }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
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
                onTap: { showSystemStatusSheet = true }
            )

            // Tool confirmation banner
            if let confirmation = viewModel.pendingToolConfirmation {
                ToolConfirmationBannerView(
                    toolName: confirmation.toolName,
                    toolDescription: confirmation.toolDescription,
                    onApprove: { viewModel.respondToToolConfirmation(approved: true) },
                    onDeny: { viewModel.respondToToolConfirmation(approved: false) }
                )
            }

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
                    onShowCatalog: { showCapabilityCatalog = true }
                )
            } else {
                ConversationView(
                    messages: viewModel.currentConversation?.messages ?? [],
                    streamingText: viewModel.streamingText,
                    currentToolName: viewModel.currentToolName,
                    processingSubState: viewModel.processingSubState,
                    fontSize: viewModel.settings.chatFontSize
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

            // ⌘⇧U: User switcher
            Button("") {
                showUserSwitcher = true
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
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

        // ⌘⇧M: Toggle multi-select mode
        if hasCommand && hasShift && chars == "m" {
            viewModel.toggleMultiSelectMode()
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
        case .toggleKanban:
            selectedSection = selectedSection == .chat ? .kanban : .chat
        case .openTagManagement:
            showTagManagementFromPalette = true
        case .toggleMultiSelect:
            viewModel.toggleMultiSelectMode()
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
    @State private var filter: ConversationFilter = ConversationFilter()
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
        if filter.isActive {
            result = result.filter { filter.matches($0) }
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
                    filter: $filter,
                    showFilterPopover: $showFilterPopover,
                    viewModel: viewModel
                )
                .popover(isPresented: $showFilterPopover) {
                    ConversationFilterView(
                        filter: $filter,
                        tags: viewModel.conversationTags
                    )
                }

                // Active filter chips
                ConversationFilterChipsView(filter: $filter)

                // Conversation list
                ConversationListView(
                    viewModel: viewModel,
                    conversations: filteredConversations,
                    filter: filter,
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

    var body: some View {
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

            Button {
                onDeny()
            } label: {
                Text("거부")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)

            Button {
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
        .background(Color.orange.opacity(0.08))
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

    private var contextualSuggestions: [FeatureSuggestion] {
        FeatureCatalog.contextualSuggestions()
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

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
