import Foundation

/// 프롬프트 파일 관리 서비스 프로토콜
/// - system.md: 페르소나 + 행동 지침
/// - memory.md: 사용자 기억 (레거시, fallback)
/// - family.md: 가족 공유 기억
/// - memory/{userId}.md: 개인 기억
/// - profiles.json: 사용자 프로필
@MainActor
protocol ContextServiceProtocol {
    // MARK: - System (페르소나 + 행동 지침)
    func loadSystem() -> String
    func saveSystem(_ content: String)
    var systemPath: String { get }

    // MARK: - Memory (레거시 사용자 기억)
    func loadMemory() -> String
    func saveMemory(_ content: String)
    func appendMemory(_ content: String)
    var memoryPath: String { get }
    var memorySize: Int { get }

    // MARK: - Family Memory (가족 공유 기억)
    func loadFamilyMemory() -> String
    func saveFamilyMemory(_ content: String)
    func appendFamilyMemory(_ content: String)

    // MARK: - User Memory (개인 기억)
    func loadUserMemory(userId: UUID) -> String
    func saveUserMemory(userId: UUID, content: String)
    func appendUserMemory(userId: UUID, content: String)

    // MARK: - Profiles (사용자 프로필)
    func loadProfiles() -> [UserProfile]
    func saveProfiles(_ profiles: [UserProfile])

    // MARK: - Base System Prompt (앱 레벨 기본 규칙)
    func loadBaseSystemPrompt() -> String
    func saveBaseSystemPrompt(_ content: String)
    var baseSystemPromptPath: String { get }

    // MARK: - Workspace
    func listWorkspaces() -> [Workspace]
    func loadWorkspaceConfig(id: UUID) -> Workspace?
    func saveWorkspaceConfig(_ workspace: Workspace)
    
    // MARK: - Workspace Memory (워크스페이스 공유 기억)
    func loadWorkspaceMemory(workspaceId: UUID) -> String
    func saveWorkspaceMemory(workspaceId: UUID, content: String)
    func appendWorkspaceMemory(workspaceId: UUID, content: String)

    // MARK: - Agent Persona (에이전트별 페르소나 - 워크스페이스 종속)
    func loadAgentPersona(workspaceId: UUID, agentName: String) -> String
    func saveAgentPersona(workspaceId: UUID, agentName: String, content: String)

    // MARK: - Agent Memory (에이전트별 기억 - 워크스페이스 종속)
    func loadAgentMemory(workspaceId: UUID, agentName: String) -> String
    func saveAgentMemory(workspaceId: UUID, agentName: String, content: String)
    func appendAgentMemory(workspaceId: UUID, agentName: String, content: String)

    // MARK: - Agent Config (에이전트 설정 - 워크스페이스 종속)
    func loadAgentConfig(workspaceId: UUID, agentName: String) -> AgentConfig?
    func saveAgentConfig(workspaceId: UUID, config: AgentConfig)

    // MARK: - Agent Management
    func listAgents(workspaceId: UUID) -> [String]
    func createAgent(workspaceId: UUID, name: String, wakeWord: String, description: String)
    
    // MARK: - Migration
    func migrateToWorkspaceStructure()
    
    // Deprecated methods (temporarily kept for build compatibility during refactoring)
    func loadAgentPersona(agentName: String) -> String
    func saveAgentPersona(agentName: String, content: String)
    func loadAgentMemory(agentName: String) -> String
    func saveAgentMemory(agentName: String, content: String)
    func appendAgentMemory(agentName: String, content: String)
    func loadAgentConfig(agentName: String) -> AgentConfig?
    func saveAgentConfig(_ config: AgentConfig)
    func listAgents() -> [String]
    func createAgent(name: String, wakeWord: String, description: String)
    func migrateIfNeeded()
    func migrateToAgentStructure(currentWakeWord: String)
}
