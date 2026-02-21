import Foundation
import os

@MainActor
final class ToolRegistry {
    private var allTools: [String: any BuiltInToolProtocol] = [:]
    private var enabledNames: Set<String> = []
    private var ttlTask: Task<Void, Never>?

    var baselineTools: [any BuiltInToolProtocol] {
        allTools.values.filter { $0.isBaseline }
    }

    func register(_ tool: any BuiltInToolProtocol) {
        allTools[tool.name] = tool
    }

    func tool(named name: String) -> (any BuiltInToolProtocol)? {
        allTools[name]
    }

    /// Returns tools available for the given permission categories.
    /// Explicitly enabled tools bypass the category filter.
    /// Baseline tools are included if their category is permitted.
    func availableTools(for permissions: [String]) -> [any BuiltInToolProtocol] {
        let permissionSet = Set(permissions)
        return allTools.values.filter { tool in
            if enabledNames.contains(tool.name) { return true }
            guard permissionSet.contains(tool.category.rawValue) else { return false }
            return tool.isBaseline
        }
    }

    /// Returns tool names that belong to one of the requested logical groups.
    /// Group names are normalized (trimmed, lowercased) before matching.
    func toolNames(inGroups groups: [String]) -> [String] {
        let normalized = Set(groups.map(ToolGroupResolver.normalizeGroupName).filter { !$0.isEmpty })
        guard !normalized.isEmpty else { return [] }

        return allTools.keys
            .filter { normalized.contains(ToolGroupResolver.group(forToolName: $0)) }
            .sorted()
    }

    /// Returns all currently known logical group names.
    var allToolGroups: [String] {
        let groups = allTools.keys.map { ToolGroupResolver.group(forToolName: $0) }
        return Array(Set(groups)).sorted()
    }

    func enable(names: [String]) {
        for name in names {
            if allTools[name] != nil {
                enabledNames.insert(name)
                Log.tool.info("Tool enabled: \(name)")
            } else {
                Log.tool.warning("Tool not found for enable: \(name)")
            }
        }
    }

    func enableTTL(minutes: Int) {
        ttlTask?.cancel()
        let mins = minutes
        ttlTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(mins * 60))
            guard !Task.isCancelled else { return }
            await self?.resetEnabled()
            Log.tool.info("TTL expired, enabled tools reset")
        }
        Log.tool.info("Tool TTL set: \(minutes) minutes")
    }

    func resetEnabled() {
        enabledNames.removeAll()
        ttlTask?.cancel()
        ttlTask = nil
        Log.tool.info("Tool registry reset to baseline")
    }

    func reset() {
        resetEnabled()
    }

    /// Returns summaries of non-baseline tools for system prompt injection.
    var nonBaselineToolSummaries: [(name: String, description: String, category: ToolCategory)] {
        allTools.values
            .filter { !$0.isBaseline }
            .map { (name: $0.name, description: $0.description, category: $0.category) }
            .sorted { $0.name < $1.name }
    }

    var enabledToolNames: Set<String> { enabledNames }

    var allToolNames: [String] { Array(allTools.keys).sorted() }

    /// Returns info about all registered tools for UI display
    var allToolInfos: [ToolInfo] {
        allTools.values.map { tool in
            let params = extractParams(from: tool.inputSchema)
            return ToolInfo(
                name: tool.name,
                description: tool.description,
                category: tool.category,
                isBaseline: tool.isBaseline,
                isEnabled: tool.isBaseline || enabledNames.contains(tool.name),
                parameters: params
            )
        }
        .sorted { $0.name < $1.name }
    }

    private func extractParams(from schema: [String: Any]) -> [ToolParamInfo] {
        guard let properties = schema["properties"] as? [String: Any] else { return [] }
        let required = Set((schema["required"] as? [String]) ?? [])

        return properties.compactMap { key, value in
            guard let prop = value as? [String: Any] else { return nil }
            let type = prop["type"] as? String ?? "any"
            let desc = prop["description"] as? String ?? ""
            return ToolParamInfo(name: key, type: type, description: desc, isRequired: required.contains(key))
        }
        .sorted { $0.name < $1.name }
    }
}

// MARK: - Tool Info (for UI)

struct ToolParamInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let type: String
    let description: String
    let isRequired: Bool
}

struct ToolInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let description: String
    let category: ToolCategory
    let isBaseline: Bool
    let isEnabled: Bool
    let parameters: [ToolParamInfo]

    var group: String {
        ToolGroupResolver.group(forToolName: name)
    }
}

