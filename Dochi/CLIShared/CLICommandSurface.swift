import Foundation

enum CLIOutputMode: String, Equatable, Sendable {
    case text
    case json
}

enum CLIRuntimeMode: String, Equatable, Sendable {
    case auto
    case app
    case standalone
}

enum CLIContextTarget: String, Equatable, Sendable {
    case system
    case memory
}

enum CLIContextAction: Equatable, Sendable {
    case show(target: CLIContextTarget)
    case edit(target: CLIContextTarget)
}

enum CLIConversationAction: Equatable, Sendable {
    case list(limit: Int)
}

enum CLIConfigAction: Equatable, Sendable {
    case show
    case get(key: String)
    case set(key: String, value: String)
}

enum CLISessionAction: Equatable, Sendable {
    case list
}

enum CLIDevAction: Equatable, Sendable {
    case tool(name: String, argumentsJSON: String?)
    case logRecent(minutes: Int)
    case bridgeOpen(agent: String)
    case bridgeStatus(sessionId: String?)
    case bridgeSend(sessionId: String, command: String)
    case bridgeRead(sessionId: String, lines: Int)
}

enum CLICommand: Equatable, Sendable {
    case help
    case version
    case ask(query: String)
    case chat
    case context(CLIContextAction)
    case conversation(CLIConversationAction)
    case config(CLIConfigAction)
    case session(CLISessionAction)
    case dev(CLIDevAction)
    case doctor
}

struct CLIInvocation: Equatable, Sendable {
    let outputMode: CLIOutputMode
    let runtimeMode: CLIRuntimeMode
    let command: CLICommand
}

enum CLIParseError: LocalizedError {
    case invalidUsage(String)

    var errorDescription: String? {
        switch self {
        case .invalidUsage(let message):
            return message
        }
    }
}

