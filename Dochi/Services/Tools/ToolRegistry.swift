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
}
