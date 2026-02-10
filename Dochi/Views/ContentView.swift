import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: DochiViewModel

    // Settings moved to ViewModel toggle for command palette access
    @State private var showChangelog = false
    @State private var showOnboarding = false

    private let changelogService = ChangelogService()
    @State private var splitVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            SidebarView(showSettings: $viewModel.showSettingsSheet)
        } detail: {
            VStack(spacing: 0) {
                ConversationView()
                Divider()
                InputBar()
                    .environmentObject(viewModel)
            }
            .safeAreaInset(edge: .top) {
                AppToolbar()
                    .environmentObject(viewModel)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $viewModel.showSettingsSheet) {
            SettingsView()
                .accessibilityIdentifier("sheet.settings")
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogView(changelogService: changelogService, showFullChangelog: false)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onAppear {
            splitVisibility = .all
            let isUITest = ProcessInfo.processInfo.arguments.contains("-uiTest") || ProcessInfo.processInfo.environment["UITEST"] == "1"
            if !isUITest {
                if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                    viewModel.connectOnLaunch()
                    checkForNewVersion()
                }
            }
        }
        .overlay(alignment: .center) {
            if viewModel.showCommandPalette {
                CommandPaletteView()
                    .environmentObject(viewModel)
                    .padding(.top, 40)
            }
        }
    }

    private func checkForNewVersion() {
        if changelogService.hasNewVersion {
            // 약간 딜레이 후 표시 (앱 로딩 완료 후)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showChangelog = true
            }
        } else if changelogService.isFirstLaunch {
            changelogService.markCurrentVersionAsSeen()
            // 첫 실행 시 온보딩 표시
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showOnboarding = true
            }
        }
    }

}

// MARK: - Wake Word Indicator

struct WakeWordIndicator: View {
    let wakeWord: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.mint.opacity(0.25))
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
                Image(systemName: "ear")
                    .font(.caption)
                    .foregroundStyle(.mint)
            }
            Text("\"\(wakeWord)\" 대기 중")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .onDisappear { pulse = false }
    }
}

// MARK: - Active Alarms Bar