enum ToolGroupResolver {
    static func normalizeGroupName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func group(forToolName name: String) -> String {
        let base = String(name.split(separator: ".").first ?? Substring(name)).lowercased()

        // 레거시 도구명을 논리적 그룹으로 정규화
        switch base {
        case "create_reminder", "list_reminders", "complete_reminder": return "reminders"
        case "set_timer", "list_timers", "cancel_timer": return "timer"
        case "set_alarm", "list_alarms", "cancel_alarm": return "alarm"
        case "save_memory", "update_memory": return "memory"
        case "set_current_user": return "profile"
        case "list_calendar_events", "create_calendar_event", "delete_calendar_event": return "calendar"
        case "web", "web_search": return "search"
        case "generate_image": return "image"
        case "print_image": return "image"
        case "open_url": return "url"
        case "calculate": return "calculator"
        case "datetime": return "datetime"
        case "update_base_system_prompt": return "context"
        default: return base
        }
    }
}

enum ToolGroupCatalog {
    struct Meta: Sendable {
        let icon: String
        let displayName: String
    }

    static let metadata: [String: Meta] = [
        "calendar": Meta(icon: "calendar", displayName: "캘린더"),
        "kanban": Meta(icon: "rectangle.3.group", displayName: "칸반"),
        "file": Meta(icon: "doc", displayName: "파일 관리"),
        "search": Meta(icon: "magnifyingglass", displayName: "웹 검색"),
        "shell": Meta(icon: "terminal", displayName: "터미널"),
        "clipboard": Meta(icon: "doc.on.clipboard", displayName: "클립보드"),
        "screenshot": Meta(icon: "camera.viewfinder", displayName: "스크린샷"),
        "git": Meta(icon: "arrow.triangle.branch", displayName: "Git"),
        "github": Meta(icon: "chevron.left.forwardslash.chevron.right", displayName: "GitHub"),
        "music": Meta(icon: "music.note", displayName: "음악"),
        "contacts": Meta(icon: "person.2", displayName: "연락처"),
        "image": Meta(icon: "photo", displayName: "이미지"),
        "reminders": Meta(icon: "checklist", displayName: "미리알림"),
        "timer": Meta(icon: "timer", displayName: "타이머"),
        "alarm": Meta(icon: "alarm", displayName: "알람"),
        "calculator": Meta(icon: "function", displayName: "계산기"),
        "datetime": Meta(icon: "clock", displayName: "날짜/시간"),
        "memory": Meta(icon: "brain", displayName: "기억"),
        "tools": Meta(icon: "wrench.and.screwdriver", displayName: "도구 관리"),
        "settings": Meta(icon: "gear", displayName: "설정"),
        "agent": Meta(icon: "person.badge.key", displayName: "에이전트"),
        "workspace": Meta(icon: "building.2", displayName: "워크스페이스"),
        "telegram": Meta(icon: "paperplane", displayName: "텔레그램"),
        "workflow": Meta(icon: "arrow.triangle.2.circlepath", displayName: "워크플로우"),
        "coding": Meta(icon: "chevron.left.forwardslash.chevron.right", displayName: "코딩 에이전트"),
        "finder": Meta(icon: "folder", displayName: "Finder"),
        "url": Meta(icon: "link", displayName: "URL 열기"),
        "mcp": Meta(icon: "server.rack", displayName: "MCP 서버"),
        "profile": Meta(icon: "person.crop.circle", displayName: "사용자 전환"),
        "context": Meta(icon: "doc.text", displayName: "시스템 프롬프트"),
    ]

    static var defaultGroups: [String] {
        metadata.keys.sorted()
    }

    static func icon(for group: String) -> String {
        metadata[normalize(group)]?.icon ?? "square.grid.2x2"
    }

    static func displayName(for group: String) -> String {
        metadata[normalize(group)]?.displayName ?? normalize(group)
    }

    static func normalize(_ group: String) -> String {
        ToolGroupResolver.normalizeGroupName(group)
    }

    static func normalizedUnique(_ groups: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []

        for raw in groups {
            let normalized = normalize(raw)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        return result
    }

    static func orderedGroups(from groups: [String]) -> [String] {
        normalizedUnique(groups)
            .sorted {
                displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
            }
    }

    static func groups(fromToolNames toolNames: [String]) -> [String] {
        let groups = toolNames.map { ToolGroupResolver.group(forToolName: $0) }
        return normalizedUnique(groups)
    }
}
