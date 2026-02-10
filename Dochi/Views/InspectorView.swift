import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .context
    // Editors
    @State private var showBasePromptEditor = false
    @State private var showSystemEditor = false
    @State private var showAgentPersonaEditor = false
    @State private var showAgentMemoryEditor = false
    @State private var showMemoryEditor = false
    @State private var showFamilyMemoryEditor = false

    enum Tab: String, CaseIterable { case context = "Context", tools = "Tools", coding = "Coding", sources = "Sources", vars = "Vars" }

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("컨텍스트").font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            .background(.bar)
            .overlay(alignment: .bottom) { Rectangle().fill(AppColor.border).frame(height: 1) }
            // Tabs
            HStack(spacing: AppSpacing.s) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        Text(t.rawValue)
                            .compact(AppFont.caption)
                            .padding(.horizontal, AppSpacing.s)
                            .padding(.vertical, AppSpacing.xs)
                            .background(tab == t ? AppColor.surface : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.background)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    switch tab {
                    case .context: ContextPanel(
                        viewModel: viewModel,
                        onOpenBasePrompt: { showBasePromptEditor = true },
                        onOpenWorkspaceMemory: { showFamilyMemoryEditor = true },
                        onOpenAgentPersona: { showAgentPersonaEditor = true },
                        onOpenAgentMemory: { showAgentMemoryEditor = true },
                        onOpenPersonalMemory: { showMemoryEditor = true }
                    )
                    case .tools: ToolsPanel(viewModel: viewModel)
                    case .coding: ClaudeUIPanel(viewModel: viewModel)
                    case .sources: SourcesPanel()
                    case .vars: VarsPanel(viewModel: viewModel)
                    }
                }
                .padding(AppSpacing.s)
            }
        }
        // Sheets for editors
        .sheet(isPresented: $showBasePromptEditor) { BasePromptEditorView(contextService: viewModel.settings.contextService) }
        .sheet(isPresented: $showSystemEditor) { SystemEditorView(contextService: viewModel.settings.contextService) }
        .sheet(isPresented: $showAgentPersonaEditor) { AgentPersonaEditorView(contextService: viewModel.settings.contextService, agentName: viewModel.settings.activeAgentName) }
        .sheet(isPresented: $showAgentMemoryEditor) { AgentMemoryEditorView(contextService: viewModel.settings.contextService, agentName: viewModel.settings.activeAgentName) }
        .sheet(isPresented: $showMemoryEditor) { MemoryEditorView(contextService: viewModel.settings.contextService) }
        .sheet(isPresented: $showFamilyMemoryEditor) { FamilyMemoryEditorView(contextService: viewModel.settings.contextService) }
    }
}

