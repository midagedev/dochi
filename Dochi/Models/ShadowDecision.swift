import Foundation

// MARK: - Risk Level

/// Planner가 평가한 툴 선택의 위험 수준.
enum ShadowRiskLevel: String, Codable, Sendable, Comparable {
    case low
    case medium
    case high

    private var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: ShadowRiskLevel, rhs: ShadowRiskLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Tool Alternative

/// Planner가 제안하는 대안 툴.
struct ToolAlternative: Codable, Sendable, Equatable {
    /// 툴 이름
    let name: String
    /// 해당 대안에 대한 confidence (0.0~1.0)
    let confidence: Double
    /// 이 대안을 추천하는 이유 (간략)
    let reason: String

    init(name: String, confidence: Double, reason: String = "") {
        self.name = name
        self.confidence = max(0, min(1, confidence))
        self.reason = reason
    }
}

// MARK: - Reason Code

/// Planner의 의사결정 근거 코드.
enum ShadowReasonCode: String, Codable, Sendable {
    /// 사용자 의도와 가장 부합하는 도구
    case bestIntentMatch = "BEST_INTENT_MATCH"
    /// 이전 실패에 대한 대체 도구
    case failureRecovery = "FAILURE_RECOVERY"
    /// 그룹 선호 반영
    case groupPreference = "GROUP_PREFERENCE"
    /// 컨텍스트 기반 추론
    case contextInference = "CONTEXT_INFERENCE"
    /// 기본값 선택 (다른 근거 불충분)
    case defaultFallback = "DEFAULT_FALLBACK"
}

// MARK: - ShadowDecision

/// Shadow planner의 도구 선택 결정.
///
/// 부모 컨텍스트에 병합되는 데이터:
/// - 선택 툴 1개 (`primaryTool`)
/// - 차선책 최대 2개 (`alternatives`, 최대 2개로 제한)
/// - 근거 요약 최대 240 tokens (`reasonSummary`)
///
/// raw sub transcript는 메인 컨텍스트에 병합 금지.
struct ShadowDecision: Codable, Sendable, Equatable {
    /// Planner가 선택한 primary tool 이름
    let primaryTool: String
    /// 차선책 (최대 2개)
    let alternatives: [ToolAlternative]
    /// 의사결정 근거 코드 목록
    let reasonCodes: [ShadowReasonCode]
    /// 근거 요약 (240 tokens 이내)
    let reasonSummary: String
    /// Primary tool에 대한 confidence (0.0~1.0)
    let confidence: Double
    /// 위험 수준 평가
    let riskLevel: ShadowRiskLevel
    /// 중단 사유 (planner가 결정을 내리지 못한 경우)
    let abortReason: String?

    /// 최대 대안 수
    static let maxAlternatives = 2
    /// 근거 요약 최대 길이 (문자 수 기준, 토큰 근사)
    static let maxReasonSummaryLength = 960

    init(
        primaryTool: String,
        alternatives: [ToolAlternative] = [],
        reasonCodes: [ShadowReasonCode] = [],
        reasonSummary: String = "",
        confidence: Double = 0.0,
        riskLevel: ShadowRiskLevel = .low,
        abortReason: String? = nil
    ) {
        self.primaryTool = primaryTool
        // 대안 수 제한
        self.alternatives = Array(alternatives.prefix(Self.maxAlternatives))
        self.reasonCodes = reasonCodes
        // 근거 요약 길이 제한
        if reasonSummary.count > Self.maxReasonSummaryLength {
            self.reasonSummary = String(reasonSummary.prefix(Self.maxReasonSummaryLength))
        } else {
            self.reasonSummary = reasonSummary
        }
        self.confidence = max(0, min(1, confidence))
        self.riskLevel = riskLevel
        self.abortReason = abortReason
    }

    /// 유효한 결정인지 검사 (primaryTool이 비어있지 않고, abortReason이 없는 경우)
    var isValid: Bool {
        !primaryTool.isEmpty && abortReason == nil
    }

    /// JSON 직렬화 (DebugBundle 기록용).
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