struct ActiveAlarmsBar: View {
    @EnvironmentObject var viewModel: DochiViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 8) {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                ForEach(viewModel.builtInToolService.activeAlarms) { alarm in
                    HStack(spacing: 4) {
                        Text(alarm.label)
                            .font(.caption)
                            .lineLimit(1)
                        Text(remainingText(alarm.fireDate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.1), in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    private func remainingText(_ fireDate: Date) -> String {
        let remaining = max(0, Int(fireDate.timeIntervalSinceNow))
        if remaining >= 3600 {
            let h = remaining / 3600
            let m = (remaining % 3600) / 60
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", remaining % 60))"
        } else if remaining >= 60 {
            let m = remaining / 60
            let s = remaining % 60
            return "\(m):\(String(format: "%02d", s))"
        } else {
            return "\(remaining)초"
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Binding var showSettings: Bool
    @State private var showSystemEditor = false
    @State private var showBasePromptEditor = false
    @State private var showAgentPersonaEditor = false
    @State private var showMemoryEditor = false
    @State private var showFamilyMemoryEditor = false
    @State private var showAgentMemoryEditor = false
    @State private var editingUserMemoryProfile: UserProfile?

    private var contextService: ContextServiceProtocol {
        viewModel.settings.contextService
    }

    @State private var query: String = ""

    // Accordion open states
    // Removed 요약: 상단 앱바로 요약 이동
    @State private var openChats: Bool = true
    @State private var openAgents: Bool = true
    @State private var openMemory: Bool = false
    @State private var openTools: Bool = false
    @State private var openCloud: Bool = false
    @State private var openDevices: Bool = false

    var body: some View {
        List {
            // Search
            SectionHeader("검색", compact: true)
            HStack(spacing: rowSpacing) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("대화 검색...", text: $query)
            }
            .padding(.horizontal, rowPaddingH)
            .padding(.vertical, rowPaddingV)

            // Expand/Collapse helpers
            HStack(spacing: 8) {
                Button("모두 펼치기") { setAllOpen(true) }
                Button("모두 접기") { setAllOpen(false) }
                Spacer()
            }
            .compact(AppFont.caption)
            .padding(.horizontal, rowPaddingH)
            .padding(.vertical, AppSpacing.xs)

            // Accordion sections
            DisclosureGroup("대화", isExpanded: $openChats) { chatsGroup }
            DisclosureGroup("에이전트", isExpanded: $openAgents) { agentsGroup }
            DisclosureGroup("기억", isExpanded: $openMemory) { memoryGroup }
            DisclosureGroup("도구", isExpanded: $openTools) { toolsGroup }
            DisclosureGroup("클라우드", isExpanded: $openCloud) { cloudGroup }
            DisclosureGroup("디바이스", isExpanded: $openDevices) { devicesGroup }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(AppColor.background)
        .environment(\.defaultMinListRowHeight, minRowHeight)
        .sheet(isPresented: $showSystemEditor) { SystemEditorView(contextService: contextService) }
        .sheet(isPresented: $showBasePromptEditor) { BasePromptEditorView(contextService: contextService) }
        .sheet(isPresented: $showAgentPersonaEditor) { AgentPersonaEditorView(contextService: contextService, agentName: viewModel.settings.activeAgentName) }
        .sheet(isPresented: $showAgentMemoryEditor) { AgentMemoryEditorView(contextService: contextService, agentName: viewModel.settings.activeAgentName) }
        .sheet(isPresented: $showMemoryEditor) { MemoryEditorView(contextService: contextService) }
        .sheet(isPresented: $showFamilyMemoryEditor) { FamilyMemoryEditorView(contextService: contextService) }
        .sheet(item: $editingUserMemoryProfile) { profile in UserMemoryEditorView(contextService: contextService, profile: profile) }
        .safeAreaInset(edge: .bottom) {
            Button { showSettings = true } label: {
                Label("설정", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, rowPaddingH)
                    .padding(.vertical, rowPaddingV)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("open.settings")
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }
}

// MARK: - Density helpers
private extension SidebarView {
    var isCompact: Bool { viewModel.settings.uiDensity == .compact }
    var rowPaddingH: CGFloat { isCompact ? AppSpacing.s : AppSpacing.s }
    var rowPaddingV: CGFloat { isCompact ? AppSpacing.xs : AppSpacing.s }
    var rowSpacing: CGFloat { isCompact ? AppSpacing.s : AppSpacing.s }
    var minRowHeight: CGFloat { isCompact ? 26 : 32 }

    func setAllOpen(_ v: Bool) {
        openChats = v; openAgents = v; openMemory = v; openTools = v; openCloud = v; openDevices = v
    }
}

// MARK: - Tab content builders
private extension SidebarView {
    // Removed homeGroup: 요약 정보는 앱바로 이동

    var toolsGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            if let name = viewModel.currentToolExecution { HStack { Image(systemName: "bolt.fill").foregroundStyle(.cyan); Text("\(name) 실행 중…"); Spacer(); ProgressView().controlSize(.small) } }
            if let enabled = viewModel.builtInToolService.getEnabledToolNames(), !enabled.isEmpty {
                HStack { Text("사용 중인 도구 ("); Text("\(enabled.count)").bold(); Text(")"); Spacer() }
                let list = Array(enabled.prefix(8)).joined(separator: ", ") + (enabled.count > 8 ? "…" : "")
                Text(list).font(.caption).foregroundStyle(.secondary)
            } else { Text("최근 실행 중인 도구 없음").font(.caption).foregroundStyle(.secondary) }
            if !viewModel.mcpService.availableTools.isEmpty { Text("MCP 도구 \(viewModel.mcpService.availableTools.count)개").font(.caption) }
            // Catalog by category with enable toggles
            let catalog = viewModel.builtInToolService.toolCatalogByCategory()
            let currentEnabled = Set(viewModel.builtInToolService.getEnabledToolNames() ?? [])
            ForEach(catalog.keys.sorted(), id: \.self) { category in
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.uppercased()).compact(AppFont.caption).foregroundStyle(.secondary)
                    ForEach(catalog[category] ?? [], id: \.self) { toolName in
                        Toggle(isOn: Binding(
                            get: { currentEnabled.contains(toolName) },
                            set: { on in
                                var new = currentEnabled
                                if on { new.insert(toolName) } else { new.remove(toolName) }
                                viewModel.builtInToolService.setEnabledToolNames(Array(new))
                            }
                        )) {
                            Text(toolName).compact(AppFont.caption)
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(.leading, 2)
                }
                .padding(.vertical, 2)
            }
            Text("참고: 기본 제공 도구는 항상 활성입니다. 여기서는 추가 활성 도구를 설정합니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button { showSettings = true } label: { Label("도구 관리 열기", systemImage: "slider.horizontal.3") }.buttonStyle(.plain)
        }
    }

    var cloudGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            if let supabase = viewModel.supabaseServiceForView, supabase.isConfigured {
                switch supabase.authState {
                case .signedOut: HStack { Image(systemName: "person.crop.circle.badge.exclam"); Text("로그인 필요").foregroundStyle(.secondary) }
                case .signedIn(_, let email): VStack(alignment: .leading, spacing: 4) { HStack { Image(systemName: "person.crop.circle"); Text(email ?? "로그인됨"); Spacer() }; if let ws = supabase.selectedWorkspace { Text("워크스페이스: \(ws.name)").font(.caption).foregroundStyle(.secondary) } }
                }
            } else { Text("Supabase 설정이 필요합니다").font(.caption).foregroundStyle(.secondary) }
            if let device = viewModel.deviceServiceForView, let current = device.currentDevice { HStack(spacing: 6) { Circle().fill(current.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8); Text(current.deviceName); Spacer() } }
            HStack { Button { showSettings = true } label: { Label("클라우드/디바이스 관리", systemImage: "gear") }; Spacer(); if let supabase = viewModel.supabaseServiceForView, case .signedIn = supabase.authState { Button("워크스페이스 전환/참가") { showSettings = true }.buttonStyle(.plain) } }.buttonStyle(.plain)
        }
    }

    var chatsGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Button { viewModel.clearConversation() } label: { Label("새 대화", systemImage: "plus.circle") }
                Spacer()
                if !viewModel.messages.isEmpty {
                    Text("현재 메시지: \(viewModel.messages.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if viewModel.conversations.isEmpty { Text("저장된 대화가 없습니다").font(.caption).foregroundStyle(.secondary) }
            else {
                ForEach(viewModel.conversations.filter { query.isEmpty ? true : $0.title.lowercased().contains(query.lowercased()) }) { conv in
                    Button { viewModel.loadConversation(conv) } label: {
                        HStack { VStack(alignment: .leading, spacing: 2) { Text(conv.title).lineLimit(1); Text(conv.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary) }; Spacer(); if viewModel.currentConversationId == conv.id { Image(systemName: "checkmark").font(.caption).foregroundStyle(.blue) } }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button(role: .destructive) { viewModel.deleteConversation(id: conv.id) } label: { Label("삭제", systemImage: "trash") } }
                }
            }
        }
    }

    var agentsGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            let agents = contextService.listAgents()
            if agents.isEmpty { Text("등록된 에이전트가 없습니다").font(.caption).foregroundStyle(.secondary) }
            else {
                ForEach(agents, id: \.self) { name in
                    Button { viewModel.settings.activeAgentName = name } label: {
                        HStack { Text(name); Spacer(); if viewModel.settings.activeAgentName == name { Image(systemName: "checkmark").foregroundStyle(.blue) } }
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) { Button { showAgentPersonaEditor = true } label: { Label("페르소나 편집", systemImage: "text.badge.star") }; Button { showAgentMemoryEditor = true } label: { Label("에이전트 기억", systemImage: "brain") } }
        }
    }

    var memoryGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Button { showBasePromptEditor = true } label: { HStack { Image(systemName: "doc.text").foregroundStyle(.orange); VStack(alignment: .leading, spacing: 2) { Text("기본 규칙"); let basePrompt = contextService.loadBaseSystemPrompt(); Text(basePrompt.isEmpty ? "설정되지 않음" : basePrompt).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer() } }.buttonStyle(.plain)
            let legacySystem = contextService.loadSystem(); if !legacySystem.isEmpty { Button { showSystemEditor = true } label: { HStack { Image(systemName: "doc.text.fill").foregroundStyle(.secondary); Text("system.md (레거시)"); Spacer() } }.buttonStyle(.plain) }
            let profiles = contextService.loadProfiles()
            if profiles.isEmpty { Button { showMemoryEditor = true } label: { HStack { Image(systemName: "brain").foregroundStyle(.purple); Text("사용자 기억 편집"); Spacer() } }.buttonStyle(.plain) }
            else {
                Button { showFamilyMemoryEditor = true } label: { HStack { Image(systemName: "house").foregroundStyle(.orange); Text("가족 공유 기억 편집"); Spacer() } }.buttonStyle(.plain)
                ForEach(profiles) { profile in Button { editingUserMemoryProfile = profile } label: { HStack { Image(systemName: "person"); Text(profile.name); Spacer() } }.buttonStyle(.plain) }
            }
        }
    }

    var devicesGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            if let device = viewModel.deviceServiceForView, let current = device.currentDevice {
                HStack(spacing: 8) { Circle().fill(current.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8); VStack(alignment: .leading, spacing: 2) { Text(current.deviceName); HStack(spacing: 6) { Text(current.platform).font(.caption).foregroundStyle(.secondary); if !current.capabilities.isEmpty { Text(current.capabilities.joined(separator: ", ")).font(.caption2).foregroundStyle(.tertiary) } } }; Spacer() }
            } else { Text("디바이스 정보 없음").font(.caption).foregroundStyle(.secondary) }
            Button { showSettings = true } label: { Label("디바이스 관리 열기", systemImage: "desktopcomputer") }.buttonStyle(.plain)
        }
    }
    var homeSection: some View {
        Section("개요") {
            // Connection quick toggle
            Button { viewModel.toggleConnection() } label: {
                HStack {
                    Circle().fill(connectionColor).frame(width: 8, height: 8)
                    Text(viewModel.isConnected ? "연결됨" : "연결")
                    Spacer()
                }
            }.buttonStyle(.plain)

            // Model/provider
            HStack {
                Image(systemName: "brain.head.profile").foregroundStyle(.blue)
                Text("\(viewModel.settings.llmProvider.displayName) / \(viewModel.settings.llmModel)")
                    .lineLimit(1)
                Spacer()
            }

            // Context usage
            if let usage = viewModel.actualContextUsage {
                contextUsageRow(usage)
            }

            // Current user
            if let user = viewModel.currentUserName {
                HStack {
                    Image(systemName: "person.circle.fill").foregroundStyle(.green)
                    Text(user)
                    Spacer()
                }
            }

            // Messages count
            if !viewModel.messages.isEmpty {
                HStack {
                    Image(systemName: "text.bubble").foregroundStyle(.secondary)
                    Text("메시지 \(viewModel.messages.count)개")
                    Spacer()
                }
            }

            // Quick actions
            Button { viewModel.clearConversation() } label: { Label("새 대화", systemImage: "plus.circle") }.buttonStyle(.plain)
            Button { showSettings = true } label: { Label("설정", systemImage: "gear") }.buttonStyle(.plain)
        }
    }

    var toolsSection: some View {
        Section("도구") {
            if let name = viewModel.currentToolExecution {
                HStack {
                    Image(systemName: "bolt.fill").foregroundStyle(.cyan)
                    Text("\(name) 실행 중…")
                    Spacer(); ProgressView().controlSize(.small)
                }
            } else {
                Text("최근 실행 중인 도구 없음").font(.caption).foregroundStyle(.secondary)
            }

            // Enabled tools summary (if available)
            if let enabled = viewModel.builtInToolService.getEnabledToolNames(), !enabled.isEmpty {
                HStack { Text("사용 중인 도구 ("); Text("\(enabled.count)").bold(); Text(")"); Spacer() }
                let list = Array(enabled.prefix(8)).joined(separator: ", ") + (enabled.count > 8 ? "…" : "")
                Text(list).font(.caption).foregroundStyle(.secondary)
            }

            if !viewModel.mcpService.availableTools.isEmpty {
                Text("MCP 도구 \(viewModel.mcpService.availableTools.count)개").font(.caption)
            }

            Button { showSettings = true } label: { Label("도구 관리 열기", systemImage: "slider.horizontal.3") }.buttonStyle(.plain)
        }
    }

    var cloudSection: some View {
        Section("클라우드") {
            if let supabase = viewModel.supabaseServiceForView, supabase.isConfigured {
                switch supabase.authState {
                case .signedOut:
                    HStack { Image(systemName: "person.crop.circle.badge.exclam"); Text("로그인 필요").foregroundStyle(.secondary) }
                case .signedIn(_, let email):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Image(systemName: "person.crop.circle"); Text(email ?? "로그인됨"); Spacer() }
                        if let ws = supabase.selectedWorkspace { Text("워크스페이스: \(ws.name)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else {
                Text("Supabase 설정이 필요합니다").font(.caption).foregroundStyle(.secondary)
            }
            // Device brief
            if let device = viewModel.deviceServiceForView, let current = device.currentDevice {
                HStack(spacing: 6) {
                    Circle().fill(current.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8)
                    Text(current.deviceName)
                    Spacer()
                }
            }
            HStack {
                Button { showSettings = true } label: { Label("클라우드/디바이스 관리", systemImage: "gear") }
                Spacer()
                if let supabase = viewModel.supabaseServiceForView, case .signedIn = supabase.authState {
                    Button("워크스페이스 전환/참가") { showSettings = true }.buttonStyle(.plain)
                }
            }.buttonStyle(.plain)
        }
    }

    var agentsSection: some View {
        Section("에이전트") {
            let agents = contextService.listAgents()
            if agents.isEmpty {
                Text("등록된 에이전트가 없습니다").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(agents, id: \.self) { name in
                    Button {
                        viewModel.settings.activeAgentName = name
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            if viewModel.settings.activeAgentName == name {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button { showAgentPersonaEditor = true } label: { Label("페르소나 편집", systemImage: "text.badge.star") }
                Button { showAgentMemoryEditor = true } label: { Label("에이전트 기억", systemImage: "brain") }
            }
        }
    }

    var memorySection: some View {
        Section("기억") {
            // Base rules
            Button { showBasePromptEditor = true } label: {
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("기본 규칙")
                        let basePrompt = contextService.loadBaseSystemPrompt()
                        Text(basePrompt.isEmpty ? "설정되지 않음" : basePrompt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }.buttonStyle(.plain)

            // Legacy system (if any)
            let legacySystem = contextService.loadSystem()
            if !legacySystem.isEmpty {
                Button { showSystemEditor = true } label: {
                    HStack { Image(systemName: "doc.text.fill").foregroundStyle(.secondary); Text("system.md (레거시)"); Spacer() }
                }.buttonStyle(.plain)
            }

            // Memory: personal / family
            let profiles = contextService.loadProfiles()
            if profiles.isEmpty {
                Button { showMemoryEditor = true } label: {
                    HStack { Image(systemName: "brain").foregroundStyle(.purple); Text("사용자 기억 편집"); Spacer() }
                }.buttonStyle(.plain)
            } else {
                Button { showFamilyMemoryEditor = true } label: {
                    HStack { Image(systemName: "house").foregroundStyle(.orange); Text("가족 공유 기억 편집"); Spacer() }
                }.buttonStyle(.plain)
                ForEach(profiles) { profile in
                    Button { editingUserMemoryProfile = profile } label: {
                        HStack { Image(systemName: "person"); Text(profile.name); Spacer() }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    var devicesSection: some View {
        Section("디바이스") {
            if let device = viewModel.deviceServiceForView, let current = device.currentDevice {
                HStack(spacing: 8) {
                    Circle().fill(current.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.deviceName)
                        HStack(spacing: 6) {
                            Text(current.platform).font(.caption).foregroundStyle(.secondary)
                            if !current.capabilities.isEmpty { Text(current.capabilities.joined(separator: ", ")).font(.caption2).foregroundStyle(.tertiary) }
                        }
                    }
                    Spacer()
                }
            } else {
                Text("디바이스 정보 없음").font(.caption).foregroundStyle(.secondary)
            }
            Button { showSettings = true } label: { Label("디바이스 관리 열기", systemImage: "desktopcomputer") }.buttonStyle(.plain)
        }
    }

    var chatsSection: some View {
        Section("대화 기록") {
            if viewModel.conversations.isEmpty {
                Text("저장된 대화가 없습니다").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.conversations.filter { query.isEmpty ? true : $0.title.lowercased().contains(query.lowercased()) }) { conv in
                    Button { viewModel.loadConversation(conv) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conv.title).lineLimit(1)
                                Text(conv.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.currentConversationId == conv.id { Image(systemName: "checkmark").font(.caption).foregroundStyle(.blue) }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button(role: .destructive) { viewModel.deleteConversation(id: conv.id) } label: { Label("삭제", systemImage: "trash") } }
                }
            }
        }
    }

    // Helpers
    func contextUsageRow(_ info: DochiViewModel.ContextUsageInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge").font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(info.percent < 0.8 ? Color.blue.opacity(0.6) : (info.percent < 1.0 ? Color.orange.opacity(0.7) : Color.red.opacity(0.7)))
                    .frame(width: max(0, CGFloat(info.percent)) * 90)
            }
            .frame(width: 90, height: 8)
            Text("\(Int(info.percent * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(info.percent < 0.8 ? Color.secondary : (info.percent < 1.0 ? Color.orange : Color.red))
            Spacer()
        }
    }

    var connectionColor: Color {
        switch viewModel.supertonicService.state {
        case .unloaded: return .red
        case .loading: return .yellow
        case .ready:
            switch viewModel.state {
            case .idle: return .green
            case .listening: return .orange
            case .processing: return .blue
            case .executingTool: return .cyan
            case .speaking: return .purple
            }
        case .synthesizing: return .blue
        case .playing: return .purple
        }
    }
}
