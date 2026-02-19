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

    // Project context (repo-level)
    func listProjects(workspaceId: UUID) -> [ProjectContext]
    func loadProject(workspaceId: UUID, projectId: String) -> ProjectContext?
    func saveProject(workspaceId: UUID, project: ProjectContext)
    func removeProject(workspaceId: UUID, projectId: String)
    func registerProject(workspaceId: UUID, repoRootPath: String, defaultBranch: String?) -> ProjectContext
    func loadProjectMemory(workspaceId: UUID, projectId: String) -> String?
    func saveProjectMemory(workspaceId: UUID, projectId: String, content: String)
    func appendProjectMemory(workspaceId: UUID, projectId: String, content: String)

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
    func loadAgentConfigData(workspaceId: UUID, agentName: String) -> Data?
    func saveAgentConfigData(workspaceId: UUID, agentName: String, data: Data)
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

    // Conversation tags
    func loadTags() -> [ConversationTag]
    func saveTags(_ tags: [ConversationTag])

    // Conversation folders
    func loadFolders() -> [ConversationFolder]
    func saveFolders(_ folders: [ConversationFolder])

    // Agent templates
    func loadCustomTemplates() -> [AgentTemplate]
    func saveCustomTemplates(_ templates: [AgentTemplate])

    // Migration
    func migrateIfNeeded()
}

extension ContextServiceProtocol {
    func listProjects(workspaceId: UUID) -> [ProjectContext] { [] }

    func loadProject(workspaceId: UUID, projectId: String) -> ProjectContext? { nil }

    func saveProject(workspaceId: UUID, project: ProjectContext) {}

    func removeProject(workspaceId: UUID, projectId: String) {}

    func registerProject(workspaceId: UUID, repoRootPath: String, defaultBranch: String?) -> ProjectContext {
        ProjectContext(repoRootPath: repoRootPath, defaultBranch: defaultBranch)
    }

    func loadProjectMemory(workspaceId: UUID, projectId: String) -> String? { nil }

    func saveProjectMemory(workspaceId: UUID, projectId: String, content: String) {}

    func appendProjectMemory(workspaceId: UUID, projectId: String, content: String) {}

    func loadAgentConfigData(workspaceId: UUID, agentName: String) -> Data? { nil }

    func saveAgentConfigData(workspaceId: UUID, agentName: String, data: Data) {}
}
