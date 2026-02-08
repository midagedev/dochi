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

    // MARK: - Migration
    func migrateIfNeeded()
}
