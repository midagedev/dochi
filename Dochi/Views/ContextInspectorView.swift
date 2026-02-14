import SwiftUI

struct ContextInspectorView: View {
    let contextService: ContextServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case systemPrompt = "시스템 프롬프트"
        case agent = "에이전트"
        case memory = "메모리"
    }

    @State private var selectedTab: Tab = .systemPrompt

    // System prompt
    @State private var systemPromptText: String = ""
    @State private var systemPromptSaved: Bool = false

    // Agent
    @State private var agentPersonaText: String = ""
    @State private var agentPersonaSaved: Bool = false
    @State private var agentMemoryText: String = ""
    @State private var agentMemorySaved: Bool = false

    // Memory
    @State private var workspaceMemoryText: String = ""
    @State private var workspaceMemorySaved: Bool = false
    @State private var userMemoryText: String = ""
    @State private var userMemorySaved: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("컨텍스트 인스펙터")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()
                .padding(.top, 8)

            // Tab content
            switch selectedTab {
            case .systemPrompt:
                systemPromptTab
            case .agent:
                agentTab
            case .memory:
                memoryTab
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            loadAllContent()
        }
    }

    // MARK: - System Prompt Tab

    private var systemPromptTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEditorView(
                title: "기본 시스템 프롬프트",
                subtitle: "system_prompt.md",
                text: $systemPromptText,
                placeholder: "시스템 프롬프트를 입력하세요...",
                saved: $systemPromptSaved,
                onSave: {
                    contextService.saveBaseSystemPrompt(systemPromptText)
                    systemPromptSaved = true
                    Log.storage.info("System prompt saved from inspector")
                }
            )
        }
        .padding()
    }

    // MARK: - Agent Tab

    private var agentTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Agent name display
                HStack {
                    Text("현재 에이전트:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(settings.activeAgentName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                SectionEditorView(
                    title: "페르소나",
                    subtitle: "persona.md",
                    text: $agentPersonaText,
                    placeholder: "에이전트 페르소나를 입력하세요...",
                    saved: $agentPersonaSaved,
                    onSave: {
                        contextService.saveAgentPersona(
                            workspaceId: sessionContext.workspaceId,
                            agentName: settings.activeAgentName,
                            content: agentPersonaText
                        )
                        agentPersonaSaved = true
                        Log.storage.info("Agent persona saved from inspector")
                    }
                )

                SectionEditorView(
                    title: "에이전트 메모리",
                    subtitle: "memory.md",
                    text: $agentMemoryText,
                    placeholder: "에이전트 메모리가 비어 있습니다.",
                    saved: $agentMemorySaved,
                    onSave: {
                        contextService.saveAgentMemory(
                            workspaceId: sessionContext.workspaceId,
                            agentName: settings.activeAgentName,
                            content: agentMemoryText
                        )
                        agentMemorySaved = true
                        Log.storage.info("Agent memory saved from inspector")
                    }
                )
            }
            .padding()
        }
    }

    // MARK: - Memory Tab

    private var memoryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionEditorView(
                    title: "워크스페이스 메모리",
                    subtitle: "workspace memory.md",
                    text: $workspaceMemoryText,
                    placeholder: "워크스페이스 메모리가 비어 있습니다.",
                    saved: $workspaceMemorySaved,
                    onSave: {
                        contextService.saveWorkspaceMemory(
                            workspaceId: sessionContext.workspaceId,
                            content: workspaceMemoryText
                        )
                        workspaceMemorySaved = true
                        Log.storage.info("Workspace memory saved from inspector")
                    }
                )

                if sessionContext.currentUserId != nil {
                    SectionEditorView(
                        title: "개인 메모리",
                        subtitle: "user memory",
                        text: $userMemoryText,
                        placeholder: "개인 메모리가 비어 있습니다.",
                        saved: $userMemorySaved,
                        onSave: {
                            guard let userId = sessionContext.currentUserId else { return }
                            contextService.saveUserMemory(userId: userId, content: userMemoryText)
                            userMemorySaved = true
                            Log.storage.info("User memory saved from inspector")
                        }
                    )
                } else {
                    HStack {
                        Image(systemName: "person.slash")
                            .foregroundStyle(.secondary)
                        Text("사용자 ID가 설정되지 않아 개인 메모리를 표시할 수 없습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    // MARK: - Section Editor (delegated to SectionEditorView)

    // MARK: - Data Loading

    private func loadAllContent() {
        // System prompt
        systemPromptText = contextService.loadBaseSystemPrompt() ?? ""

        // Agent
        let wsId = sessionContext.workspaceId
        let agentName = settings.activeAgentName
        agentPersonaText = contextService.loadAgentPersona(workspaceId: wsId, agentName: agentName) ?? ""
        agentMemoryText = contextService.loadAgentMemory(workspaceId: wsId, agentName: agentName) ?? ""

        // Memory
        workspaceMemoryText = contextService.loadWorkspaceMemory(workspaceId: wsId) ?? ""
        if let userId = sessionContext.currentUserId {
            userMemoryText = contextService.loadUserMemory(userId: userId) ?? ""
        }

        Log.app.debug("Context inspector loaded all content")
    }
}
