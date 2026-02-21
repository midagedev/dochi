import Foundation

/// K-6: Telegram proactive relay protocol.
/// Relays heartbeat alerts and proactive suggestions to Telegram DM.
@MainActor
protocol TelegramProactiveRelayProtocol: AnyObject {
    var isActive: Bool { get }

    func start()
    func stop()

    /// Send a heartbeat alert to Telegram.
    func sendHeartbeatAlert(
        calendar: String,
        kanban: String,
        reminder: String,
        memory: String?
    ) async

    /// Send a proactive suggestion to Telegram.
    func sendSuggestion(_ suggestion: ProactiveSuggestion) async

    /// Send a heartbeat change alert to Telegram.
    func sendHeartbeatChangeAlert(_ event: HeartbeatChangeEvent) async

    /// Number of Telegram notifications sent today.
    var todayTelegramNotificationCount: Int { get }
}
