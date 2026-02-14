import Foundation

/// API key tier for cost/quality trade-off routing.
enum APIKeyTier: String, Codable, CaseIterable, Sendable {
    case premium   // 고성능 키 (높은 rate limit, 고급 모델 전용)
    case standard  // 기본 키
    case economy   // 경제적 키 (경량 모델 전용)

    var displayName: String {
        switch self {
        case .premium: "프리미엄"
        case .standard: "기본"
        case .economy: "경제"
        }
    }

    var description: String {
        switch self {
        case .premium: "고급 모델 전용, 높은 rate limit"
        case .standard: "기본 API 키"
        case .economy: "경량 모델 전용, 비용 절감"
        }
    }

    /// Keychain account suffix for this tier.
    var keychainSuffix: String {
        switch self {
        case .standard: "" // No suffix for backwards compatibility
        case .premium: "_premium"
        case .economy: "_economy"
        }
    }

    /// Map from TaskComplexity to preferred API key tier.
    static func preferredTier(for complexity: TaskComplexity) -> APIKeyTier {
        switch complexity {
        case .heavy: .premium
        case .standard: .standard
        case .light: .economy
        }
    }
}
