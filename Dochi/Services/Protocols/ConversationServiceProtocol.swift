import Foundation

/// 대화 히스토리 저장 서비스 프로토콜
@MainActor
protocol ConversationServiceProtocol {
    /// 전체 대화 목록 반환 (updatedAt 내림차순)
    func list() -> [Conversation]

    /// 단일 대화 로드
    func load(id: UUID) -> Conversation?

    /// 대화 저장
    func save(_ conversation: Conversation)

    /// 대화 삭제
    func delete(id: UUID)
}
