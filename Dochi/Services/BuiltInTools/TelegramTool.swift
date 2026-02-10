import Foundation
import os

/// 텔레그램 설정/동작 도구
@MainActor
final class TelegramTool: BuiltInTool {
    weak var settings: AppSettings?
    var telegram: TelegramService?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:telegram.enable",
                name: "telegram.enable",
                description: "Enable or disable Telegram integration. Optionally set token.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "enabled": ["type": "boolean"],
                        "token": ["type": "string"]
                    ],
                    "required": ["enabled"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:telegram.set_token",
                name: "telegram.set_token",
                description: "Set Telegram bot token (stored securely).",
                inputSchema: [
                    "type": "object",
                    "properties": ["token": ["type": "string"]],
                    "required": ["token"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:telegram.get_me",
                name: "telegram.get_me",
                description: "Fetch bot username for the configured token.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:telegram.send_message",
                name: "telegram.send_message",
                description: "Send a test message to a chat id (DM chat id).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "chat_id": ["type": "integer"],
                        "text": ["type": "string"]
                    ],
                    "required": ["chat_id", "text"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String : Any]) async throws -> MCPToolResult {
        guard let settings, let telegram else {
            return MCPToolResult(content: "Telegram settings/service unavailable", isError: true)
        }
        switch name {
        case "telegram.enable":
            guard let enabled = arguments["enabled"] as? Bool else {
                return MCPToolResult(content: "enabled is required (boolean)", isError: true)
            }
            if let token = arguments["token"] as? String, !token.isEmpty {
                settings.telegramBotToken = token
            }
            settings.telegramEnabled = enabled
            if enabled {
                telegram.start(token: settings.telegramBotToken)
            } else {
                telegram.stop()
            }
            return MCPToolResult(content: enabled ? "Telegram enabled" : "Telegram disabled", isError: false)

        case "telegram.set_token":
            guard let token = arguments["token"] as? String, !token.isEmpty else {
                return MCPToolResult(content: "token is required", isError: true)
            }
            settings.telegramBotToken = token
            if settings.telegramEnabled { telegram.start(token: token) }
            return MCPToolResult(content: "Token updated", isError: false)

        case "telegram.get_me":
            let token = settings.telegramBotToken
            guard !token.isEmpty else { return MCPToolResult(content: "Token is not set", isError: true) }
            do {
                let name = try await telegram.getMe(token: token)
                return MCPToolResult(content: name, isError: false)
            } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "telegram.send_message":
            guard let chatIdVal = arguments["chat_id"], let text = arguments["text"] as? String, !text.isEmpty else {
                return MCPToolResult(content: "chat_id and text are required", isError: true)
            }
            let chatId: Int64
            if let n = chatIdVal as? Int64 { chatId = n }
            else if let i = chatIdVal as? Int { chatId = Int64(i) }
            else if let s = chatIdVal as? String, let i = Int64(s) { chatId = i }
            else { return MCPToolResult(content: "chat_id must be integer", isError: true) }
            let _ = await telegram.sendMessage(chatId: chatId, text: text)
            return MCPToolResult(content: "Sent", isError: false)

        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }
}

