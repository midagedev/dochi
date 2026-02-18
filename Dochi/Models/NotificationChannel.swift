import Foundation

/// Notification delivery channel for proactive alerts (K-6).
enum NotificationChannel: String, Codable, Sendable, CaseIterable {
    case appOnly        // macOS notification + in-app UI only
    case telegramOnly   // Telegram DM only
    case both           // Both channels
    case off            // Disabled

    var displayName: String {
        switch self {
        case .appOnly: return "앱만"
        case .telegramOnly: return "텔레그램만"
        case .both: return "둘 다"
        case .off: return "끄기"
        }
    }

    var deliversToApp: Bool {
        self == .appOnly || self == .both
    }

    var deliversToTelegram: Bool {
        self == .telegramOnly || self == .both
    }
}
