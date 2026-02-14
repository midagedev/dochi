import SwiftUI

/// 기능 카탈로그 — "도치가 할 수 있는 것" 전체 목록
struct CapabilityCatalogView: View {
    let toolInfos: [ToolInfo]
    let onSelectPrompt: (String) -> Void
    @State private var searchText = ""
    @State private var selectedGroup: String?
    @Environment(\.dismiss) private var dismiss

    private var groupedTools: [(group: String, icon: String, tools: [ToolInfo])] {
        let groups = Dictionary(grouping: filteredTools) { $0.group }
        return groups
            .map { (group: $0.key, icon: groupIcon(for: $0.key), tools: $0.value) }
            .sorted { $0.group < $1.group }
    }

    private var filteredTools: [ToolInfo] {
        if searchText.isEmpty { return toolInfos }
        let query = searchText.lowercased()
        return toolInfos.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // 좌측: 카테고리 목록
                groupListView
                    .frame(width: 200)

                Divider()

                // 우측: 선택된 그룹 상세
                if let group = selectedGroup,
                   let entry = groupedTools.first(where: { $0.group == group }) {
                    groupDetailView(entry)
                } else {
                    overviewView
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    // MARK: - 카테고리 목록

    private var groupListView: some View {
        VStack(spacing: 0) {
            // 검색
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("기능 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.3))

            Divider()

            // 전체 보기 버튼
            Button {
                selectedGroup = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .frame(width: 16)
                    Text("전체 보기")
                    Spacer()
                    Text("\(toolInfos.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedGroup == nil ? Color.accentColor.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            // 그룹 목록
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupedTools, id: \.group) { entry in
                        Button {
                            selectedGroup = entry.group
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: entry.icon)
                                    .frame(width: 16)
                                    .foregroundStyle(.secondary)
                                Text(groupDisplayName(for: entry.group))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(entry.tools.count)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedGroup == entry.group ? Color.accentColor.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 전체 보기

    private var overviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("도치가 할 수 있는 것")
                    .font(.title2.bold())
                    .padding(.top, 16)

                Text("대화 중에 자연어로 요청하면 도치가 알아서 적절한 도구를 사용합니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // 카테고리 그리드
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(groupedTools, id: \.group) { entry in
                        Button {
                            selectedGroup = entry.group
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: entry.icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.accentColor)
                                    Spacer()
                                    Text("\(entry.tools.count)개")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Text(groupDisplayName(for: entry.group))
                                    .font(.system(size: 13, weight: .semibold))
                                Text(entry.tools.first?.description ?? "")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - 그룹 상세

    private func groupDetailView(_ entry: (group: String, icon: String, tools: [ToolInfo])) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                    Text(groupDisplayName(for: entry.group))
                        .font(.title3.bold())
                }
                .padding(.top, 16)

                ForEach(entry.tools) { tool in
                    toolCard(tool)
                }
            }
            .padding(16)
        }
    }

    private func toolCard(_ tool: ToolInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tool.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                categoryBadge(tool.category)
                if tool.isBaseline {
                    Text("기본")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            Text(tool.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // 사용 예시 버튼
            if let example = examplePrompt(for: tool) {
                Button {
                    onSelectPrompt(example)
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 10))
                        Text("사용해보기: \"\(example)\"")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func categoryBadge(_ category: ToolCategory) -> some View {
        let (text, color): (String, Color) = switch category {
        case .safe: ("안전", .green)
        case .sensitive: ("확인 필요", .orange)
        case .restricted: ("제한", .red)
        }
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Helpers

    private func groupIcon(for group: String) -> String {
        switch group {
        case "calendar", "list_calendar_events", "create_calendar_event", "delete_calendar_event": return "calendar"
        case "kanban": return "rectangle.3.group"
        case "file": return "doc"
        case "web_search": return "magnifyingglass"
        case "shell": return "terminal"
        case "clipboard": return "doc.on.clipboard"
        case "screenshot": return "camera.viewfinder"
        case "git": return "arrow.triangle.branch"
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "music": return "music.note"
        case "contacts": return "person.2"
        case "generate_image", "print_image": return "photo"
        case "create_reminder", "list_reminders", "complete_reminder": return "checklist"
        case "timer", "set_timer", "list_timers", "cancel_timer": return "timer"
        case "alarm", "set_alarm", "list_alarms", "cancel_alarm": return "alarm"
        case "calculate": return "function"
        case "datetime": return "clock"
        case "memory", "save_memory", "update_memory": return "brain"
        case "tools": return "wrench.and.screwdriver"
        case "settings": return "gear"
        case "agent": return "person.badge.key"
        case "workspace": return "building.2"
        case "telegram": return "paperplane"
        case "workflow": return "arrow.triangle.2.circlepath"
        case "coding": return "chevron.left.forwardslash.chevron.right"
        case "finder": return "folder"
        case "open_url": return "link"
        case "mcp": return "server.rack"
        case "profile", "set_current_user": return "person.crop.circle"
        case "context", "update_base_system_prompt": return "doc.text"
        default: return "square.grid.2x2"
        }
    }

    private func groupDisplayName(for group: String) -> String {
        switch group {
        case "kanban": return "칸반"
        case "file": return "파일 관리"
        case "web_search": return "웹 검색"
        case "shell": return "터미널"
        case "clipboard": return "클립보드"
        case "screenshot": return "스크린샷"
        case "git": return "Git"
        case "github": return "GitHub"
        case "music": return "음악"
        case "contacts": return "연락처"
        case "generate_image": return "이미지 생성"
        case "print_image": return "이미지 표시"
        case "create_reminder", "list_reminders", "complete_reminder": return "미리알림"
        case "set_timer", "list_timers", "cancel_timer": return "타이머"
        case "set_alarm", "list_alarms", "cancel_alarm": return "알람"
        case "calculate": return "계산기"
        case "datetime": return "날짜/시간"
        case "save_memory", "update_memory": return "기억"
        case "tools": return "도구 관리"
        case "settings": return "설정"
        case "agent": return "에이전트"
        case "workspace": return "워크스페이스"
        case "telegram": return "텔레그램"
        case "workflow": return "워크플로우"
        case "coding": return "코딩 에이전트"
        case "finder": return "Finder"
        case "open_url": return "URL 열기"
        case "mcp": return "MCP 서버"
        case "set_current_user": return "사용자 전환"
        case "update_base_system_prompt": return "시스템 프롬프트"
        case "list_calendar_events", "create_calendar_event", "delete_calendar_event": return "캘린더"
        default: return group
        }
    }

    private func examplePrompt(for tool: ToolInfo) -> String? {
        // 슬래시 명령에서 매칭되는 예시 찾기
        if let cmd = FeatureCatalog.slashCommands.first(where: { $0.toolGroup == tool.group }),
           !cmd.example.isEmpty {
            return cmd.example
        }

        // 도구별 기본 예시
        switch tool.name {
        case "web_search": return "최신 뉴스 검색해줘"
        case "calculate": return "123 * 456 계산해줘"
        case "datetime": return "지금 몇 시야?"
        case "save_memory": return "이거 기억해줘: 나는 커피를 좋아해"
        default: return nil
        }
    }
}
