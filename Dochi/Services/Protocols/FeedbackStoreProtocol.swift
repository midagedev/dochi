import Foundation

/// 피드백 저장소 프로토콜 (I-4)
@MainActor
protocol FeedbackStoreProtocol {
    /// 피드백 항목 목록
    var entries: [FeedbackEntry] { get }

    /// 피드백 추가
    func add(_ entry: FeedbackEntry)

    /// 메시지 ID로 피드백 삭제
    func remove(messageId: UUID)

    /// 메시지 ID로 피드백 등급 조회
    func rating(for messageId: UUID) -> FeedbackRating?

    /// 모델별/에이전트별 만족도 비율 (필터 옵션)
    func satisfactionRate(model: String?, agent: String?) -> Double

    /// 최근 부정 피드백 조회
    func recentNegative(limit: Int) -> [FeedbackEntry]

    /// 모델별 만족도 분석
    func modelBreakdown() -> [ModelSatisfaction]

    /// 에이전트별 만족도 분석
    func agentBreakdown() -> [AgentSatisfaction]

    /// 카테고리별 분포
    func categoryDistribution() -> [CategoryCount]
}
