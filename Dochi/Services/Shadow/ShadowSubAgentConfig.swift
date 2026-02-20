import Foundation

// MARK: - Shadow Sub-Agent Configuration

/// Shadow sub-agent 시스템의 모든 설정 파라미터.
///
/// 설계 원칙:
/// - Deterministic routing: 트리거 조건은 코드 규칙 기반 (LLM 임의 판단 금지)
/// - Bounded complexity: depth/time/token/call 수를 하드리밋으로 제한
/// - Global kill switch 및 sampling gate 제공
struct ShadowSubAgentConfig: Codable, Sendable, Equatable {

    // MARK: - Kill Switch & Sampling

    /// Global kill switch — false이면 shadow sub-agent 완전 비활성화
    var shadowSubAgentEnabled: Bool

    /// Sampling gate — 트리거 조건 충족 시 실제 spawn 확률 (0.0~1.0)
    /// 기본 0.1 (10%)로 시작하여 효과 검증 후 단계적 확대
    var shadowSubAgentSampleRate: Double

    // MARK: - Hard Guardrails

    /// 재귀 금지: 최대 depth (서브가 서브를 호출하지 않음)
    var maxDepth: Int

    /// 턴당 서브 런 최대 횟수
    var maxSubRunsPerTurn: Int

    /// 서브 런 wall time 상한 (밀리초)
    var wallTimeMs: Int

    /// 서브 런 token budget 상한
    var tokenBudget: Int

    // MARK: - Trigger Thresholds

    /// 후보 툴 수 최소값 (ambiguousCandidates 트리거)
    var minCandidateCount: Int

    /// 상위 후보 confidence gap 임계값 (미만이면 트리거)
    var confidenceGapThreshold: Double

    /// 제어 툴 재호출 감지 대상 도구명
    var controlToolNames: Set<String>

    /// 최근 N턴 내 failure ratio 검사 범위
    var failureWindowTurns: Int

    /// Failure ratio 임계값 (이상이면 트리거)
    var failureRatioThreshold: Double

    // MARK: - Merge Constraints

    /// 병합 시 최대 대안 수
    var maxMergeAlternatives: Int

    /// 병합 시 근거 요약 최대 토큰 수
    var maxReasonTokens: Int

    // MARK: - Defaults

    /// 기본 설정값.
    static let `default` = ShadowSubAgentConfig(
        shadowSubAgentEnabled: false,
        shadowSubAgentSampleRate: 0.1,
        maxDepth: 1,
        maxSubRunsPerTurn: 1,
        wallTimeMs: 2000,
        tokenBudget: 600,
        minCandidateCount: 3,
        confidenceGapThreshold: 0.15,
        controlToolNames: ["tools.enable", "tools.enable_ttl", "tools.reset"],
        failureWindowTurns: 3,
        failureRatioThreshold: 0.34,
        maxMergeAlternatives: 2,
        maxReasonTokens: 240
    )

    /// 테스트용 설정 — 모든 가드레일을 넉넉하게, sampling rate 100%.
    static let forTesting = ShadowSubAgentConfig(
        shadowSubAgentEnabled: true,
        shadowSubAgentSampleRate: 1.0,
        maxDepth: 1,
        maxSubRunsPerTurn: 1,
        wallTimeMs: 5000,
        tokenBudget: 1000,
        minCandidateCount: 3,
        confidenceGapThreshold: 0.15,
        controlToolNames: ["tools.enable", "tools.enable_ttl", "tools.reset"],
        failureWindowTurns: 3,
        failureRatioThreshold: 0.34,
        maxMergeAlternatives: 2,
        maxReasonTokens: 240
    )
}
