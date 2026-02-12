import Foundation

enum LLMError: Error, LocalizedError, Sendable {
    case noAPIKey
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case modelNotFound(String)
    case timeout
    case networkError(String)
    case emptyResponse
    case invalidResponse(String)
    case cancelled
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "API 키가 설정되지 않았습니다."
        case .authenticationFailed: "API 키를 확인하세요."
        case .rateLimited: "요청 한도를 초과했습니다. 잠시 후 다시 시도하세요."
        case .modelNotFound(let model): "모델 '\(model)'을(를) 찾을 수 없습니다."
        case .timeout: "응답 시간이 초과되었습니다."
        case .networkError(let msg): "네트워크 오류: \(msg)"
        case .emptyResponse: "응답을 생성하지 못했습니다."
        case .invalidResponse(let msg): "잘못된 응답: \(msg)"
        case .cancelled: "요청이 취소되었습니다."
        case .serverError(let code, let msg): "서버 오류 (\(code)): \(msg)"
        }
    }
}
