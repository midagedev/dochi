import Foundation

enum TTSProvider: String, Codable, CaseIterable, Sendable {
    case system
    case googleCloud

    var displayName: String {
        switch self {
        case .system: "시스템 TTS"
        case .googleCloud: "Google Cloud TTS"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .system: false
        case .googleCloud: true
        }
    }

    var keychainAccount: String {
        switch self {
        case .system: ""
        case .googleCloud: "google_cloud_tts_api_key"
        }
    }
}
