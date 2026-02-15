import Foundation

/// K-2: 프로액티브 제안 서비스 프로토콜
@MainActor
protocol ProactiveSuggestionServiceProtocol: AnyObject {
    /// 현재 표시 중인 제안
    var currentSuggestion: ProactiveSuggestion? { get }
    /// 제안 기록 (최대 20건 FIFO)
    var suggestionHistory: [ProactiveSuggestion] { get }
    /// 서비스 상태
    var state: ProactiveSuggestionState { get }
    /// 일시 중지 여부
    var isPaused: Bool { get set }
    /// 제안 토스트 이벤트
    var toastEvents: [SuggestionToastEvent] { get }

    /// 사용자 활동 기록 (idle 타이머 리셋)
    func recordActivity()
    /// 제안 수락 → suggestedPrompt를 대화에 전송
    func acceptSuggestion(_ suggestion: ProactiveSuggestion)
    /// 제안을 나중에로 보관 (deferred)
    func deferSuggestion(_ suggestion: ProactiveSuggestion)
    /// 해당 유형의 제안을 비활성화 (dismissed)
    func dismissSuggestionType(_ suggestion: ProactiveSuggestion)
    /// 토스트 이벤트 제거
    func dismissToast(id: UUID)
    /// 서비스 시작
    func start()
    /// 서비스 중지
    func stop()
}