private struct ContextPanel: View {
    let viewModel: DochiViewModel
    var onOpenBasePrompt: () -> Void
    var onOpenWorkspaceMemory: () -> Void
    var onOpenAgentPersona: () -> Void
    var onOpenAgentMemory: () -> Void
    var onOpenPersonalMemory: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionCard("컨텍스트 스택", icon: "archivebox") {
                // Base rules
                HStack {
                    Text("기본 규칙").compact(AppFont.caption)
                    Spacer()
                    Button("편집") { onOpenBasePrompt() }.compact(AppFont.caption)
                }
                .padding(.bottom, AppSpacing.xs)
                if !viewModel.settings.contextService.loadBaseSystemPrompt().isEmpty {
                    Text(viewModel.settings.contextService.loadBaseSystemPrompt())
                        .compact(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("설정되지 않음").compact(AppFont.caption).foregroundStyle(.tertiary)
                }

                // Workspace memory
                HStack {
                    Text("워크스페이스 기억").compact(AppFont.caption)
                    Spacer()
                    Button("편집") { onOpenWorkspaceMemory() }.compact(AppFont.caption)
                }
                .padding(.top, AppSpacing.s)
                if let wsId = viewModel.settings.currentWorkspaceId {
                    let memory = viewModel.settings.contextService.loadWorkspaceMemory(workspaceId: wsId)
                    Text(memory.isEmpty ? "(없음)" : memory).compact(AppFont.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text("워크스페이스 없음").compact(AppFont.caption).foregroundStyle(.tertiary)
                }

                // Agent persona + memory
                HStack {
                    Text("에이전트: \(viewModel.settings.activeAgentName)").compact(AppFont.caption)
                    Spacer()
                    Button("페르소나") { onOpenAgentPersona() }.compact(AppFont.caption)
                    Button("기억") { onOpenAgentMemory() }.compact(AppFont.caption)
                }
                if let wsId = viewModel.settings.currentWorkspaceId {
                    let persona = viewModel.settings.contextService.loadAgentPersona(workspaceId: wsId, agentName: viewModel.settings.activeAgentName)
                    Text(persona.isEmpty ? "(페르소나 없음)" : persona).compact(AppFont.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    let persona = viewModel.settings.contextService.loadAgentPersona(agentName: viewModel.settings.activeAgentName)
                    Text(persona.isEmpty ? "(페르소나 없음)" : persona).compact(AppFont.caption).foregroundStyle(.secondary).lineLimit(2)
                }

                // Personal memory for current user
                HStack {
                    Text("개인 기억").compact(AppFont.caption)
                    Spacer()
                    Button("편집") { onOpenPersonalMemory() }.compact(AppFont.caption)
                }
                if let uid = viewModel.currentUserId {
                    let mem = viewModel.settings.contextService.loadUserMemory(userId: uid)
                    Text(mem.isEmpty ? "(없음)" : mem).compact(AppFont.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text("현재 사용자 미확인 — set_current_user 사용").compact(AppFont.caption).foregroundStyle(.tertiary)
                }
            }

            SectionCard("대화 메타", icon: "info.circle") {
                KVRow(k: "메시지 수", v: "\(viewModel.messages.count)")
                KVRow(k: "모델", v: "\(viewModel.settings.llmProvider.displayName) / \(viewModel.settings.llmModel)")
                if let usage = viewModel.actualContextUsage {
                    KVRow(k: "컨텍스트", v: "\(usage.usedTokens) / \(usage.limitTokens) (\(Int(usage.percent * 100))%)")
                }
            }
        }
    }
}

private struct ToolsPanel: View {
    let viewModel: DochiViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionCard("도구 상태", icon: "hammer") {
                if let name = viewModel.currentToolExecution {
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: "bolt.fill").foregroundStyle(.cyan).font(.caption)
                        Text("\(name) 실행 중...").compact(AppFont.caption)
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                } else {
                    Text("최근 실행 중인 도구 없음")
                        .compact(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard("도구 레지스트리", icon: "shippingbox") {
                RegistryControls(viewModel: viewModel)
            }

            if !viewModel.mcpService.availableTools.isEmpty {
                SectionCard("MCP 도구", icon: "wrench.and.screwdriver") {
                    ForEach(viewModel.mcpService.availableTools) { tool in
                        HStack(spacing: AppSpacing.s) {
                            Image(systemName: "wrench.and.screwdriver").foregroundStyle(.cyan)
                            Text(tool.name).compact(AppFont.caption)
                            Spacer()
                        }
                        .padding(.vertical, AppSpacing.xs)
                    }
                }
            }
        }
    }
}

private struct RegistryControls: View {
    @ObservedObject var viewModel: DochiViewModel
    @State private var ttl: Int = 10
    @State private var selectedCategories: Set<String> = []
    @State private var enabledNames: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Toggle("세션 종료 시 자동 리셋", isOn: $viewModel.settings.toolsRegistryAutoReset)
                .compact(AppFont.caption)
            HStack {
                Text("TTL(분)").compact(AppFont.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(ttl) }, set: { ttl = Int($0) ; viewModel.builtInToolService.setRegistryTTL(minutes: ttl) }), in: 1...60, step: 1)
                Text("\(ttl)").compact(AppFont.caption).monospacedDigit().frame(width: 28)
            }
            .onAppear { ttl = 10 }

