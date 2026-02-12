import Foundation
import os

// MARK: - telegram.enable

@MainActor
final class TelegramEnableTool: BuiltInToolProtocol {
    let name = "telegram.enable"
    let category: ToolCategory = .sensitive
    let description = "텔레그램 봇 연동을 활성화하거나 비활성화합니다."
    let isBaseline = false

    private let keychainService: KeychainServiceProtocol
    private let telegramService: TelegramServiceProtocol
    private let settings: AppSettings

    init(keychainService: KeychainServiceProtocol, telegramService: TelegramServiceProtocol, settings: AppSettings) {
        self.keychainService = keychainService
        self.telegramService = telegramService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "enabled": ["type": "boolean", "description": "활성화 여부"],
                "token": ["type": "string", "description": "봇 토큰 (선택, 활성화 시 함께 설정)"]
            ],
            "required": ["enabled"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let enabled = arguments["enabled"] as? Bool else {
            return ToolResult(toolCallId: "", content: "오류: enabled는 필수입니다. (true/false)", isError: true)
        }

        // Save token if provided
        if let token = arguments["token"] as? String, !token.isEmpty {
            do {
                try keychainService.save(account: "telegram_bot_token", value: token)
                Log.tool.info("Saved Telegram bot token")
            } catch {
                Log.tool.error("Failed to save Telegram bot token: \(error.localizedDescription)")
                return ToolResult(toolCallId: "", content: "오류: 봇 토큰 저장 실패 — \(error.localizedDescription)", isError: true)
            }
        }

        settings.telegramEnabled = enabled

        if !enabled {
            telegramService.stopPolling()
            Log.tool.info("Telegram disabled, polling stopped")
            return ToolResult(toolCallId: "", content: "텔레그램 연동을 비활성화했습니다.")
        }

        // When enabling, try to start polling if token exists
        if let token = keychainService.load(account: "telegram_bot_token") {
            telegramService.startPolling(token: token)
            Log.tool.info("Telegram enabled, polling started")
            return ToolResult(toolCallId: "", content: "텔레그램 연동을 활성화하고 폴링을 시작했습니다.")
        }

        Log.tool.info("Telegram enabled but no token set")
        return ToolResult(toolCallId: "", content: "텔레그램 연동을 활성화했습니다. 봇 토큰이 설정되지 않아 폴링은 시작되지 않았습니다. telegram.set_token으로 토큰을 설정해주세요.")
    }
}

// MARK: - telegram.set_token

@MainActor
final class TelegramSetTokenTool: BuiltInToolProtocol {
    let name = "telegram.set_token"
    let category: ToolCategory = .sensitive
    let description = "텔레그램 봇 토큰을 저장합니다."
    let isBaseline = false

    private let keychainService: KeychainServiceProtocol
    private let telegramService: TelegramServiceProtocol
    private let settings: AppSettings

    init(keychainService: KeychainServiceProtocol, telegramService: TelegramServiceProtocol, settings: AppSettings) {
        self.keychainService = keychainService
        self.telegramService = telegramService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "token": ["type": "string", "description": "텔레그램 봇 토큰"]
            ],
            "required": ["token"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let token = arguments["token"] as? String, !token.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: token은 필수입니다.", isError: true)
        }

        do {
            try keychainService.save(account: "telegram_bot_token", value: token)
            Log.tool.info("Saved Telegram bot token")
            return ToolResult(toolCallId: "", content: "텔레그램 봇 토큰을 저장했습니다.")
        } catch {
            Log.tool.error("Failed to save Telegram bot token: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 봇 토큰 저장 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - telegram.get_me

@MainActor
final class TelegramGetMeTool: BuiltInToolProtocol {
    let name = "telegram.get_me"
    let category: ToolCategory = .sensitive
    let description = "텔레그램 봇 정보를 조회합니다."
    let isBaseline = false

    private let keychainService: KeychainServiceProtocol
    private let telegramService: TelegramServiceProtocol
    private let settings: AppSettings

    init(keychainService: KeychainServiceProtocol, telegramService: TelegramServiceProtocol, settings: AppSettings) {
        self.keychainService = keychainService
        self.telegramService = telegramService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [String: Any]()
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let token = keychainService.load(account: "telegram_bot_token") else {
            return ToolResult(toolCallId: "", content: "오류: 봇 토큰이 설정되지 않았습니다. telegram.set_token으로 먼저 설정해주세요.", isError: true)
        }

        do {
            let user = try await telegramService.getMe(token: token)
            var result = "봇 정보:\n"
            result += "- ID: \(user.id)\n"
            result += "- 이름: \(user.firstName)\n"
            if let username = user.username {
                result += "- 사용자명: @\(username)\n"
            }
            result += "- 봇 여부: \(user.isBot ? "예" : "아니오")"
            Log.tool.info("Retrieved Telegram bot info: \(user.firstName)")
            return ToolResult(toolCallId: "", content: result)
        } catch {
            Log.tool.error("Failed to get Telegram bot info: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 봇 정보 조회 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - telegram.send_message

@MainActor
final class TelegramSendMessageTool: BuiltInToolProtocol {
    let name = "telegram.send_message"
    let category: ToolCategory = .sensitive
    let description = "텔레그램 채팅에 메시지를 전송합니다."
    let isBaseline = false

    private let keychainService: KeychainServiceProtocol
    private let telegramService: TelegramServiceProtocol
    private let settings: AppSettings

    init(keychainService: KeychainServiceProtocol, telegramService: TelegramServiceProtocol, settings: AppSettings) {
        self.keychainService = keychainService
        self.telegramService = telegramService
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "chat_id": ["type": "integer", "description": "텔레그램 채팅 ID"],
                "text": ["type": "string", "description": "전송할 메시지 내용"]
            ],
            "required": ["chat_id", "text"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let chatId = arguments["chat_id"] as? Int64 ?? (arguments["chat_id"] as? Int).map({ Int64($0) }) else {
            return ToolResult(toolCallId: "", content: "오류: chat_id는 필수입니다.", isError: true)
        }

        guard let text = arguments["text"] as? String, !text.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: text는 필수입니다.", isError: true)
        }

        do {
            let messageId = try await telegramService.sendMessage(chatId: chatId, text: text)
            Log.tool.info("Sent Telegram message to chat \(chatId), messageId: \(messageId)")
            return ToolResult(toolCallId: "", content: "메시지를 전송했습니다. (message_id: \(messageId))")
        } catch {
            Log.tool.error("Failed to send Telegram message: \(error.localizedDescription)")
            return ToolResult(toolCallId: "", content: "오류: 메시지 전송 실패 — \(error.localizedDescription)", isError: true)
        }
    }
}
