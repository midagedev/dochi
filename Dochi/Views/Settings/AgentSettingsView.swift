import SwiftUI

struct AgentSettingsView: View {
    let contextService: ContextServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    var onAgentDeleted: (() -> Void)?

    @State private var selectedAgent: String?
    @State private var showCreationForm = false

    // Inline creation form
    @State private var newName = ""
    @State private var newWakeWord = ""
    @State private var newDescription = ""
    @State private var creationError: String?

    private var workspaceId: UUID { sessionContext.workspaceId }

    private var agents: [String] {
        contextService.listAgents(workspaceId: workspaceId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Agent list
            List {
                Section("현재 워크스페이스 에이전트") {
                    if agents.isEmpty {
                        Text("에이전트가 없습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(agents, id: \.self) { name in
                            agentRow(name: name)
                        }
                    }
                }

                Section {
                    DisclosureGroup("에이전트 추가", isExpanded: $showCreationForm) {
                        creationForm
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding()
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
                    Log.app.info("Agent deleted from settings: \(name)")
                }
            )
        }
    }

    // MARK: - Agent Row

    @ViewBuilder
    private func agentRow(name: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body)
                        .fontWeight(name == settings.activeAgentName ? .semibold : .regular)

                    if name == settings.activeAgentName {
                        Text("활성")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let config = contextService.loadAgentConfig(workspaceId: workspaceId, agentName: name) {
                        if let wakeWord = config.wakeWord {
                            Text("호출어: \(wakeWord)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        permissionBadges(for: config)
                    }
                }
            }

            Spacer()

            Button {
                selectedAgent = name
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("편집")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func permissionBadges(for config: AgentConfig) -> some View {
        let perms = config.effectivePermissions
        HStack(spacing: 4) {
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

    // MARK: - Creation Form

    private var creationForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("이름 (필수)", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("호출어 (선택)", text: $newWakeWord)
                .textFieldStyle(.roundedBorder)
            TextField("설명 (선택)", text: $newDescription)
                .textFieldStyle(.roundedBorder)

            if let error = creationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("생성") {
                    createAgent()
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    private func createAgent() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if agents.contains(name) {
            creationError = "이미 같은 이름의 에이전트가 있습니다."
            return
        }

        let wake = newWakeWord.trimmingCharacters(in: .whitespaces)
        let desc = newDescription.trimmingCharacters(in: .whitespaces)

        contextService.createAgent(
            workspaceId: workspaceId,
            name: name,
            wakeWord: wake.isEmpty ? nil : wake,
            description: desc.isEmpty ? nil : desc
        )

        // Reset form
        newName = ""
        newWakeWord = ""
        newDescription = ""
        creationError = nil
        showCreationForm = false

        Log.app.info("Agent created from settings: \(name)")
    }
}

// MARK: - String Identifiable (for sheet binding)

extension String: @retroactive Identifiable {
    public var id: String { self }
}
