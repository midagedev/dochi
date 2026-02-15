import Foundation

/// 커맨드 팔레트 아이템 모델
struct CommandPaletteItem: Identifiable, Sendable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let category: Category
    let action: PaletteAction

    enum Category: String, CaseIterable, Sendable {
        case recentCommand = "최근 사용"
        case conversation = "대화"
        case navigation = "탐색"
        case agent = "에이전트"
        case workspace = "워크스페이스"
        case user = "사용자"
        case settings = "설정"
        case tool = "도구"
    }

    enum PaletteAction: Sendable {
        case newConversation
        case selectConversation(id: UUID)
        case switchAgent(name: String)
        case openSettings
        case openContextInspector
        case openMemoryPanel
        case openCapabilityCatalog
        case openSystemStatus
        case openShortcutHelp
        case exportConversation
        case openExportOptions
        case toggleKanban
        case openTagManagement
        case toggleMultiSelect
        case createAgent
        case openFeatureTour
        case resetHints
        case openQuickModelPopover
        case openSettingsSection(section: String)
        case custom(id: String)
    }
}

/// 커맨드 팔레트 아이템 레지스트리
enum CommandPaletteRegistry {

    /// ViewModel 상태에서 동적으로 팔레트 아이템 생성
    @MainActor
    static func allItems(
        conversations: [Conversation],
        agents: [String],
        workspaceIds: [UUID],
        profiles: [UserProfile],
        currentAgentName: String,
        currentWorkspaceId: UUID,
        currentUserId: String?
    ) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        // 탐색 (Navigation)
        items.append(contentsOf: staticItems)

        // 대화 (Conversations)
        for conversation in conversations.prefix(10) {
            items.append(CommandPaletteItem(
                id: "conversation-\(conversation.id.uuidString)",
                icon: conversation.source == .telegram ? "paperplane.fill" : "bubble.left",
                title: conversation.title,
                subtitle: "대화 열기",
                category: .conversation,
                action: .selectConversation(id: conversation.id)
            ))
        }

        // 에이전트 (Agents)
        for agent in agents {
            items.append(CommandPaletteItem(
                id: "agent-\(agent)",
                icon: agent == currentAgentName ? "person.fill.checkmark" : "person.fill",
                title: agent,
                subtitle: agent == currentAgentName ? "현재 에이전트" : "에이전트 전환",
                category: .agent,
                action: .switchAgent(name: agent)
            ))
        }

        // 사용자 (Users)
        for profile in profiles {
            let isCurrent = profile.id.uuidString == currentUserId
            items.append(CommandPaletteItem(
                id: "user-\(profile.id.uuidString)",
                icon: isCurrent ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle",
                title: profile.name,
                subtitle: isCurrent ? "현재 사용자" : "사용자 전환",
                category: .user,
                action: .custom(id: "switchUser-\(profile.id.uuidString)")
            ))
        }

