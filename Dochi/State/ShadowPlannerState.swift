import Foundation

// MARK: - Shadow Planner State Machine

/// Shadow sub-agent planner의 상태 머신.
///
/// 상태 전이:
/// ```
/// idle -> triggered -> shadowPlanning -> parentDecision -> parentExecution -> closed
/// ```
///
/// 실패 경로:
/// ```
/// shadowPlanning -> plannerTimeout -> parentFallback -> closed
/// shadowPlanning -> plannerError -> parentFallback -> closed
/// ```
enum ShadowPlannerState: String, Sendable, Codable, CaseIterable {
    /// 초기 상태 (대기 중)
    case idle
    /// 트리거 조건 충족, spawn 준비 중
    case triggered
    /// Shadow planner 실행 중
    case shadowPlanning
    /// Planner 결과 수신, 부모 결정 대기
    case parentDecision
    /// 부모가 planner 결과 기반으로 tool 실행 중
    case parentExecution
    /// Planner 타임아웃으로 인한 부모 fallback
    case plannerTimeout
    /// Planner 에러로 인한 부모 fallback
    case plannerError
    /// 부모 fallback 실행 중
    case parentFallback
    /// 완료 (정상 또는 fallback)
    case closed

    // MARK: - Transition Validation

    /// 현재 상태에서 전이할 수 있는 유효한 다음 상태 목록.
    var validTransitions: Set<ShadowPlannerState> {
        switch self {
        case .idle:
            return [.triggered]
        case .triggered:
            return [.shadowPlanning, .closed]
        case .shadowPlanning:
            return [.parentDecision, .plannerTimeout, .plannerError]
        case .parentDecision:
            return [.parentExecution, .parentFallback, .closed]
        case .parentExecution:
            return [.closed]
        case .plannerTimeout:
            return [.parentFallback]
        case .plannerError:
            return [.parentFallback]
        case .parentFallback:
            return [.closed]
        case .closed:
            return [] // terminal state
        }
    }

    /// 지정한 상태로 전이가 가능한지 검사한다.
    func canTransition(to next: ShadowPlannerState) -> Bool {
        validTransitions.contains(next)
    }

    /// Terminal 상태인지 여부.
    var isTerminal: Bool {
        self == .closed
    }

    /// 에러 경로에 있는 상태인지 여부.
    var isErrorPath: Bool {
        switch self {
        case .plannerTimeout, .plannerError, .parentFallback:
            return true
        default:
            return false
        }
    }

    /// 활성 상태 (작업 진행 중)인지 여부.
    var isActive: Bool {
        switch self {
        case .idle, .closed:
            return false
        default:
            return true
        }
    }
}

// MARK: - State Machine Manager

/// Shadow planner 상태 전이를 관리하는 값 타입.
///
/// 유효하지 않은 전이를 시도하면 `false`를 반환하고 상태를 변경하지 않는다.
struct ShadowPlannerStateMachine: Sendable {
    /// 현재 상태
    private(set) var state: ShadowPlannerState = .idle

    /// 상태 전이 이력 (디버깅 용도)
    private(set) var transitionHistory: [(from: ShadowPlannerState, to: ShadowPlannerState, at: Date)]

    init() {
        self.transitionHistory = []
    }

    /// 상태를 전이한다. 유효하지 않은 전이이면 `false`를 반환한다.
    @discardableResult
    mutating func transition(to next: ShadowPlannerState) -> Bool {
        guard state.canTransition(to: next) else {
            return false
        }
        let previous = state
        state = next
        transitionHistory.append((from: previous, to: next, at: Date()))
        return true
    }

    /// 상태 머신을 idle로 리셋한다.
    mutating func reset() {
        state = .idle
        transitionHistory.removeAll()
    }
}
