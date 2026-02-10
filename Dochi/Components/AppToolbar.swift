import SwiftUI

struct AppToolbar: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @State private var showInspector = false
    @State private var workspaces: [Workspace] = []

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            // Mode selector
            modeSelector

            if viewModel.settings.interactionMode == .voiceAndText {
                connectionToggle
            }

            if viewModel.isConnected {
                if isWakeWordActive {
                    WakeWordIndicator(wakeWord: viewModel.settings.wakeWord)
                } else {
                    Text(stateLabel)
                        .compact(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            // Agent / Model / Workspace quick chips
            agentModelWorkspace

            // Current user quick switch (profiles)
            userChip

            Spacer(minLength: 8)

            if let error = currentError { Text(error).compact(AppFont.caption).foregroundStyle(.red).lineLimit(1).minimumScaleFactor(0.8) }

            Spacer()

            Divider()
            if viewModel.settings.interactionMode == .voiceAndText, let _ = viewModel.actualContextUsage { contextUsageIndicator }

            if viewModel.isConnected { autoEndToggle }

            if viewModel.settings.interactionMode == .voiceAndText, isResponding { voiceIndicator }

            if !viewModel.builtInToolService.activeAlarms.isEmpty { inlineAlarms }

            // Settings
            settingsButton
        }
        .padding(.horizontal)
        .padding(.vertical, verticalPadding)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.border).frame(height: 1) }
        .frame(height: barHeight)
        .sheet(isPresented: $showInspector) {
            InspectorView()
                .environmentObject(viewModel)
        }
        .task { await refreshWorkspaces() }
    }

    // MARK: - Subviews

    private var connectionToggle: some View {
        Button { viewModel.toggleConnection() } label: {
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(connectionLabel).compact(AppFont.caption)
            }
        }
        .buttonStyle(.borderless)
    }

    private var modeSelector: some View {
        Picker("모드", selection: $viewModel.settings.interactionMode) {
            Text(InteractionMode.voiceAndText.displayName).tag(InteractionMode.voiceAndText)
            Text(InteractionMode.textOnly.displayName).tag(InteractionMode.textOnly)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
        .onChange(of: viewModel.settings.interactionMode) { _, newValue in
            if newValue == .textOnly {
                viewModel.sessionManager.stopWakeWord()
                viewModel.supertonicService.tearDown()
                viewModel.state = .idle
            }
        }
    }

    private var autoEndToggle: some View {
        Button { viewModel.autoEndSession.toggle() } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: viewModel.autoEndSession ? "timer" : "timer.circle")
                    .font(.caption)
                Text("자동종료").compact(AppFont.caption)
            }
            .foregroundStyle(viewModel.autoEndSession ? .primary : .tertiary)
        }
        .buttonStyle(.borderless)
        .help(viewModel.autoEndSession ? "자동종료 켜짐: 무응답 시 대화 종료" : "자동종료 꺼짐: 무응답 시 계속 듣기")
    }

    private var voiceIndicator: some View {
        HStack(spacing: AppSpacing.xs) {
            AudioBarsView()
            Text("응답 중").compact(AppFont.caption).foregroundStyle(.blue)
        }
        .frame(height: 16)
    }

    // MARK: - Helpers

    private var agentModelWorkspace: some View {
        HStack(spacing: AppSpacing.s) {
            // Agent quick switch
            Menu {
                let agents: [String] = {
                    if let wsId = viewModel.settings.currentWorkspaceId {
                        return viewModel.settings.contextService.listAgents(workspaceId: wsId)
                    } else {
                        return viewModel.settings.contextService.listAgents()
                    }
                }()
                if agents.isEmpty {
                    Text("에이전트 없음")
                } else {
                    ForEach(agents, id: \.self) { name in
                        Button(name) { viewModel.settings.activeAgentName = name }
                    }
                }
                Divider()
                Button("페르소나 편집") { viewModel.showSettingsSheet = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill").foregroundStyle(.blue)
                    Text(viewModel.settings.activeAgentName)
                        .compact(AppFont.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }

            // Model quick switch
            Menu {
                // Provider switch
                Section("제공자") {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Button(provider.displayName) {
                            viewModel.settings.llmProvider = provider
                            viewModel.settings.llmModel = provider.models.first ?? viewModel.settings.llmModel
                        }
                    }
                }
                // Model switch for current provider
                Section("모델") {
                    ForEach(viewModel.settings.llmProvider.models, id: \.self) { model in
                        Button(model) { viewModel.settings.llmModel = model }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile").foregroundStyle(.purple)
                    Text("\(viewModel.settings.llmProvider.displayName)/\(viewModel.settings.llmModel)")
                        .compact(AppFont.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }

            // Workspace chip (opens settings)
            if let supabase = viewModel.supabaseServiceForView, case .signedIn(_, _) = supabase.authState {
                Menu {
                    Button("새로고침") { Task { await refreshWorkspaces() } }
                    if workspaces.isEmpty {
                        Text("워크스페이스 없음")
                    } else {
                        ForEach(workspaces) { w in
                            Button {
                                supabase.setCurrentWorkspace(w)
                                viewModel.settings.currentWorkspaceId = w.id
                            } label: {
                                HStack {
                                    Text(w.name)
                                    if supabase.selectedWorkspace?.id == w.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("관리 열기") { viewModel.showSettingsSheet = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill").foregroundStyle(.teal)
                        Text(supabase.selectedWorkspace?.name ?? "워크스페이스")
                            .compact(AppFont.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            // Context Inspector toggle
            Button {
                showInspector = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
                    Text("컨텍스트").compact(AppFont.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var userChip: some View {
        let profiles = viewModel.contextService.loadProfiles()
        if profiles.isEmpty {
            EmptyView()
        } else {
            Menu {
                Button("자동 감지") {
                    viewModel.currentUserId = nil
                    viewModel.currentUserName = nil
                    viewModel.builtInToolService.configureUserContext(contextService: viewModel.contextService, currentUserId: nil)
                }
                Divider()
                ForEach(profiles) { profile in
                    Button(profile.name) {
                        viewModel.currentUserId = profile.id
                        viewModel.currentUserName = profile.name
                        viewModel.builtInToolService.configureUserContext(contextService: viewModel.contextService, currentUserId: profile.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle").foregroundStyle(.green)
                    Text(viewModel.currentUserName ?? "자동").compact(AppFont.caption)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
    }

    private var connectionColor: Color {
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

    private var connectionLabel: String {
        switch viewModel.supertonicService.state {
        case .unloaded: return "연결"
        case .loading: return "로딩 중..."
        case .ready, .synthesizing, .playing: return "연결됨"
        }
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle: return "대기 중"
        case .listening: return "듣는 중..."
        case .processing: return "응답 생성 중..."
        case .executingTool(let name): return "\(name) 실행 중..."
        case .speaking: return "음성 재생 중..."
        }
    }

    private var currentError: String? {
        viewModel.errorMessage ?? viewModel.llmService.error ?? viewModel.supertonicService.error
    }

    private var isWakeWordActive: Bool {
        viewModel.speechService.state == .waitingForWakeWord
    }

    private var isResponding: Bool {
        switch viewModel.state {
        case .processing, .executingTool, .speaking: return true
        case .idle, .listening: return false
        }
    }

    private var contextUsageIndicator: some View {
        let info = viewModel.actualContextUsage!
        return HStack(spacing: AppSpacing.xs) {
            Image(systemName: "gauge")
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(info.percent < 0.8 ? Color.blue.opacity(0.6) : (info.percent < 1.0 ? Color.orange.opacity(0.7) : Color.red.opacity(0.7)))
                    .frame(width: max(0, CGFloat(info.percent)) * 90)
            }
            .frame(width: 90, height: 8)
            Text("\(Int(info.percent * 100))%")
                .compact(AppFont.caption.monospacedDigit())
                .foregroundStyle(info.percent < 0.8 ? Color.secondary : (info.percent < 1.0 ? Color.orange : Color.red))
        }
        .accessibilityIdentifier("indicator.contextUsage")
    }

    private var inlineAlarms: some View {
        HStack(spacing: 6) {
            Image(systemName: "alarm.fill").foregroundStyle(.orange).font(.caption)
            ForEach(viewModel.builtInToolService.activeAlarms) { alarm in
                HStack(spacing: 4) {
                    Text(alarm.label).compact(AppFont.caption)
                    Text(remainingText(alarm.fireDate))
                        .compact(AppFont.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.orange.opacity(0.1), in: Capsule())
            }
        }
    }

    private var settingsButton: some View {
        Button {
            viewModel.showSettingsSheet = true
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "gearshape")
                    .font(.caption)
                Text("설정").compact(AppFont.caption)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("open.settings")
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

    private var verticalPadding: CGFloat { AppSpacing.xs }
    private var barHeight: CGFloat { 34 }

    private func refreshWorkspaces() async {
        guard let supabase = viewModel.supabaseServiceForView else { return }
        do {
            let list = try await supabase.listWorkspaces()
            await MainActor.run { self.workspaces = list }
        } catch {
            // ignore for toolbar
        }
    }
}