        return items
    }

    /// 정적 항목 (항상 표시)
    static let staticItems: [CommandPaletteItem] = [
        CommandPaletteItem(
            id: "new-conversation",
            icon: "plus.bubble",
            title: "새 대화",
            subtitle: "⌘N",
            category: .navigation,
            action: .newConversation
        ),
        CommandPaletteItem(
            id: "open-settings",
            icon: "gearshape",
            title: "설정 열기",
            subtitle: "⌘,",
            category: .settings,
            action: .openSettings
        ),
        CommandPaletteItem(
            id: "memory-panel",
            icon: "brain",
            title: "메모리 인스펙터",
            subtitle: "⌘I",
            category: .navigation,
            action: .openMemoryPanel
        ),
        CommandPaletteItem(
            id: "context-inspector",
            icon: "doc.text.magnifyingglass",
            title: "컨텍스트 인스펙터",
            subtitle: "⌘⌥I",
            category: .navigation,
            action: .openContextInspector
        ),
        CommandPaletteItem(
            id: "capability-catalog",
            icon: "square.grid.2x2",
            title: "기능 카탈로그",
            subtitle: "⌘⇧F",
            category: .navigation,
            action: .openCapabilityCatalog
        ),
        CommandPaletteItem(
            id: "system-status",
            icon: "heart.text.square",
            title: "시스템 상태",
            subtitle: "⌘⇧S",
            category: .navigation,
            action: .openSystemStatus
        ),
        CommandPaletteItem(
            id: "shortcut-help",
            icon: "keyboard",
            title: "키보드 단축키",
            subtitle: "⌘/",
            category: .navigation,
            action: .openShortcutHelp
        ),
        CommandPaletteItem(
            id: "export-conversation",
            icon: "square.and.arrow.up",
            title: "대화 빠른 내보내기 (Markdown)",
            subtitle: "⌘E",
            category: .navigation,
            action: .exportConversation
        ),
        CommandPaletteItem(
            id: "export-options",
            icon: "square.and.arrow.up.on.square",
            title: "내보내기 옵션...",
            subtitle: "⌘⇧E",
            category: .navigation,
            action: .openExportOptions
        ),
        CommandPaletteItem(
            id: "toggle-kanban",
            icon: "rectangle.3.group",
            title: "칸반 보드 전환",
            subtitle: "⌘⇧K",
            category: .navigation,
            action: .toggleKanban
        ),
        CommandPaletteItem(
            id: "tag-management",
            icon: "tag",
            title: "태그 관리",
            subtitle: "",
            category: .navigation,
            action: .openTagManagement
        ),
        CommandPaletteItem(
            id: "toggle-multi-select",
            icon: "checklist",
            title: "일괄 선택 모드",
            subtitle: "",
            category: .navigation,
            action: .toggleMultiSelect
        ),
        CommandPaletteItem(
            id: "create-agent",
            icon: "person.badge.plus",
            title: "새 에이전트 생성",
            subtitle: "",
            category: .agent,
            action: .createAgent
        ),
        CommandPaletteItem(
            id: "feature-tour",
            icon: "questionmark.circle",
            title: "기능 투어",
            subtitle: "",
            category: .navigation,
            action: .openFeatureTour
        ),
        CommandPaletteItem(
            id: "reset-hints",
            icon: "arrow.counterclockwise",
            title: "인앱 힌트 초기화",
            subtitle: "",
            category: .settings,
            action: .resetHints
        ),
        // UX-10: 설정 관련 팔레트 명령
        CommandPaletteItem(
            id: "settings.model",
            icon: "cpu",
            title: "모델 빠르게 변경",
            subtitle: "\u{2318}\u{21E7}M",
            category: .settings,
            action: .openQuickModelPopover
        ),
        CommandPaletteItem(
            id: "settings.open.ai",
            icon: "brain",
            title: "AI 모델 설정",
            subtitle: "",
            category: .settings,
            action: .openSettingsSection(section: "ai-model")
        ),
        CommandPaletteItem(
            id: "settings.open.apikey",
            icon: "key",
            title: "API 키 설정",
            subtitle: "",
            category: .settings,
            action: .openSettingsSection(section: "api-key")
        ),
        CommandPaletteItem(
            id: "settings.open.voice",
            icon: "speaker.wave.2",
            title: "음성 설정",
            subtitle: "",
            category: .settings,
            action: .openSettingsSection(section: "voice")
        ),
        CommandPaletteItem(
            id: "settings.open.agent",
            icon: "person.crop.rectangle.stack",
            title: "에이전트 설정",
            subtitle: "",
            category: .settings,
            action: .openSettingsSection(section: "agent")
        ),
        CommandPaletteItem(
            id: "settings.open.integration",
            icon: "puzzlepiece",
            title: "통합 서비스 설정",
            subtitle: "",
            category: .settings,
            action: .openSettingsSection(section: "integrations")
        ),
        CommandPaletteItem(
            id: "settings.open.account",
            icon: "person.circle",
            title: "계정/동기화 설정",
            subtitle: "",
            category: .settings,
            action: .openSettingsSection(section: "account")
        ),
    ]

    // MARK: - 최근 사용 기록

    private static let recentKey = "commandPaletteRecentIds"
    private static let maxRecent = 10

    static func recentIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    static func recordRecent(id: String) {
        var recents = recentIds()
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > maxRecent {
            recents = Array(recents.prefix(maxRecent))
        }
        UserDefaults.standard.set(recents, forKey: recentKey)
    }
}
