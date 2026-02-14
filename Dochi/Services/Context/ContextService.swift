import Foundation
import os

@MainActor
final class ContextService: ContextServiceProtocol {
    private let baseURL: URL

    init() {
        self.baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        ensureDirectories()
    }

    /// Testable init with custom base directory.
    init(baseURL: URL) {
        self.baseURL = baseURL
        ensureDirectories()
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        let dirs = [
            baseURL,
            baseURL.appendingPathComponent("memory"),
            baseURL.appendingPathComponent("workspaces")
        ]
        for dir in dirs {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Base prompt

    func loadBaseSystemPrompt() -> String? {
        let url = baseURL.appendingPathComponent("system_prompt.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveBaseSystemPrompt(_ content: String) {
        let url = baseURL.appendingPathComponent("system_prompt.md")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("Failed to save base system prompt: \(error.localizedDescription)")
        }
    }

    // MARK: - Profiles

    func loadProfiles() -> [UserProfile] {
        let url = baseURL.appendingPathComponent("profiles.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UserProfile].self, from: data)) ?? []
    }

    func saveProfiles(_ profiles: [UserProfile]) {
        let url = baseURL.appendingPathComponent("profiles.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profiles)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.storage.error("Failed to save profiles: \(error.localizedDescription)")
        }
    }

    // MARK: - User memory

    func loadUserMemory(userId: String) -> String? {
        let url = baseURL.appendingPathComponent("memory/\(userId).md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveUserMemory(userId: String, content: String) {
        let url = baseURL.appendingPathComponent("memory/\(userId).md")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("Failed to save user memory: \(error.localizedDescription)")
        }
    }

    func appendUserMemory(userId: String, content: String) {
        let existing = loadUserMemory(userId: userId) ?? ""
        saveUserMemory(userId: userId, content: existing + "\n" + content)
    }

    // MARK: - Workspace memory

    func loadWorkspaceMemory(workspaceId: UUID) -> String? {
        let url = workspaceURL(workspaceId).appendingPathComponent("memory.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveWorkspaceMemory(workspaceId: UUID, content: String) {
        let url = workspaceURL(workspaceId).appendingPathComponent("memory.md")
        do {
            try? FileManager.default.createDirectory(at: workspaceURL(workspaceId), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("Failed to save workspace memory: \(error.localizedDescription)")
        }
    }

    func appendWorkspaceMemory(workspaceId: UUID, content: String) {
        let existing = loadWorkspaceMemory(workspaceId: workspaceId) ?? ""
        saveWorkspaceMemory(workspaceId: workspaceId, content: existing + "\n" + content)
    }

    // MARK: - Agent persona

    func loadAgentPersona(workspaceId: UUID, agentName: String) -> String? {
        let url = agentURL(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("persona.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveAgentPersona(workspaceId: UUID, agentName: String, content: String) {
        let url = agentURL(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("persona.md")
        do {
            try? FileManager.default.createDirectory(at: agentURL(workspaceId: workspaceId, agentName: agentName), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("Failed to save agent persona: \(error.localizedDescription)")
        }
    }

    // MARK: - Agent memory

    func loadAgentMemory(workspaceId: UUID, agentName: String) -> String? {
        let url = agentURL(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("memory.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func saveAgentMemory(workspaceId: UUID, agentName: String, content: String) {
        let url = agentURL(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("memory.md")
        do {
            try? FileManager.default.createDirectory(at: agentURL(workspaceId: workspaceId, agentName: agentName), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.storage.error("Failed to save agent memory: \(error.localizedDescription)")
        }
    }

    func appendAgentMemory(workspaceId: UUID, agentName: String, content: String) {
        let existing = loadAgentMemory(workspaceId: workspaceId, agentName: agentName) ?? ""
        saveAgentMemory(workspaceId: workspaceId, agentName: agentName, content: existing + "\n" + content)
    }

    // MARK: - Agent config

    func loadAgentConfig(workspaceId: UUID, agentName: String) -> AgentConfig? {
        let url = agentURL(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentConfig.self, from: data)
    }

    func saveAgentConfig(workspaceId: UUID, config: AgentConfig) {
        let url = agentURL(workspaceId: workspaceId, agentName: config.name).appendingPathComponent("config.json")
        do {
            try? FileManager.default.createDirectory(at: agentURL(workspaceId: workspaceId, agentName: config.name), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.storage.error("Failed to save agent config: \(error.localizedDescription)")
        }
    }

    func listAgents(workspaceId: UUID) -> [String] {
        let agentsDir = workspaceURL(workspaceId).appendingPathComponent("agents")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: agentsDir.path) else { return [] }
        return contents.filter { !$0.hasPrefix(".") }.sorted()
    }

    func createAgent(workspaceId: UUID, name: String, wakeWord: String?, description: String?) {
        let config = AgentConfig(name: name, wakeWord: wakeWord, description: description)
        saveAgentConfig(workspaceId: workspaceId, config: config)
        Log.storage.info("Created agent: \(name) in workspace \(workspaceId)")
    }

    // MARK: - Workspace management

    func listLocalWorkspaces() -> [UUID] {
        let wsDir = baseURL.appendingPathComponent("workspaces")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: wsDir.path) else { return [] }
        return contents.compactMap { UUID(uuidString: $0) }.sorted { $0.uuidString < $1.uuidString }
    }

    func createLocalWorkspace(id: UUID) {
        let wsURL = workspaceURL(id)
        try? FileManager.default.createDirectory(at: wsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: wsURL.appendingPathComponent("agents"), withIntermediateDirectories: true)
        Log.storage.info("Created local workspace: \(id)")
    }

    func deleteLocalWorkspace(id: UUID) {
        let wsURL = workspaceURL(id)
        try? FileManager.default.removeItem(at: wsURL)
        Log.storage.info("Deleted local workspace: \(id)")
    }

    func deleteAgent(workspaceId: UUID, name: String) {
        let url = agentURL(workspaceId: workspaceId, agentName: name)
        try? FileManager.default.removeItem(at: url)
        Log.storage.info("Deleted agent: \(name) from workspace \(workspaceId)")
    }

    // MARK: - Snapshots (for context compression)

    func saveWorkspaceMemorySnapshot(workspaceId: UUID, content: String) {
        let url = workspaceURL(workspaceId).appendingPathComponent("memory.md.snapshot")
        do {
            try? FileManager.default.createDirectory(at: workspaceURL(workspaceId), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            Log.storage.info("Saved workspace memory snapshot for \(workspaceId)")
        } catch {
            Log.storage.error("Failed to save workspace memory snapshot: \(error.localizedDescription)")
        }
    }

    func saveAgentMemorySnapshot(workspaceId: UUID, agentName: String, content: String) {
        let url = agentURL(workspaceId: workspaceId, agentName: agentName).appendingPathComponent("memory.md.snapshot")
        do {
            try? FileManager.default.createDirectory(at: agentURL(workspaceId: workspaceId, agentName: agentName), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            Log.storage.info("Saved agent memory snapshot for \(agentName) in \(workspaceId)")
        } catch {
            Log.storage.error("Failed to save agent memory snapshot: \(error.localizedDescription)")
        }
    }

    func saveUserMemorySnapshot(userId: String, content: String) {
        let url = baseURL.appendingPathComponent("memory/\(userId).md.snapshot")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            Log.storage.info("Saved user memory snapshot for \(userId)")
        } catch {
            Log.storage.error("Failed to save user memory snapshot: \(error.localizedDescription)")
        }
    }

    // MARK: - Conversation Tags

    func loadTags() -> [ConversationTag] {
        let url = baseURL.appendingPathComponent("conversation_tags.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ConversationTag].self, from: data)) ?? []
    }

    func saveTags(_ tags: [ConversationTag]) {
        let url = baseURL.appendingPathComponent("conversation_tags.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(tags)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.storage.error("Failed to save conversation tags: \(error.localizedDescription)")
        }
    }

    // MARK: - Conversation Folders

    func loadFolders() -> [ConversationFolder] {
        let url = baseURL.appendingPathComponent("conversation_folders.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ConversationFolder].self, from: data)) ?? []
    }

    func saveFolders(_ folders: [ConversationFolder]) {
        let url = baseURL.appendingPathComponent("conversation_folders.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(folders)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.storage.error("Failed to save conversation folders: \(error.localizedDescription)")
        }
    }

    // MARK: - Migration

    func migrateIfNeeded() {
        // TODO: Phase 1 — migrate legacy files (system.md → system_prompt.md, etc.)
        Log.storage.info("Migration check completed")
    }

    // MARK: - Helpers

    private func workspaceURL(_ workspaceId: UUID) -> URL {
        baseURL.appendingPathComponent("workspaces/\(workspaceId.uuidString)")
    }

    private func agentURL(workspaceId: UUID, agentName: String) -> URL {
        workspaceURL(workspaceId).appendingPathComponent("agents/\(agentName)")
    }
}
