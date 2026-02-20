import Foundation

/// Persistent store for tool usage context and preference profiles.
/// Storage path: `{baseURL}/tool_context.json`
@MainActor
final class ToolContextStore: ToolContextStoreProtocol {
    private let fileURL: URL
    private var cache: ToolContextFile?
    private var isDirty = false
    private var saveTask: Task<Void, Never>?

    private static let debounceInterval: TimeInterval = 5.0
    private static let maxRecentEvents = 300
    private static let scoreDecayHalfLifeDays: Double = 7.0

    init(baseURL: URL) {
        self.fileURL = baseURL.appendingPathComponent("tool_context.json")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func record(_ event: ToolUsageEvent) async {
        var file = await load()
        let profileKey = Self.profileKey(workspaceId: event.workspaceId, agentName: event.agentName)
        var profile = file.profiles[profileKey] ?? ToolContextProfile(
            agentName: event.agentName,
            workspaceId: event.workspaceId,
            lastUpdatedAt: event.timestamp
        )

        applyDecay(to: &profile, now: event.timestamp)

        let normalizedCategory = ToolGroupResolver.normalizeGroupName(event.category)
        if !normalizedCategory.isEmpty {
            profile.categoryScores[normalizedCategory, default: 0] += event.decision.scoreDelta
        }

        let normalizedToolName = event.toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedToolName.isEmpty {
            profile.toolScores[normalizedToolName, default: 0] += event.decision.scoreDelta
        }

        profile.lastUpdatedAt = event.timestamp
        file.profiles[profileKey] = profile

        file.recentEvents.append(event)
        if file.recentEvents.count > Self.maxRecentEvents {
            file.recentEvents.removeFirst(file.recentEvents.count - Self.maxRecentEvents)
        }

        cache = file
        isDirty = true
        scheduleSave()
    }

    func profile(workspaceId: String, agentName: String) async -> ToolContextProfile? {
        let file = await load()
        let key = Self.profileKey(workspaceId: workspaceId, agentName: agentName)
        return file.profiles[key]
    }

    func userPreference(workspaceId: String) async -> UserToolPreference {
        let file = await load()
        return file.userPreferences[workspaceId] ?? UserToolPreference()
    }

    func updateUserPreference(_ preference: UserToolPreference, workspaceId: String) async {
        var file = await load()
        file.userPreferences[workspaceId] = preference
        cache = file
        isDirty = true
        scheduleSave()
    }

    func flushToDisk() async {
        guard isDirty else { return }
        guard let file = cache else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
            isDirty = false
            Log.storage.debug("Tool context saved to disk")
        } catch {
            Log.storage.error("Failed to save tool context: \(error.localizedDescription)")
        }
    }
}

private extension ToolContextStore {
    func load() async -> ToolContextFile {
        if let cache {
            return cache
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = .empty
            return .empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(ToolContextFile.self, from: data)
            cache = decoded
            return decoded
        } catch {
            Log.storage.error("Failed to load tool context: \(error.localizedDescription)")
            cache = .empty
            return .empty
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.debounceInterval))
            guard !Task.isCancelled else { return }
            await self?.flushToDisk()
        }
    }

    static func profileKey(workspaceId: String, agentName: String) -> String {
        "\(workspaceId)::\(agentName)"
    }

    func applyDecay(to profile: inout ToolContextProfile, now: Date) {
        let elapsed = max(0, now.timeIntervalSince(profile.lastUpdatedAt))
        guard elapsed > 0 else { return }

        let elapsedDays = elapsed / 86_400.0
        let factor = pow(0.5, elapsedDays / Self.scoreDecayHalfLifeDays)

        profile.categoryScores = profile.categoryScores.reduce(into: [:]) { partial, entry in
            let decayed = entry.value * factor
            if abs(decayed) > 0.0001 {
                partial[entry.key] = decayed
            }
        }

        profile.toolScores = profile.toolScores.reduce(into: [:]) { partial, entry in
            let decayed = entry.value * factor
            if abs(decayed) > 0.0001 {
                partial[entry.key] = decayed
            }
        }
    }
}
