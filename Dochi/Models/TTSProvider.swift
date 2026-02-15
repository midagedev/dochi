import Foundation

enum TTSProvider: String, Codable, CaseIterable, Sendable {
    case system
    case googleCloud
    case onnxLocal

    var displayName: String {
        switch self {
        case .system: "시스템 TTS"
        case .googleCloud: "Google Cloud TTS"
        case .onnxLocal: "로컬 TTS (ONNX)"
        }
    }

    var shortDescription: String {
        switch self {
        case .system: "macOS 내장 음성 합성 — 추가 설정 불필요"
        case .googleCloud: "Google Cloud 고품질 음성 — API 키 필요"
        case .onnxLocal: "Piper ONNX 로컬 추론 — 오프라인 사용 가능"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .system: false
        case .googleCloud: true
        case .onnxLocal: false
        }
    }

    var keychainAccount: String {
        switch self {
        case .system: ""
        case .googleCloud: "google_cloud_tts_api_key"
        case .onnxLocal: ""
        }
    }

    /// Whether this provider runs locally without network
    var isLocal: Bool {
        switch self {
        case .system, .onnxLocal: true
        case .googleCloud: false
        }
    }
}
