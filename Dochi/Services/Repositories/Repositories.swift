import Foundation

// MARK: - Agent Repository

@MainActor
protocol AgentRepository {
    func listAgents(workspaceId: UUID?) -> [String]
    func createAgent(workspaceId: UUID?, name: String, wakeWord: String, description: String)
    func getPersona(workspaceId: UUID?, name: String) -> String
    func setPersona(workspaceId: UUID?, name: String, content: String)
    func getMemory(workspaceId: UUID?, name: String) -> String
    func setMemory(workspaceId: UUID?, name: String, content: String)
    func appendMemory(workspaceId: UUID?, name: String, content: String)
    func getConfig(workspaceId: UUID?, name: String) -> AgentConfig?
    func setConfig(workspaceId: UUID?, config: AgentConfig)
}

@MainActor
struct LocalAgentRepository: AgentRepository {
    let context: ContextServiceProtocol

    func listAgents(workspaceId: UUID?) -> [String] {
        if let id = workspaceId { return context.listAgents(workspaceId: id) }
        return context.listAgents()
    }

    func createAgent(workspaceId: UUID?, name: String, wakeWord: String, description: String) {
        if let id = workspaceId { context.createAgent(workspaceId: id, name: name, wakeWord: wakeWord, description: description) }
        else { context.createAgent(name: name, wakeWord: wakeWord, description: description) }
    }

    func getPersona(workspaceId: UUID?, name: String) -> String {
        if let id = workspaceId { return context.loadAgentPersona(workspaceId: id, agentName: name) }
        return context.loadAgentPersona(agentName: name)
    }

    func setPersona(workspaceId: UUID?, name: String, content: String) {
        if let id = workspaceId { context.saveAgentPersona(workspaceId: id, agentName: name, content: content) }
        else { context.saveAgentPersona(agentName: name, content: content) }
    }

    func getMemory(workspaceId: UUID?, name: String) -> String {
        if let id = workspaceId { return context.loadAgentMemory(workspaceId: id, agentName: name) }
        return context.loadAgentMemory(agentName: name)
    }

    func setMemory(workspaceId: UUID?, name: String, content: String) {
        if let id = workspaceId { context.saveAgentMemory(workspaceId: id, agentName: name, content: content) }
        else { context.saveAgentMemory(agentName: name, content: content) }
    }

    func appendMemory(workspaceId: UUID?, name: String, content: String) {
        if let id = workspaceId { context.appendAgentMemory(workspaceId: id, agentName: name, content: content) }
        else { context.appendAgentMemory(agentName: name, content: content) }
    }

    func getConfig(workspaceId: UUID?, name: String) -> AgentConfig? {
        if let id = workspaceId { return context.loadAgentConfig(workspaceId: id, agentName: name) }
        return context.loadAgentConfig(agentName: name)
    }

    func setConfig(workspaceId: UUID?, config: AgentConfig) {
        if let id = workspaceId { context.saveAgentConfig(workspaceId: id, config: config) }
        else { context.saveAgentConfig(config) }
    }
}

// MARK: - Workspace Repository

@MainActor
protocol WorkspaceRepository {
    func create(name: String) async throws -> Workspace
    func join(inviteCode: String) async throws -> Workspace
    func list() async throws -> [Workspace]
    func switchTo(id: UUID) async throws -> Workspace
    func regenerateInviteCode(id: UUID) async throws -> String
}

@MainActor
struct CloudWorkspaceRepository: WorkspaceRepository {
    let service: SupabaseServiceProtocol

    func create(name: String) async throws -> Workspace { try await service.createWorkspace(name: name) }
    func join(inviteCode: String) async throws -> Workspace { try await service.joinWorkspace(inviteCode: inviteCode) }
    func list() async throws -> [Workspace] { try await service.listWorkspaces() }
    func switchTo(id: UUID) async throws -> Workspace {
        let workspaces = try await list()
        guard let ws = workspaces.first(where: { $0.id == id }) else { throw SupabaseError.invalidInviteCode }
        await service.setCurrentWorkspace(ws)
        return ws
    }
    func regenerateInviteCode(id: UUID) async throws -> String { try await service.regenerateInviteCode(workspaceId: id) }
}

// MARK: - Auth Repository

@MainActor
protocol AuthRepository {
    var authState: AuthState { get }
    func restoreSession() async
    func signOut() async throws
}

@MainActor
struct CloudAuthRepository: AuthRepository {
    let service: SupabaseServiceProtocol
    var authState: AuthState { service.authState }
    func restoreSession() async { await service.restoreSession() }
    func signOut() async throws { try await service.signOut() }
}
