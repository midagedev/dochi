import SwiftUI

/// 에이전트 카드 그리드 (설정 > 에이전트 탭 교체)
struct AgentCardGridView: View {
    let contextService: ContextServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    var viewModel: DochiViewModel?
    var onAgentDeleted: (() -> Void)?

    @State private var selectedAgent: String?
    @State private var showWizard = false
    @State private var refreshTrigger = false

    private var workspaceId: UUID { sessionContext.workspaceId }

    private var agents: [String] {
        _ = refreshTrigger
        return contextService.listAgents(workspaceId: workspaceId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if agents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ], spacing: 12) {
                        ForEach(agents, id: \.self) { name in
                            agentCard(name: name)
                        }

                        // "New agent" card
                        newAgentCard
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $selectedAgent) { name in
            AgentDetailView(
                agentName: name,
                contextService: contextService,
                settings: settings,
                sessionContext: sessionContext,
                onDelete: {
                    contextService.deleteAgent(workspaceId: workspaceId, name: name)
                    selectedAgent = nil
                    onAgentDeleted?()
                    refreshTrigger.toggle()
                    Log.app.info("Agent deleted from card grid: \(name)")
                }
            )
        }
        .sheet(isPresented: $showWizard) {
            if let vm = viewModel {
                AgentWizardView(viewModel: vm)
            }
        }
        .onChange(of: showWizard) { _, isPresented in
            if !isPresented {
                refreshTrigger.toggle()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("에이전트가 없습니다")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("에이전트를 만들어 특화된 AI 비서를 구성하세요.\n템플릿을 사용하면 빠르게 시작할 수 있습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                showWizard = true
            } label: {
                Label("에이전트 만들기", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Agent Card

    private func agentCard(name: String) -> some View {
        let config = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: name)
        let isActive = name == settings.activeAgentName

        return VStack(alignment: .leading, spacing: 8) {
            // Top row: icon + name + active badge + menu
            HStack {
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(isActive ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        if isActive {
                            Text("활성")
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }

                    if let desc = config?.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                cardMenu(name: name)
            }

            // Info row: model + permissions
            HStack(spacing: 8) {
                if let model = config?.defaultModel, !model.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "brain")
                            .font(.system(size: 9))
                        Text(model)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }

                if let config = config {
                    permissionBadges(for: config)
                }

                Spacer()

                if let wakeWord = config?.wakeWord, !wakeWord.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 9))
                        Text(wakeWord)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(isActive ? Color.accentColor.opacity(0.05) : Color.secondary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    // MARK: - Card Menu

    private func cardMenu(name: String) -> some View {
        Menu {
            Button {
                selectedAgent = name
            } label: {
                Label("편집", systemImage: "pencil")
            }

            Button {
                duplicateAgent(name: name)
            } label: {
                Label("복제", systemImage: "doc.on.doc")
            }

            Button {
                saveAgentAsTemplate(name: name)
            } label: {
                Label("템플릿으로 저장", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(role: .destructive) {
                contextService.deleteAgent(workspaceId: workspaceId, name: name)
                onAgentDeleted?()
                refreshTrigger.toggle()
                Log.app.info("Agent deleted from card menu: \(name)")
            } label: {
                Label("삭제", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - New Agent Card

    private var newAgentCard: some View {
        Button {
            showWizard = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("새 에이전트")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.3))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permission Badges

    @ViewBuilder
    private func permissionBadges(for config: AgentConfig) -> some View {
        let perms = config.effectivePermissions
        HStack(spacing: 3) {
            if perms.contains("sensitive") {
                Text("sensitive")
                    .font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
            if perms.contains("restricted") {
                Text("restricted")
                    .font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.red.opacity(0.15))
                    .foregroundStyle(.red)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Actions

    private func duplicateAgent(name: String) {
        let config = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: name)
        let persona = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: name)

        // Find unique name
        var newName = "\(name) (복제)"
        let existing = contextService.listAgents(workspaceId: workspaceId)
        var counter = 2
        while existing.contains(newName) {
            newName = "\(name) (복제 \(counter))"
            counter += 1
        }

        // Create new agent
        let newConfig = AgentConfig(
            name: newName,
            wakeWord: config?.wakeWord,
            description: config?.description,
            defaultModel: config?.defaultModel,
            permissions: config?.permissions,
            shellPermissions: config?.shellPermissions
        )
        contextService.saveAgentConfig(workspaceId: workspaceId, config: newConfig)

        if let persona = persona {
            contextService.saveAgentPersona(workspaceId: workspaceId, agentName: newName, content: persona)
        }

        refreshTrigger.toggle()
        Log.app.info("Agent duplicated: \(name) -> \(newName)")
    }

    private func saveAgentAsTemplate(name: String) {
        let config = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: name)
        let persona = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: name) ?? ""

        let template = AgentTemplate(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: name,
            icon: "person.fill",
            description: config?.description ?? name,
            detailedDescription: config?.description ?? "",
            suggestedPersona: persona,
            suggestedModel: config?.defaultModel,
            suggestedPermissions: config?.effectivePermissions ?? ["safe"],
            suggestedTools: [],
            isBuiltIn: false,
            accentColor: "gray"
        )

        var templates = contextService.loadCustomTemplates()
        templates.append(template)
        contextService.saveCustomTemplates(templates)
        Log.app.info("Agent saved as template: \(name)")
    }
}
