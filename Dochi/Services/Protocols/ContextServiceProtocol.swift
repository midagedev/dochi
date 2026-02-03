import Foundation

/// 프롬프트 파일 관리 서비스 프로토콜
/// - system.md: 페르소나 + 행동 지침
/// - memory.md: 사용자 기억
protocol ContextServiceProtocol {
    // MARK: - System (페르소나 + 행동 지침)
    func loadSystem() -> String
    func saveSystem(_ content: String)
    var systemPath: String { get }

    // MARK: - Memory (사용자 기억)
    func loadMemory() -> String
    func saveMemory(_ content: String)
    func appendMemory(_ content: String)
    var memoryPath: String { get }
    var memorySize: Int { get }

    // MARK: - Migration
    func migrateIfNeeded()
}
