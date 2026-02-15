import SwiftUI

/// UX-8: 우측 인스펙터 패널 — 메모리 계층 트리 시각화
struct MemoryPanelView: View {
    let contextService: ContextServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext

    // Node content states
    @State private var systemPromptText: String = ""
    @State private var agentPersonaText: String = ""
    @State private var workspaceMemoryText: String = ""
    @State private var agentMemoryText: String = ""
    @State private var personalMemoryText: String = ""

    // Expand states
    @State private var expandedNodes: Set<String> = []

    // Save feedback
    @State private var savedNodes: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            nodeList
            Divider()
            panelFooter
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        .onAppear { loadAll() }
    }

    // MARK: - Header

    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("메모리 인스펙터")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 6) {
                // Agent badge
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                    Text(settings.activeAgentName)
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Workspace badge
                HStack(spacing: 3) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 9))
                    Text(workspaceDisplayName)
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Node List

    private var nodeList: some View {
        ScrollView {
            VStack(spacing: 2) {
                MemoryNodeView(
                    nodeId: "system",
                    icon: "doc.text",
                    title: "시스템 프롬프트",
                    subtitle: "system_prompt.md",
                    emptyHint: "LLM에게 전달할 기본 지시사항을 입력하세요.",
                    text: $systemPromptText,
                    isExpanded: binding(for: "system"),
                    isSaved: savedNodes.contains("system"),
                    onSave: {
                        contextService.saveBaseSystemPrompt(systemPromptText)
                        markSaved("system")
                        Log.storage.info("System prompt saved from memory panel")
                    }
                )

                MemoryNodeView(
                    nodeId: "persona",
                    icon: "person.text.rectangle",
                    title: "에이전트 페르소나",
                    subtitle: "persona.md",
                    emptyHint: "에이전트의 성격과 역할을 정의하세요.",
                    text: $agentPersonaText,
                    isExpanded: binding(for: "persona"),
                    isSaved: savedNodes.contains("persona"),
                    onSave: {
                        contextService.saveAgentPersona(
                            workspaceId: sessionContext.workspaceId,
                            agentName: settings.activeAgentName,
                            content: agentPersonaText
                        )
                        markSaved("persona")
                        Log.storage.info("Agent persona saved from memory panel")
                    }
                )

                MemoryNodeView(
                    nodeId: "workspace",
                    icon: "square.grid.2x2",
                    title: "워크스페이스 메모리",
                    subtitle: "memory.md",
                    emptyHint: "이 워크스페이스 공통 메모리입니다. LLM이 자동으로 기록합니다.",
                    text: $workspaceMemoryText,
                    isExpanded: binding(for: "workspace"),
                    isSaved: savedNodes.contains("workspace"),
                    onSave: {
                        contextService.saveWorkspaceMemory(
                            workspaceId: sessionContext.workspaceId,
                            content: workspaceMemoryText
                        )
                        markSaved("workspace")
                        Log.storage.info("Workspace memory saved from memory panel")
                    }
                )

                MemoryNodeView(
                    nodeId: "agent",
                    icon: "brain",
                    title: "에이전트 메모리",
                    subtitle: "memory.md",
                    emptyHint: "에이전트가 학습한 내용이 여기에 저장됩니다.",
                    text: $agentMemoryText,
                    isExpanded: binding(for: "agent"),
                    isSaved: savedNodes.contains("agent"),
                    onSave: {
                        contextService.saveAgentMemory(
                            workspaceId: sessionContext.workspaceId,
                            agentName: settings.activeAgentName,
                            content: agentMemoryText
                        )
                        markSaved("agent")
                        Log.storage.info("Agent memory saved from memory panel")
                    }
                )

                if sessionContext.currentUserId != nil {
                    MemoryNodeView(
                        nodeId: "personal",
                        icon: "person",
                        title: "개인 메모리",
                        subtitle: "user memory",
                        emptyHint: "사용자에 대해 기억할 내용이 여기에 저장됩니다.",
                        text: $personalMemoryText,
                        isExpanded: binding(for: "personal"),
                        isSaved: savedNodes.contains("personal"),
                        onSave: {
                            guard let userId = sessionContext.currentUserId else { return }
                            contextService.saveUserMemory(userId: userId, content: personalMemoryText)
                            markSaved("personal")
                            Log.storage.info("User memory saved from memory panel")
                        }
                    )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text("사용자가 설정되지 않아 개인 메모리를 표시할 수 없습니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Footer

    private var panelFooter: some View {
        VStack(spacing: 4) {
            HStack {
                Text("총 \(totalChars)자 / ~\(estimatedTokens)토큰")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var totalChars: Int {
        systemPromptText.count + agentPersonaText.count + workspaceMemoryText.count + agentMemoryText.count + personalMemoryText.count
    }

    private var estimatedTokens: Int {
        max(1, totalChars / 2)
    }

    private var workspaceDisplayName: String {
        let id = sessionContext.workspaceId
        if id == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
            return "기본"
        }
        return String(id.uuidString.prefix(8))
    }

    private func binding(for nodeId: String) -> Binding<Bool> {
        Binding(
            get: { expandedNodes.contains(nodeId) },
            set: { isExpanded in
                if isExpanded {
                    expandedNodes.insert(nodeId)
                } else {
                    expandedNodes.remove(nodeId)
                }
            }
        )
    }

    private func markSaved(_ nodeId: String) {
        savedNodes.insert(nodeId)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            savedNodes.remove(nodeId)
        }
    }

    private func loadAll() {
        systemPromptText = contextService.loadBaseSystemPrompt() ?? ""

        let wsId = sessionContext.workspaceId
        let agentName = settings.activeAgentName
        agentPersonaText = contextService.loadAgentPersona(workspaceId: wsId, agentName: agentName) ?? ""
        workspaceMemoryText = contextService.loadWorkspaceMemory(workspaceId: wsId) ?? ""
        agentMemoryText = contextService.loadAgentMemory(workspaceId: wsId, agentName: agentName) ?? ""

        if let userId = sessionContext.currentUserId {
            personalMemoryText = contextService.loadUserMemory(userId: userId) ?? ""
        }

        Log.app.debug("Memory panel loaded all content")
    }
}

// MARK: - MemoryNodeView

/// 개별 메모리 노드 카드 (접기/펼치기 패턴)
struct MemoryNodeView: View {
    let nodeId: String
    let icon: String
    let title: String
    let subtitle: String
    let emptyHint: String
    @Binding var text: String
    @Binding var isExpanded: Bool
    let isSaved: Bool
    let onSave: () -> Void

    @State private var isDirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    if isSaved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }

                    Text("\(text.count)자")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isExpanded && !text.isEmpty {
                // Preview (collapsed, non-empty)
                Text(text.prefix(80).replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 6)
            }

            // Expanded content
            if isExpanded {
                if text.isEmpty {
                    // Empty state
                    VStack(spacing: 6) {
                        Text(emptyHint)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)

                        Button {
                            text = ""
                            isDirty = true
                        } label: {
                            Text("작성하기")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                } else {
                    // Editor
                    editorView
                }
            }
        }
        .background(isExpanded ? Color.secondary.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
    }

    private var editorView: some View {
        VStack(spacing: 4) {
            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .frame(minHeight: 80, maxHeight: 200)
                .onChange(of: text) { _, _ in
                    isDirty = true
                }

            HStack {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)

                Spacer()

                if isDirty {
                    Button("저장") {
                        onSave()
                        isDirty = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
