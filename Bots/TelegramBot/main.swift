import Foundation

// Minimal Telegram Bot CLI scaffold for MVP
// - Reads TELEGRAM_BOT_TOKEN from env
// - Provides a --check command to validate config
// - Placeholder for long polling loop (to be implemented in subsequent PRs)

enum BotError: Error, CustomStringConvertible {
    case missingToken

    var description: String {
        switch self {
        case .missingToken:
            return "TELEGRAM_BOT_TOKEN is not set"
        }
    }
}

@main
struct TelegramBotMain {
    static func main() throws {
        let args = CommandLine.arguments.dropFirst()
        let env = ProcessInfo.processInfo.environment

        guard let token = env["TELEGRAM_BOT_TOKEN"], token.isEmpty == false else {
            throw BotError.missingToken
        }

        if args.contains("--check") {
            print("TelegramBot: configuration OK (token length = \(token.count))")
            return
        }

        // TODO: Implement long polling MVP
        // Plan:
        // 1) GET getMe to verify bot identity
        // 2) Simple getUpdates loop with offset tracking (in memory)
        // 3) Echo back received messages (DM) as MVP
        print("TelegramBot scaffold ready. Use --check to validate env.")
    }
}

