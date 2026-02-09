import Foundation
@testable import Dochi

@MainActor
final class MockContextService: ContextServiceProtocol {
    var systemContent: String = ""
    var memoryContent: String = ""
    var familyMemoryContent: String = ""
    var userMemories: [UUID: String] = [:]
    var profiles: [UserProfile] = []
    var migrateIfNeededCalled = false

    func loadSystem() -> String {
        systemContent
    }

    func saveSystem(_ content: String) {
        systemContent = content
    }

    var systemPath: String {
        "/mock/system.md"
    }

    func loadMemory() -> String {
        memoryContent
    }

    func saveMemory(_ content: String) {
        memoryContent = content
    }

    func appendMemory(_ content: String) {
        if !memoryContent.isEmpty && !memoryContent.hasSuffix("\n") {
            memoryContent += "\n"
        }
        memoryContent += content
    }

    var memoryPath: String {
        "/mock/memory.md"
    }

    var memorySize: Int {
        memoryContent.utf8.count
    }

    // MARK: - Family Memory

    func loadFamilyMemory() -> String {
        familyMemoryContent
    }

    func saveFamilyMemory(_ content: String) {
        familyMemoryContent = content
    }

    func appendFamilyMemory(_ content: String) {
        if !familyMemoryContent.isEmpty && !familyMemoryContent.hasSuffix("\n") {
            familyMemoryContent += "\n"
        }
        familyMemoryContent += content
    }

    // MARK: - User Memory

    func loadUserMemory(userId: UUID) -> String {
        userMemories[userId] ?? ""
    }

    func saveUserMemory(userId: UUID, content: String) {
        userMemories[userId] = content
    }

    func appendUserMemory(userId: UUID, content: String) {
        var current = userMemories[userId] ?? ""
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        userMemories[userId] = current
    }

    // MARK: - Profiles

    func loadProfiles() -> [UserProfile] {
        profiles
    }

    func saveProfiles(_ newProfiles: [UserProfile]) {
        profiles = newProfiles
    }

    // MARK: - Base System Prompt

    var baseSystemPromptContent: String = ""

    func loadBaseSystemPrompt() -> String {
        baseSystemPromptContent
    }

    func saveBaseSystemPrompt(_ content: String) {
        baseSystemPromptContent = content
    }

    var baseSystemPromptPath: String {
        "/mock/system_prompt.md"
    }

    // MARK: - Agent Persona

    var agentPersonas: [String: String] = [:]

    func loadAgentPersona(agentName: String) -> String {
        agentPersonas[agentName] ?? ""
    }

    func saveAgentPersona(agentName: String, content: String) {
        agentPersonas[agentName] = content
    }

    // MARK: - Agent Memory

    var agentMemories: [String: String] = [:]

    func loadAgentMemory(agentName: String) -> String {
        agentMemories[agentName] ?? ""
    }

    func saveAgentMemory(agentName: String, content: String) {
        agentMemories[agentName] = content
    }

    func appendAgentMemory(agentName: String, content: String) {
        var current = agentMemories[agentName] ?? ""
        if !current.isEmpty && !current.hasSuffix("\n") {
            current += "\n"
        }
        current += content
        agentMemories[agentName] = current
    }

    // MARK: - Agent Config

    var agentConfigs: [String: AgentConfig] = [:]

    func loadAgentConfig(agentName: String) -> AgentConfig? {
        agentConfigs[agentName]
    }

    func saveAgentConfig(_ config: AgentConfig) {
        agentConfigs[config.name] = config
    }

    // MARK: - Agent Management

    func listAgents() -> [String] {
        Array(agentConfigs.keys).sorted()
    }

    func createAgent(name: String, wakeWord: String, description: String) {
        agentConfigs[name] = AgentConfig(name: name, wakeWord: wakeWord, description: description)
        if agentPersonas[name] == nil {
            agentPersonas[name] = Constants.Agent.defaultPersona
        }
    }

    // MARK: - Migration

    var migrateToAgentStructureCalled = false

    func migrateIfNeeded() {
        migrateIfNeededCalled = true
    }

    func migrateToAgentStructure(currentWakeWord: String) {
        migrateToAgentStructureCalled = true
    }
}
