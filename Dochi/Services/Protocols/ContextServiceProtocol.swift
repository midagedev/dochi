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

    // MARK: - Agent Persona (에이전트별 페르소나)
    func loadAgentPersona(agentName: String) -> String
    func saveAgentPersona(agentName: String, content: String)

    // MARK: - Agent Memory (에이전트별 기억)
    func loadAgentMemory(agentName: String) -> String
    func saveAgentMemory(agentName: String, content: String)
    func appendAgentMemory(agentName: String, content: String)

    // MARK: - Agent Config (에이전트 설정)
    func loadAgentConfig(agentName: String) -> AgentConfig?
    func saveAgentConfig(_ config: AgentConfig)

    // MARK: - Agent Management
    func listAgents() -> [String]
    func createAgent(name: String, wakeWord: String, description: String)

    // MARK: - Migration
    func migrateIfNeeded()
    func migrateToAgentStructure(currentWakeWord: String)
}
