import Foundation

@MainActor
protocol ContextServiceProtocol {
    // Base prompt
    func loadBaseSystemPrompt() -> String?
    func saveBaseSystemPrompt(_ content: String)

    // Profiles
    func loadProfiles() -> [UserProfile]
    func saveProfiles(_ profiles: [UserProfile])

    // User memory
    func loadUserMemory(userId: String) -> String?
    func saveUserMemory(userId: String, content: String)
    func appendUserMemory(userId: String, content: String)

    // Workspace memory
    func loadWorkspaceMemory(workspaceId: UUID) -> String?
    func saveWorkspaceMemory(workspaceId: UUID, content: String)
    func appendWorkspaceMemory(workspaceId: UUID, content: String)

    // Agent persona
    func loadAgentPersona(workspaceId: UUID, agentName: String) -> String?
    func saveAgentPersona(workspaceId: UUID, agentName: String, content: String)

    // Agent memory
    func loadAgentMemory(workspaceId: UUID, agentName: String) -> String?
    func saveAgentMemory(workspaceId: UUID, agentName: String, content: String)
    func appendAgentMemory(workspaceId: UUID, agentName: String, content: String)

    // Agent config
    func loadAgentConfig(workspaceId: UUID, agentName: String) -> AgentConfig?
    func saveAgentConfig(workspaceId: UUID, config: AgentConfig)
    func listAgents(workspaceId: UUID) -> [String]
    func createAgent(workspaceId: UUID, name: String, wakeWord: String?, description: String?)

    // Workspace management
    func listLocalWorkspaces() -> [UUID]
    func createLocalWorkspace(id: UUID)
    func deleteLocalWorkspace(id: UUID)
    func deleteAgent(workspaceId: UUID, name: String)

    // Snapshots (for context compression)
    func saveWorkspaceMemorySnapshot(workspaceId: UUID, content: String)
    func saveAgentMemorySnapshot(workspaceId: UUID, agentName: String, content: String)
    func saveUserMemorySnapshot(userId: String, content: String)

    // Migration
    func migrateIfNeeded()
}