enum CLICommandParser {
    static func parse(_ args: [String]) throws -> CLIInvocation {
        var outputMode: CLIOutputMode = .text
        var runtimeMode: CLIRuntimeMode = .auto

        var filtered: [String] = []
        var i = 0
        var helpRequested = false

        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--json":
                outputMode = .json
            case "--help", "-h":
                helpRequested = true
            case "--mode":
                let next = i + 1
                guard next < args.count else {
                    throw CLIParseError.invalidUsage("--mode 값이 필요합니다. (auto|app|standalone)")
                }
                guard let parsed = CLIRuntimeMode(rawValue: args[next].lowercased()) else {
                    throw CLIParseError.invalidUsage("지원하지 않는 모드입니다: \(args[next])")
                }
                runtimeMode = parsed
                i += 1
            default:
                if arg.hasPrefix("--mode=") {
                    let value = String(arg.dropFirst("--mode=".count))
                    guard let parsed = CLIRuntimeMode(rawValue: value.lowercased()) else {
                        throw CLIParseError.invalidUsage("지원하지 않는 모드입니다: \(value)")
                    }
                    runtimeMode = parsed
                } else {
                    filtered.append(arg)
                }
            }
            i += 1
        }

        if helpRequested {
            return CLIInvocation(outputMode: outputMode, runtimeMode: runtimeMode, command: .help)
        }

        guard let head = filtered.first else {
            return CLIInvocation(outputMode: outputMode, runtimeMode: runtimeMode, command: .help)
        }

        let tail = Array(filtered.dropFirst())
        let command: CLICommand

        switch head {
        case "version", "--version", "-v":
            command = .version

        case "ask":
            guard !tail.isEmpty else {
                throw CLIParseError.invalidUsage("ask 명령에는 질문 텍스트가 필요합니다.")
            }
            command = .ask(query: tail.joined(separator: " "))

        case "chat":
            command = .chat

        case "context":
            command = try parseContext(tail)

        case "conversation", "conversations":
            command = try parseConversation(tail)

        case "config":
            command = try parseConfig(tail)

        case "session":
            command = try parseSession(tail)

        case "dev":
            command = try parseDev(tail)

        case "doctor":
            command = .doctor

        default:
            // Backward compatible: treat free text as ask
            command = .ask(query: filtered.joined(separator: " "))
        }

        return CLIInvocation(outputMode: outputMode, runtimeMode: runtimeMode, command: command)
    }

    private static func parseContext(_ args: [String]) throws -> CLICommand {
        let sub = args.first ?? "show"
        let target = CLIContextTarget(rawValue: args.dropFirst().first ?? "system") ?? .system

        switch sub {
        case "show": return .context(.show(target: target))
        case "edit": return .context(.edit(target: target))
        default: throw CLIParseError.invalidUsage("context 하위 명령은 show/edit만 지원합니다.")
        }
    }

    private static func parseConversation(_ args: [String]) throws -> CLICommand {
        let sub = args.first ?? "list"
        guard sub == "list" else {
            throw CLIParseError.invalidUsage("conversation 하위 명령은 list만 지원합니다.")
        }

        var limit = 10
        if args.count >= 3, args[1] == "--limit", let parsed = Int(args[2]) {
            limit = max(1, parsed)
        }

        return .conversation(.list(limit: limit))
    }

    private static func parseConfig(_ args: [String]) throws -> CLICommand {
        let sub = args.first ?? "show"

        switch sub {
        case "show":
            return .config(.show)
        case "get":
            guard args.count >= 2 else {
                throw CLIParseError.invalidUsage("config get <key> 형식이 필요합니다.")
            }
            return .config(.get(key: args[1]))
        case "set":
            guard args.count >= 3 else {
                throw CLIParseError.invalidUsage("config set <key> <value> 형식이 필요합니다.")
            }
            return .config(.set(key: args[1], value: args.dropFirst(2).joined(separator: " ")))
        default:
            throw CLIParseError.invalidUsage("config 하위 명령은 show/get/set만 지원합니다.")
        }
    }

    private static func parseSession(_ args: [String]) throws -> CLICommand {
        let sub = args.first ?? "list"
        guard sub == "list" else {
            throw CLIParseError.invalidUsage("session 하위 명령은 list만 지원합니다.")
        }
        return .session(.list)
    }

    private static func parseDev(_ args: [String]) throws -> CLICommand {
        guard let domain = args.first else {
            throw CLIParseError.invalidUsage("dev 하위 명령이 필요합니다. (tool|log|bridge)")
        }

        switch domain {
        case "tool":
            guard args.count >= 2 else {
                throw CLIParseError.invalidUsage("dev tool <name> [arguments_json] 형식이 필요합니다.")
            }
            let name = args[1]
            let argumentsJSON = args.count > 2 ? args.dropFirst(2).joined(separator: " ") : nil
            return .dev(.tool(name: name, argumentsJSON: argumentsJSON))

        case "log":
            let sub = args.dropFirst().first ?? "recent"
            guard sub == "recent" else {
                throw CLIParseError.invalidUsage("dev log 하위 명령은 recent만 지원합니다.")
            }

            var minutes = 10
            let rest = Array(args.dropFirst(2))
            if rest.count >= 2, rest[0] == "--minutes", let parsed = Int(rest[1]) {
                minutes = max(1, parsed)
            }
            return .dev(.logRecent(minutes: minutes))

        case "bridge":
            let sub = args.dropFirst().first ?? "status"
            let rest = Array(args.dropFirst(2))
            switch sub {
            case "open":
                let agent = rest.first ?? "codex"
                return .dev(.bridgeOpen(agent: agent))
            case "status":
                let sessionId = rest.first
                return .dev(.bridgeStatus(sessionId: sessionId))
            case "send":
                guard rest.count >= 2 else {
                    throw CLIParseError.invalidUsage("dev bridge send <session_id> <command> 형식이 필요합니다.")
                }
                return .dev(.bridgeSend(sessionId: rest[0], command: rest.dropFirst().joined(separator: " ")))
            case "read":
                guard !rest.isEmpty else {
                    throw CLIParseError.invalidUsage("dev bridge read <session_id> [lines] 형식이 필요합니다.")
                }
                let lines = rest.count >= 2 ? (Int(rest[1]) ?? 80) : 80
                return .dev(.bridgeRead(sessionId: rest[0], lines: max(1, lines)))
            default:
                throw CLIParseError.invalidUsage("dev bridge 하위 명령은 open/status/send/read만 지원합니다.")
            }

        default:
            throw CLIParseError.invalidUsage("dev 하위 명령은 tool/log/bridge만 지원합니다.")
        }
    }
}
