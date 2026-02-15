import SwiftUI

// MARK: - SettingsSection

enum SettingsSection: String, CaseIterable, Identifiable {
    case aiModel = "ai-model"
    case apiKey = "api-key"
    case usage = "usage"
    case rag = "rag"
    case memory = "memory"
    case feedback = "feedback"
    case voice = "voice"
    case interface = "interface"
    case wakeWord = "wake-word"
    case heartbeat = "heartbeat"
    case family = "family"
    case agent = "agent"
    case tools = "tools"
    case integrations = "integrations"
    case shortcuts = "shortcuts"
    case automation = "automation"
    case plugins = "plugins"
    case devices = "devices"
    case account = "account"
    case guide = "guide"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiModel: return "AI 모델"
        case .apiKey: return "API 키"
        case .usage: return "사용량"
        case .rag: return "문서 검색"
        case .memory: return "메모리 정리"
        case .feedback: return "피드백 통계"
        case .voice: return "음성 합성"
        case .interface: return "인터페이스"
        case .wakeWord: return "웨이크워드"
        case .heartbeat: return "하트비트"
        case .automation: return "자동화"
        case .family: return "가족 구성원"
        case .agent: return "에이전트"
        case .tools: return "도구"
        case .integrations: return "통합 서비스"
        case .shortcuts: return "단축어"
        case .plugins: return "플러그인"
        case .devices: return "디바이스"
        case .account: return "계정/동기화"
        case .guide: return "가이드"
        }
    }

    var icon: String {
        switch self {
        case .aiModel: return "brain"
        case .apiKey: return "key"
        case .usage: return "chart.bar.xaxis"
        case .rag: return "doc.text.magnifyingglass"
        case .memory: return "brain.head.profile"
        case .feedback: return "chart.line.uptrend.xyaxis"
        case .voice: return "speaker.wave.2"
        case .interface: return "textformat.size"
        case .wakeWord: return "mic"
        case .heartbeat: return "heart"
        case .automation: return "clock.badge.checkmark"
        case .family: return "person.2"
        case .agent: return "person.crop.rectangle.stack"
        case .tools: return "wrench.and.screwdriver"
        case .integrations: return "puzzlepiece"
        case .shortcuts: return "square.grid.3x3.square"
        case .plugins: return "puzzlepiece.extension"
        case .devices: return "laptopcomputer.and.iphone"
        case .account: return "person.circle"
        case .guide: return "play.rectangle"
        }
    }

    var group: SettingsSectionGroup {
        switch self {
        case .aiModel, .apiKey, .usage, .rag, .memory, .feedback: return .ai
        case .voice: return .voice
        case .interface, .wakeWord, .heartbeat, .automation: return .general
        case .family, .agent: return .people
        case .tools, .integrations, .shortcuts, .plugins, .devices, .account: return .connection
        case .guide: return .help
        }
    }

    var searchKeywords: [String] {
        switch self {
        case .aiModel:
            return ["모델", "프로바이더", "OpenAI", "Anthropic", "Z.AI", "Ollama", "LM Studio", "로컬", "오프라인", "local", "라우팅", "폴백"]
        case .apiKey:
            return ["API", "키", "key", "OpenAI", "Anthropic", "Tavily", "Fal", "티어"]
        case .usage:
            return ["사용량", "비용", "cost", "토큰", "token", "예산", "budget", "대시보드", "dashboard"]
        case .rag:
            return ["RAG", "문서", "검색", "임베딩", "embedding", "벡터", "vector", "PDF", "인덱싱"]
        case .memory:
            return ["메모리", "정리", "자동", "요약", "사실", "추출", "아카이브", "모순", "중복", "consolidation"]
        case .feedback:
            return ["피드백", "만족도", "평가", "feedback", "통계", "좋아요", "싫어요"]
        case .voice:
            return ["음성", "TTS", "속도", "피치", "Google Cloud", "프로바이더"]
        case .interface:
            return ["글꼴", "폰트", "크기", "모드", "아바타", "VRM"]
        case .wakeWord:
            return ["웨이크워드", "마이크", "침묵", "음성 입력"]
        case .heartbeat:
            return ["하트비트", "주기", "캘린더", "칸반", "미리알림", "조용한 시간"]
        case .automation:
            return ["자동화", "스케줄", "크론", "cron", "반복", "타이머", "예약", "브리핑", "리포트", "automation"]
        case .family:
            return ["가족", "구성원", "프로필", "사용자"]
        case .agent:
            return ["에이전트", "페르소나", "템플릿", "위임", "delegation"]
        case .tools:
            return ["도구", "tool", "권한", "safe", "sensitive", "restricted"]
        case .integrations:
            return ["텔레그램", "MCP", "봇", "웹훅"]
        case .shortcuts:
            return ["단축어", "Shortcuts", "Siri", "AppIntent", "자동화", "automation"]
        case .plugins:
            return ["플러그인", "plugin", "확장", "extension", "도구", "커스텀", "설치"]
        case .devices:
            return ["디바이스", "기기", "device", "멀티", "정책", "우선순위", "priority", "데스크탑", "모바일", "CLI", "응답"]
        case .account:
            return ["Supabase", "동기화", "로그인", "인증"]
        case .guide:
            return ["투어", "힌트", "온보딩"]
        }
    }

    /// Check if this section matches a search query
    func matches(query: String) -> Bool {
        let q = query.lowercased()
        if title.lowercased().contains(q) { return true }
        return searchKeywords.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - SettingsSectionGroup

enum SettingsSectionGroup: String, CaseIterable {
    case ai = "AI"
    case voice = "음성"
    case general = "일반"
    case people = "사람"
    case connection = "연결"
    case help = "도움말"

    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.group == self }
    }
}

// MARK: - SettingsSidebarView

struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection
    @Binding var searchText: String

    @FocusState private var isSearchFocused: Bool

    private var filteredGroups: [(group: SettingsSectionGroup, sections: [SettingsSection])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [(group: SettingsSectionGroup, sections: [SettingsSection])] = []

        for group in SettingsSectionGroup.allCases {
            let sections: [SettingsSection]
            if query.isEmpty {
                sections = group.sections
            } else {
                sections = group.sections.filter { $0.matches(query: query) }
            }
            if !sections.isEmpty {
                result.append((group, sections))
            }
        }

        return result
    }

    private var flatSections: [SettingsSection] {
        filteredGroups.flatMap(\.sections)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            if flatSections.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("일치하는 설정이 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredGroups, id: \.group) { group in
                            // Group header
                            Text(group.group.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .padding(.bottom, 4)

                            ForEach(group.sections) { section in
                                SettingsSidebarRow(
                                    section: section,
                                    isSelected: selectedSection == section,
                                    onSelect: {
                                        selectedSection = section
                                    }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)

            // Version footer
            Divider()
            Text(versionString)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 180)
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
    }

    private func moveSelection(by delta: Int) {
        let flat = flatSections
        guard !flat.isEmpty else { return }
        if let currentIndex = flat.firstIndex(of: selectedSection) {
            let newIndex = max(0, min(flat.count - 1, currentIndex + delta))
            selectedSection = flat[newIndex]
        } else {
            selectedSection = flat.first ?? .aiModel
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

// MARK: - SettingsSidebarRow

struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18)

                Text(section.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : isHovering ? Color.secondary.opacity(0.06) : Color.clear
                    )
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(section.title)
    }
}
