import AppKit
import Foundation
import os

/// K-6: Relays heartbeat alerts and proactive suggestions to Telegram DM.
@MainActor
@Observable
final class TelegramProactiveRelay: TelegramProactiveRelayProtocol {
    // MARK: - Dependencies

    private let settings: AppSettings
    private let telegramService: TelegramServiceProtocol
    private let keychainService: KeychainServiceProtocol

    // MARK: - State

    private(set) var isActive: Bool = false
    private(set) var todayTelegramNotificationCount: Int = 0
    private var todayDateString: String = ""

    /// Last sent suggestion (for response context).
    private(set) var lastSentSuggestion: ProactiveSuggestion?

    // MARK: - Init

    init(
        settings: AppSettings,
        telegramService: TelegramServiceProtocol,
        keychainService: KeychainServiceProtocol
    ) {
        self.settings = settings
        self.telegramService = telegramService
        self.keychainService = keychainService
        self.todayDateString = Self.dateString(from: Date())
        Log.telegram.info("TelegramProactiveRelay initialized")
    }

    // MARK: - Lifecycle

    func start() {
        isActive = true
        Log.telegram.info("TelegramProactiveRelay started")
    }

    func stop() {
        isActive = false
        Log.telegram.info("TelegramProactiveRelay stopped")
    }

    // MARK: - Heartbeat Alert

    func sendHeartbeatAlert(
        calendar: String,
        kanban: String,
        reminder: String,
        memory: String?
    ) async {
        let channel = NotificationChannel(rawValue: settings.heartbeatNotificationChannel) ?? .appOnly
        guard shouldSendToTelegram(channel: channel) else { return }
        guard let chatId = resolveChatId() else {
            Log.telegram.debug("하트비트 텔레그램 전송 건너뜀: chatId 미매핑")
            return
        }
        guard hasTelegramToken() else {
            Log.telegram.debug("하트비트 텔레그램 전송 건너뜀: 토큰 미설정")
            return
        }

        var parts: [String] = []

        if !calendar.isEmpty {
            parts.append("\u{1F4C5} *일정 알림*\n\(escapeMarkdown(calendar))")
        }
        if !kanban.isEmpty {
            parts.append("\u{1F4CB} *칸반 진행 상황*\n\(escapeMarkdown(kanban))")
        }
        if !reminder.isEmpty {
            parts.append("\u{23F0} *마감 임박 미리알림*\n\(escapeMarkdown(reminder))")
        }
        if let memory, !memory.isEmpty {
            parts.append("\u{1F4BE} *메모리 정리 필요*\n\(escapeMarkdown(memory))\n\n_\"메모리 정리해줘\"라고 답장하면 자동 정리합니다_")
        }

        guard !parts.isEmpty else { return }

        let message = parts.joined(separator: "\n\n")
        await send(chatId: chatId, text: message)
    }

    // MARK: - Suggestion

    func sendSuggestion(_ suggestion: ProactiveSuggestion) async {
        let channel = NotificationChannel(rawValue: settings.suggestionNotificationChannel) ?? .appOnly
        guard shouldSendToTelegram(channel: channel) else { return }
        guard let chatId = resolveChatId() else {
            Log.telegram.debug("제안 텔레그램 전송 건너뜀: chatId 미매핑")
            return
        }
        guard hasTelegramToken() else {
            Log.telegram.debug("제안 텔레그램 전송 건너뜀: 토큰 미설정")
            return
        }

        let message = formatSuggestion(suggestion)
        lastSentSuggestion = suggestion
        await send(chatId: chatId, text: message)
    }

    // MARK: - Channel Logic

    func shouldSendToTelegram(channel: NotificationChannel) -> Bool {
        guard channel.deliversToTelegram else { return false }

        if settings.telegramSkipWhenAppActive && NSApp.isActive {
            Log.telegram.debug("앱이 활성 상태이므로 텔레그램 전송 생략")
            return false
        }

        return true
    }

    // MARK: - Message Formatting

    private func formatSuggestion(_ suggestion: ProactiveSuggestion) -> String {
        let emoji: String
        let replyHint: String

        switch suggestion.type {
        case .newsTrend:
            emoji = "\u{1F310}"
            replyHint = "\"알아봐줘\"라고 답장하세요"
        case .deepDive:
            emoji = "\u{1F4D6}"
            replyHint = "\"설명해줘\"라고 답장하세요"
        case .relatedResearch:
            emoji = "\u{1F50D}"
            replyHint = "\"조사해줘\"라고 답장하세요"
        case .kanbanCheck:
            emoji = "\u{2705}"
            replyHint = "\"확인해줘\"라고 답장하세요"
        case .memoryRemind:
            emoji = "\u{1F9E0}"
            replyHint = "\"리마인드해줘\"라고 답장하세요"
        case .costReport:
            emoji = "\u{1F4CA}"
            replyHint = "\"요약 보여줘\"라고 답장하세요"
        }

        return "\(emoji) *\(escapeMarkdown(suggestion.title))*\n\(escapeMarkdown(suggestion.body))\n\n\u{1F4A1} \(replyHint)"
    }

    /// Escape Telegram Markdown special characters in user data.
    func escapeMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "[", with: "\\[")
    }

    // MARK: - Helpers

    private func resolveChatId() -> Int64? {
        let mappings = TelegramChatMappingStore.loadMappings(from: settings)
        let workspaceId = UUID(uuidString: settings.currentWorkspaceId) ?? UUID()
        return mappings.first(where: { $0.workspaceId == workspaceId && $0.enabled })?.chatId
    }

    private func hasTelegramToken() -> Bool {
        guard let token = keychainService.load(account: "telegram_bot_token"), !token.isEmpty else {
            return false
        }
        return true
    }

    private func send(chatId: Int64, text: String) async {
        resetDailyCountIfNeeded()

        do {
            _ = try await telegramService.sendMessage(chatId: chatId, text: text)
            todayTelegramNotificationCount += 1
            Log.telegram.info("프로액티브 텔레그램 메시지 전송 완료 (오늘 \(self.todayTelegramNotificationCount)건)")
        } catch {
            Log.telegram.warning("프로액티브 텔레그램 메시지 전송 실패: \(error.localizedDescription)")
        }
    }

    private func resetDailyCountIfNeeded() {
        let today = Self.dateString(from: Date())
        if today != todayDateString {
            todayDateString = today
            todayTelegramNotificationCount = 0
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dateString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
