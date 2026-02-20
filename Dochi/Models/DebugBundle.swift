import Foundation

// MARK: - Latency Breakdown

/// Sub-agent 실행의 지연 시간 분석.
struct ShadowLatencyBreakdown: Codable, Sendable, Equatable {
    /// 트리거 평가 소요 시간 (밀리초)
    let triggerEvaluationMs: Double
    /// Planner LLM 호출 소요 시간 (밀리초)
    let plannerCallMs: Double
    /// 결과 병합 소요 시간 (밀리초)
    let mergeDecisionMs: Double
    /// 전체 소요 시간 (밀리초)
    let totalMs: Double

    init(
        triggerEvaluationMs: Double = 0,
        plannerCallMs: Double = 0,
        mergeDecisionMs: Double = 0,
        totalMs: Double = 0
    ) {
        self.triggerEvaluationMs = triggerEvaluationMs
        self.plannerCallMs = plannerCallMs
        self.mergeDecisionMs = mergeDecisionMs
        self.totalMs = totalMs
    }
}

// MARK: - Token Breakdown

/// Sub-agent 실행의 토큰 사용량 분석.
struct ShadowTokenBreakdown: Codable, Sendable, Equatable {
    /// Planner 입력 토큰 수
    let inputTokens: Int
    /// Planner 출력 토큰 수
    let outputTokens: Int
    /// 합계
    var totalTokens: Int { inputTokens + outputTokens }

    init(inputTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

// MARK: - DebugBundle

/// Shadow sub-agent 디버그 번들.
///
/// 메인 컨텍스트에 병합되지 않는 상세 진단 정보를 담는다.
/// sanitized 형태로 저장하며, raw sub transcript는 포함하지 않는다.
struct DebugBundle: Codable, Sendable, Identifiable, Equatable {
    /// 고유 식별자
    let id: UUID
    /// 연결된 TraceEnvelope 식별자
    let traceEnvelopeId: UUID
    /// Sanitized 입력 요약 (원문 아닌 요약본)
    let inputSummary: String
    /// Planner 출력 JSON (ShadowDecision 직렬화)
    let plannerOutputJSON: String?
    /// Parent 최종 결정 (수락/거부/override)
    let parentFinalDecision: String
    /// 지연 시간 분석
    let latencyBreakdown: ShadowLatencyBreakdown
    /// 토큰 사용량 분석
    let tokenBreakdown: ShadowTokenBreakdown
    /// 가드레일 이벤트 목록
    let guardrailEvents: [GuardrailEvent]
    /// 생성 시간
    let createdAt: Date

    init(
        id: UUID = UUID(),
        traceEnvelopeId: UUID,
        inputSummary: String,
        plannerOutputJSON: String? = nil,
        parentFinalDecision: String,
        latencyBreakdown: ShadowLatencyBreakdown = ShadowLatencyBreakdown(),
        tokenBreakdown: ShadowTokenBreakdown = ShadowTokenBreakdown(),
        guardrailEvents: [GuardrailEvent] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.traceEnvelopeId = traceEnvelopeId
        self.inputSummary = inputSummary
        self.plannerOutputJSON = plannerOutputJSON
        self.parentFinalDecision = parentFinalDecision
        self.latencyBreakdown = latencyBreakdown
        self.tokenBreakdown = tokenBreakdown
        self.guardrailEvents = guardrailEvents
        self.createdAt = createdAt
    }
}
