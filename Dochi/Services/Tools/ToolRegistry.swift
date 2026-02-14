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
        let base = String(name.split(separator: ".").first ?? Substring(name))
        // 레거시 도구명을 논리적 그룹으로 정규화
        switch base {
        case "create_reminder", "list_reminders", "complete_reminder": return "reminders"
        case "set_timer", "list_timers", "cancel_timer": return "timer"
        case "set_alarm", "list_alarms", "cancel_alarm": return "alarm"
        case "save_memory", "update_memory": return "memory"
        case "set_current_user": return "profile"
        case "list_calendar_events", "create_calendar_event", "delete_calendar_event": return "calendar"
        case "web_search": return "search"
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
