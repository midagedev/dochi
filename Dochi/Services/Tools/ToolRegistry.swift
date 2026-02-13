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
    /// Baseline tools are always included; enabled (non-baseline) tools are included if their category is permitted.
    func availableTools(for permissions: [String]) -> [any BuiltInToolProtocol] {
        let permissionSet = Set(permissions)
        return allTools.values.filter { tool in
            guard permissionSet.contains(tool.category.rawValue) else { return false }
            return tool.isBaseline || enabledNames.contains(tool.name)
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
        String(name.split(separator: ".").first ?? Substring(name))
    }
}
