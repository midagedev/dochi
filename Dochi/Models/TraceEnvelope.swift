import Foundation

// MARK: - Trigger Code

/// Shadow sub-agent spawn 트리거 코드.
enum ShadowTriggerCode: String, Codable, Sendable {
    /// 후보 툴 수 >= 3 이고 상위 후보 confidence gap < 0.15
    case ambiguousCandidates = "AMBIGUOUS_CANDIDATES"
    /// 동일 턴에서 제어 툴 재호출 감지
    case controlToolReuse = "CONTROL_TOOL_REUSE"
    /// 최근 3턴 내 tool failure ratio >= 0.34
    case highFailureRatio = "HIGH_FAILURE_RATIO"
}

// MARK: - Failure Classification

/// Shadow sub-agent 실패 분류 코드.
enum ShadowFailureCode: String, Codable, Sendable {
    /// 트리거 조건 오판 (불필요한 spawn)
    case triggerMisfire = "TRIGGER_MISFIRE"
    /// Planner 응답 시간 초과
    case plannerTimeout = "PLANNER_TIMEOUT"
    /// Planner 결과의 confidence가 낮음
    case plannerLowConfidence = "PLANNER_LOW_CONFIDENCE"
    /// 부모가 planner 결과를 override
    case parentOverride = "PARENT_OVERRIDE"
    /// Trace 데이터 불완전 (span 누락 등)
    case traceIncomplete = "TRACE_INCOMPLETE"
}

// MARK: - Guardrail Event

/// 가드레일 위반 이벤트.
struct GuardrailEvent: Codable, Sendable, Equatable {
    /// 위반된 가드레일 이름 (예: "maxDepth", "wallTime", "tokenBudget")
    let rule: String
    /// 실제 값
    let actualValue: String
    /// 허용 상한
    let limitValue: String
    /// 이벤트 발생 시간
    let timestamp: Date

    init(rule: String, actualValue: String, limitValue: String, timestamp: Date = Date()) {
        self.rule = rule
        self.actualValue = actualValue
        self.limitValue = limitValue
        self.timestamp = timestamp
    }
}

// MARK: - TraceEnvelope

/// Parent/Sub 공통 트레이스 봉투 (OpenTelemetry aligned).
///
/// 모든 shadow sub-agent 실행에 대해 하나의 `TraceEnvelope`이 생성되며,
/// parent run과 sub run의 상관관계를 추적한다.
///
/// Span names:
/// - `dochi.parent_run`
/// - `dochi.subagent.shadow_plan`
/// - `dochi.parent.tool_execute`
struct TraceEnvelope: Codable, Sendable, Identifiable, Equatable {
    /// 고유 식별자 (trace-level)
    let id: UUID
    /// Parent run 식별자
    let parentRunId: UUID
    /// Sub-agent run 식별자 (spawn 시 생성)
    let subRunId: UUID
    /// 대화 식별자
    let conversationId: String
    /// Spawn 트리거 코드
    let triggerCode: ShadowTriggerCode
    /// Planner가 선택한 primary tool
    var selectedTool: String?
    /// Parent가 planner 결과를 수락했는지 여부
    var acceptedByParent: Bool?
    /// 가드레일 위반 여부
    var guardrailHit: Bool
    /// 가드레일 위반 이벤트 목록
    var guardrailEvents: [GuardrailEvent]
    /// 실패 분류 코드 (실패 시에만 존재)
    var failureCode: ShadowFailureCode?
    /// 생성 시간
    let createdAt: Date
    /// 종료 시간
    var completedAt: Date?

    /// Envelope 소요 시간 (밀리초)
    var durationMs: Double? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(createdAt) * 1000.0
    }

    init(
        id: UUID = UUID(),
        parentRunId: UUID,
        subRunId: UUID = UUID(),
        conversationId: String,
        triggerCode: ShadowTriggerCode,
        selectedTool: String? = nil,
        acceptedByParent: Bool? = nil,
        guardrailHit: Bool = false,
        guardrailEvents: [GuardrailEvent] = [],
        failureCode: ShadowFailureCode? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.parentRunId = parentRunId
        self.subRunId = subRunId
        self.conversationId = conversationId
        self.triggerCode = triggerCode
        self.selectedTool = selectedTool
        self.acceptedByParent = acceptedByParent
        self.guardrailHit = guardrailHit
        self.guardrailEvents = guardrailEvents
        self.failureCode = failureCode
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    /// OpenTelemetry-aligned span attributes 딕셔너리 생성.
    var spanAttributes: [String: String] {
        var attrs: [String: String] = [
            "dochi.parent_run_id": parentRunId.uuidString,
            "dochi.sub_run_id": subRunId.uuidString,
            "gen_ai.system": "dochi",
            "dochi.trigger_code": triggerCode.rawValue,
            "dochi.guardrail_hit": String(guardrailHit)
        ]
        if let tool = selectedTool {
            attrs["dochi.primary_tool"] = tool
        }
        if let accepted = acceptedByParent {
            attrs["dochi.parent_accept"] = String(accepted)
        }
        if let failure = failureCode {
            attrs["dochi.failure_code"] = failure.rawValue
        }
        return attrs
    }
}
