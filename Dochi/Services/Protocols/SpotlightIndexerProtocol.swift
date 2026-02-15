import Foundation

/// Spotlight 인덱싱 서비스 프로토콜 (H-4)
@MainActor
protocol SpotlightIndexerProtocol {
    /// 인덱싱된 항목 수
    var indexedItemCount: Int { get }

    /// 전체 재구축 진행 중 여부
    var isRebuilding: Bool { get }

    /// 전체 재구축 진행률 (0.0~1.0)
    var rebuildProgress: Double { get }

    /// 마지막 인덱싱 시각
    var lastIndexedAt: Date? { get }

    /// 대화를 Spotlight 인덱스에 추가
    func indexConversation(_ conversation: Conversation)

    /// 대화를 Spotlight 인덱스에서 제거
    func removeConversation(id: UUID)

    /// 메모리를 Spotlight 인덱스에 추가
    func indexMemory(scope: String, identifier: String, title: String, content: String)

    /// 메모리를 Spotlight 인덱스에서 제거
    func removeMemory(identifier: String)

    /// 전체 인덱스 재구축
    func rebuildAllIndices(conversations: [Conversation], contextService: ContextServiceProtocol, sessionContext: SessionContext) async

    /// 모든 인덱스 삭제
    func clearAllIndices() async
}
