import Foundation

// MARK: - Trigger Context

/// `shouldSpawn` 판단에 필요한 현재 턴의 컨텍스트 정보.
struct ShadowTriggerContext: Sendable {
    /// 현재 턴에서 사용 가능한 후보 tool 이름 목록
    let candidateTools: [String]
    /// 후보 tool별 confidence (LLM logprobs 기반 또는 휴리스틱)
    let candidateConfidences: [String: Double]
    /// 현재 턴에서 호출된 tool 이름 목록 (순서대로)
    let toolCallsThisTurn: [String]
    /// 최근 N턴의 tool 호출 결과 (이름, 성공 여부)
    let recentToolResults: [(name: String, success: Bool)]
    /// 현재 depth (재귀 방지)
    let currentDepth: Int
    /// 현재 턴에서 이미 실행된 sub-agent run 수
    let subRunsThisTurn: Int
    /// 대화 식별자
    let conversationId: String
    /// Parent run 식별자
    let parentRunId: UUID

    init(
        candidateTools: [String] = [],
        candidateConfidences: [String: Double] = [:],
        toolCallsThisTurn: [String] = [],
        recentToolResults: [(name: String, success: Bool)] = [],
        currentDepth: Int = 0,
        subRunsThisTurn: Int = 0,
        conversationId: String = "",
        parentRunId: UUID = UUID()
    ) {
        self.candidateTools = candidateTools
        self.candidateConfidences = candidateConfidences
        self.toolCallsThisTurn = toolCallsThisTurn
        self.recentToolResults = recentToolResults
        self.currentDepth = currentDepth
        self.subRunsThisTurn = subRunsThisTurn
        self.conversationId = conversationId
        self.parentRunId = parentRunId
    }
}

// MARK: - Planner Input

/// Shadow planner에 전달되는 입력.
struct ShadowPlannerInput: Sendable {
    /// 사용자 메시지 요약 (sanitized)
    let userMessageSummary: String
    /// 사용 가능한 도구 목록 (이름, 설명)
    let availableTools: [(name: String, description: String)]
    /// 최근 tool failure 히스토리
    let recentFailures: [(toolName: String, errorSummary: String)]
    /// 트리거 코드
    let triggerCode: ShadowTriggerCode

    init(
        userMessageSummary: String = "",
        availableTools: [(name: String, description: String)] = [],
        recentFailures: [(toolName: String, errorSummary: String)] = [],
        triggerCode: ShadowTriggerCode = .ambiguousCandidates
    ) {
        self.userMessageSummary = userMessageSummary
        self.availableTools = availableTools
        self.recentFailures = recentFailures
        self.triggerCode = triggerCode
    }
}

// MARK: - Planner Result

/// Shadow planner 실행 결과.
enum ShadowPlannerResult: Sendable {
    /// 성공적으로 결정을 생성함
    case success(ShadowDecision)
    /// 타임아웃으로 실패
    case timeout
    /// 에러로 실패
    case error(String)
}

// MARK: - Merge Result

/// Parent에 병합될 최종 결과.
struct ShadowMergeResult: Sendable, Equatable {
    /// 선택된 primary tool
    let selectedTool: String
    /// 차선책 (최대 2개)
    let alternatives: [ToolAlternative]
    /// 근거 요약
    let reasonSummary: String
    /// Parent가 planner 결과를 수락했는지 여부
    let accepted: Bool
    /// 관련 trace envelope ID
    let traceEnvelopeId: UUID

    init(
        selectedTool: String,
        alternatives: [ToolAlternative] = [],
        reasonSummary: String = "",
        accepted: Bool = true,
        traceEnvelopeId: UUID = UUID()
    ) {
        self.selectedTool = selectedTool
        self.alternatives = alternatives
        self.reasonSummary = reasonSummary
        self.accepted = accepted
        self.traceEnvelopeId = traceEnvelopeId
    }
}

// MARK: - Protocol

/// Shadow sub-agent orchestrator 프로토콜.
///
/// `@MainActor` 근거: 상태 머신과 trace 데이터가 UI (세션 탐색기, 디버그 패널)에서
/// 관찰되며, 단일 스레드에서 일관성을 유지해야 한다.
///
/// 설계 원칙:
/// 1. Single-agent first: 기본 실행 권한은 항상 부모 런에 둔다.
/// 2. Planner-only first: 서브는 계획 생성만 수행, 실제 툴 호출은 부모가 수행.
/// 3. Deterministic routing: 서브 런 생성 조건은 코드 규칙 기반.
/// 4. Bounded complexity: depth/time/token/call 수를 하드리밋으로 제한.
/// 5. Trace-first: parent/sub 공통 trace 스키마 기반.
@MainActor
protocol ShadowSubAgentOrchestratorProtocol {
    /// 현재 설정.
    var config: ShadowSubAgentConfig { get }

    /// 현재 상태.
    var currentState: ShadowPlannerState { get }

    /// 최근 trace envelope 목록 (디버깅/관측용).
    var recentTraceEnvelopes: [TraceEnvelope] { get }

    /// 최근 debug bundle 목록 (디버깅용).
    var recentDebugBundles: [DebugBundle] { get }

    /// 트리거 조건을 평가하여 shadow planner를 spawn해야 하는지 결정한다.
    ///
    /// Deterministic routing: LLM 임의 판단 없이 코드 규칙으로만 판단한다.
    /// 트리거 조건 중 하나라도 충족되고, 가드레일 (depth, turn limit, kill switch,
    /// sampling gate)을 통과하면 `true`를 반환한다.
    ///
    /// - Parameter context: 현재 턴의 컨텍스트 정보
    /// - Returns: spawn 여부와 트리거 코드 (spawn하지 않을 경우 nil)
    func shouldSpawn(context: ShadowTriggerContext) -> (spawn: Bool, triggerCode: ShadowTriggerCode?)

    /// Shadow planner를 실행하여 tool 선택 계획을 생성한다.
    ///
    /// wall time과 token budget 가드레일을 적용한다.
    /// 실제 tool 호출은 수행하지 않으며 계획만 생성한다.
    ///
    /// - Parameter input: planner 입력
    /// - Returns: planner 결과
    func runPlanner(input: ShadowPlannerInput) async -> ShadowPlannerResult

    /// Planner 결과를 부모 컨텍스트에 병합 가능한 형태로 변환한다.
    ///
    /// 병합 제약:
    /// - 선택 툴 1개
    /// - 차선책 최대 2개
    /// - 근거 요약 최대 240 tokens
    /// - raw sub transcript 병합 금지
    ///
    /// - Parameters:
    ///   - decision: planner의 결정
    ///   - traceEnvelopeId: 연결된 trace envelope ID
    /// - Returns: 병합 결과
    func mergeDecision(decision: ShadowDecision, traceEnvelopeId: UUID) -> ShadowMergeResult

    /// 설정을 업데이트한다.
    func updateConfig(_ config: ShadowSubAgentConfig)

    /// 상태 머신을 리셋한다.
    func resetState()
}