            let catalog = viewModel.builtInToolService.toolCatalogByCategory()
            if !catalog.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("카테고리 선택").compact(AppFont.caption).foregroundStyle(.secondary)
                    ForEach(catalog.keys.sorted(), id: \.self) { key in
                        Toggle(isOn: Binding(
                            get: { selectedCategories.contains(key) },
                            set: { newValue in
                                if newValue { selectedCategories.insert(key) } else { selectedCategories.remove(key) }
                                applyCategories(catalog)
                            }
                        )) {
                            Text(key).compact(AppFont.caption)
                        }
                    }
                }
            }

            HStack {
                Button("리셋") { viewModel.builtInToolService.setEnabledToolNames(nil); refreshEnabled() }
                Spacer()
                Button("새로고침") { refreshEnabled() }
            }
            .compact(AppFont.caption)

            if !enabledNames.isEmpty {
                Text("활성 도구: \(enabledNames.sorted().joined(separator: ", "))")
                    .compact(AppFont.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("활성 도구: (베이스라인만 노출)")
                    .compact(AppFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { refreshEnabled() }
    }

    private func applyCategories(_ catalog: [String: [String]]) {
        let names = selectedCategories.flatMap { catalog[$0] ?? [] }
        viewModel.builtInToolService.setEnabledToolNames(Array(Set(names)))
        refreshEnabled()
    }

    private func refreshEnabled() {
        enabledNames = viewModel.builtInToolService.getEnabledToolNames() ?? []
    }
}

private struct SourcesPanel: View {
    var body: some View {
        SectionCard("출처", icon: "link") {
            Text("연결된 출처 없음")
                .compact(AppFont.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClaudeUIPanel: View {
    @ObservedObject var viewModel: DochiViewModel
    @State private var health: String = ""
    @State private var projects: [[String: Any]] = []
    @State private var selectedProject: String?
    @State private var sessions: [String: Any] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionCard("연결", icon: "network") {
                HStack {
                    Text(viewModel.settings.claudeUIEnabled ? "사용" : "비활성").compact(AppFont.caption)
                    Spacer()
                    Button("새로고침") { Task { await refresh() } }
                        .compact(AppFont.caption)
                        .disabled(!viewModel.settings.claudeUIEnabled)
                }
                if !health.isEmpty {
                    Text(health).compact(AppFont.caption).foregroundStyle(.secondary)
                }
            }

            SectionCard("프로젝트", icon: "folder") {
                if projects.isEmpty {
                    Text("프로젝트 없음 또는 로드 안 됨").compact(AppFont.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(projects.indices), id: \.self) { i in
                        let p = projects[i]
                        let name = (p["name"] as? String) ?? "(unknown)"
                        Button {
                            selectedProject = name
                            Task { await loadSessions(project: name) }
                        } label: { Text(name).compact(AppFont.caption) }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let sp = selectedProject {
                SectionCard("세션 — \(sp)", icon: "clock") {
                    if let arr = sessions["sessions"] as? [[String: Any]], !arr.isEmpty {
                        ForEach(Array(arr.indices), id: \.self) { i in
                            let s = arr[i]
                            HStack {
                                Text((s["summary"] as? String) ?? "(no summary)")
                                    .compact(AppFont.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text((s["lastActivity"] as? String) ?? "").compact(AppFont.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("세션 없음").compact(AppFont.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onAppear { Task { await refresh() } }
    }

    private func refresh() async {
        guard viewModel.settings.claudeUIEnabled else { return }
        let svc = ClaudeCodeUIService(settings: viewModel.settings)
        do {
            health = try await svc.health()
            projects = try await svc.listProjects()
        } catch {
            health = "연결 실패: \(error.localizedDescription)"
            projects = []
        }
    }

    private func loadSessions(project: String) async {
        let svc = ClaudeCodeUIService(settings: viewModel.settings)
        do { sessions = try await svc.listSessions(projectName: project, limit: 5, offset: 0) } catch { sessions = [:] }
    }
}

private struct VarsPanel: View {
    let viewModel: DochiViewModel
    var body: some View {
        SectionCard("런타임 변수", icon: "terminal") {
            Group {
                KVRow(k: "모델", v: "\(viewModel.settings.llmProvider.displayName) / \(viewModel.settings.llmModel)")
                KVRow(k: "상태", v: "\(String(describing: viewModel.state))")
                KVRow(k: "연결", v: viewModel.isConnected ? "연결됨" : "연결 안 됨")
            }
        }
    }
}

private struct KVRow: View {
    let k: String
    let v: String
    var body: some View {
        HStack {
            Text(k).compact(AppFont.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).compact(AppFont.caption)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
