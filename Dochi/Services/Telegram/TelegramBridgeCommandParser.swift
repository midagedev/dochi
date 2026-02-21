import Foundation

enum TelegramBridgeCommand: Equatable {
    case bridgeOpen(
        agent: String,
        profileName: String?,
        workingDirectory: String?,
        forceWorkingDirectory: Bool
    )
    case bridgeStatus(sessionId: String?)
    case bridgeSend(sessionId: String, command: String)
    case bridgeRead(sessionId: String, lines: Int)
    case orchRequest(command: String, repositoryRoot: String?, ttlSeconds: Int?)
    case orchApprove(approvalId: String, challengeCode: String)
    case orchExecute(
        command: String,
        repositoryRoot: String?,
        confirmed: Bool,
        approvalId: String?
    )
    case orchStatus(repositoryRoot: String?, sessionId: String?, lines: Int)
}

enum TelegramBridgeCommandRoute: Equatable {
    case notCommand
    case command(TelegramBridgeCommand)
    case usageError(String)
}

enum TelegramBridgeCommandParser {
    static func route(_ text: String) -> TelegramBridgeCommandRoute {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return .notCommand
        }

        let tokens = tokenize(trimmed)
        guard let head = tokens.first else {
            return .notCommand
        }

        switch normalizeSlashCommand(head) {
        case "/bridge":
            return parseBridge(Array(tokens.dropFirst()))
        case "/orch":
            return parseOrch(Array(tokens.dropFirst()))
        default:
            return .notCommand
        }
    }

    private static func parseBridge(_ args: [String]) -> TelegramBridgeCommandRoute {
        guard let subcommand = args.first?.lowercased() else {
            return .usageError(bridgeUsage)
        }
        let rest = Array(args.dropFirst())

        switch subcommand {
        case "open":
            return parseBridgeOpen(rest)
        case "status":
            return parseBridgeStatus(rest)
        case "send":
            return parseBridgeSend(rest)
        case "read":
            return parseBridgeRead(rest)
        default:
            return .usageError(bridgeUsage)
        }
    }

    private static func parseBridgeOpen(_ args: [String]) -> TelegramBridgeCommandRoute {
        var agent: String?
        var profileName: String?
        var workingDirectory: String?
        var forceWorkingDirectory = false

        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--agent":
                guard index + 1 < args.count else {
                    return .usageError(bridgeUsage)
                }
                agent = args[index + 1].lowercased()
                index += 2
            case "--profile", "--profile-name":
                guard index + 1 < args.count else {
                    return .usageError(bridgeUsage)
                }
                profileName = args[index + 1]
                index += 2
            case "--cwd", "--working-directory":
                guard index + 1 < args.count else {
                    return .usageError(bridgeUsage)
                }
                workingDirectory = args[index + 1]
                index += 2
            case "--force-cwd", "--force-working-directory":
                forceWorkingDirectory = true
                index += 1
            default:
                if token.hasPrefix("--") {
                    return .usageError(bridgeUsage)
                }
                if agent == nil {
                    agent = token.lowercased()
                    index += 1
                } else {
                    return .usageError(bridgeUsage)
                }
            }
        }

        let resolvedAgent = agent ?? "codex"
        guard ["codex", "claude", "aider"].contains(resolvedAgent) else {
            return .usageError(bridgeUsage)
        }

        return .command(.bridgeOpen(
            agent: resolvedAgent,
            profileName: nonEmpty(profileName),
            workingDirectory: nonEmpty(workingDirectory),
            forceWorkingDirectory: forceWorkingDirectory
        ))
    }

    private static func parseBridgeStatus(_ args: [String]) -> TelegramBridgeCommandRoute {
        if args.isEmpty {
            return .command(.bridgeStatus(sessionId: nil))
        }
        if args.count == 1, !args[0].hasPrefix("--") {
            return .command(.bridgeStatus(sessionId: args[0]))
        }
        if args.count == 2, args[0] == "--session" {
            return .command(.bridgeStatus(sessionId: args[1]))
        }
        return .usageError(bridgeUsage)
    }

    private static func parseBridgeSend(_ args: [String]) -> TelegramBridgeCommandRoute {
        guard args.count >= 2 else {
            return .usageError(bridgeUsage)
        }
        let sessionId = args[0]
        let command = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return .usageError(bridgeUsage)
        }
        return .command(.bridgeSend(sessionId: sessionId, command: command))
    }

    private static func parseBridgeRead(_ args: [String]) -> TelegramBridgeCommandRoute {
        guard let sessionId = args.first else {
            return .usageError(bridgeUsage)
        }

        if args.count == 1 {
            return .command(.bridgeRead(sessionId: sessionId, lines: 80))
        }
        guard args.count == 2, let lines = Int(args[1]) else {
            return .usageError(bridgeUsage)
        }
        return .command(.bridgeRead(sessionId: sessionId, lines: max(1, min(500, lines))))
    }

    private static func parseOrch(_ args: [String]) -> TelegramBridgeCommandRoute {
        guard let subcommand = args.first?.lowercased() else {
            return .usageError(orchUsage)
        }
        let rest = Array(args.dropFirst())

        switch subcommand {
        case "request":
            return parseOrchRequest(rest)
        case "approve":
            return parseOrchApprove(rest)
        case "execute":
            return parseOrchExecute(rest)
        case "status":
            return parseOrchStatus(rest)
        default:
            return .usageError(orchUsage)
        }
    }

    private static func parseOrchRequest(_ args: [String]) -> TelegramBridgeCommandRoute {
        var repositoryRoot: String?
        var ttlSeconds: Int?
        var commandTokens: [String] = []

        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--repo", "--repository-root":
                guard index + 1 < args.count else {
                    return .usageError(orchUsage)
                }
                repositoryRoot = args[index + 1]
                index += 2
            case "--ttl", "--ttl-seconds":
                guard index + 1 < args.count, let parsed = Int(args[index + 1]) else {
                    return .usageError(orchUsage)
                }
                ttlSeconds = parsed
                index += 2
            default:
                commandTokens.append(token)
                index += 1
            }
        }

        let command = commandTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return .usageError(orchUsage)
        }

        return .command(.orchRequest(
            command: command,
            repositoryRoot: nonEmpty(repositoryRoot),
            ttlSeconds: ttlSeconds
        ))
    }

    private static func parseOrchApprove(_ args: [String]) -> TelegramBridgeCommandRoute {
        if args.count == 2, !args[0].hasPrefix("--"), !args[1].hasPrefix("--") {
            return .command(.orchApprove(approvalId: args[0], challengeCode: args[1]))
        }

        var approvalId: String?
        var challengeCode: String?
        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--id", "--approval-id":
                guard index + 1 < args.count else {
                    return .usageError(orchUsage)
                }
                approvalId = args[index + 1]
                index += 2
            case "--code", "--challenge-code":
                guard index + 1 < args.count else {
                    return .usageError(orchUsage)
                }
                challengeCode = args[index + 1]
                index += 2
            default:
                return .usageError(orchUsage)
            }
        }

        guard let approvalId = nonEmpty(approvalId), let challengeCode = nonEmpty(challengeCode) else {
            return .usageError(orchUsage)
        }

        return .command(.orchApprove(approvalId: approvalId, challengeCode: challengeCode))
    }

    private static func parseOrchExecute(_ args: [String]) -> TelegramBridgeCommandRoute {
        var repositoryRoot: String?
        var confirmed = false
        var approvalId: String?
        var commandTokens: [String] = []

        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--repo", "--repository-root":
                guard index + 1 < args.count else {
                    return .usageError(orchUsage)
                }
                repositoryRoot = args[index + 1]
                index += 2
            case "--confirmed":
                confirmed = true
                index += 1
            case "--approval-id":
                guard index + 1 < args.count else {
                    return .usageError(orchUsage)
                }
                approvalId = args[index + 1]
                index += 2
            default:
                commandTokens.append(token)
                index += 1
            }
        }

        let command = commandTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return .usageError(orchUsage)
        }

        return .command(.orchExecute(
            command: command,
            repositoryRoot: nonEmpty(repositoryRoot),
            confirmed: confirmed,
            approvalId: nonEmpty(approvalId)
        ))
    }

    private static func parseOrchStatus(_ args: [String]) -> TelegramBridgeCommandRoute {
        var repositoryRoot: String?
        var sessionId: String?
        var lines = 120

        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--repo", "--repository-root":
                guard index + 1 < args.count else {
                    return .usageError(orchUsage)
                }
                repositoryRoot = args[index + 1]
                index += 2
            case "--session":
                guard index + 1 < args.count else {
                    return .usageError(orchUsage)
                }
                sessionId = args[index + 1]
                index += 2
            case "--lines":
                guard index + 1 < args.count, let parsed = Int(args[index + 1]) else {
                    return .usageError(orchUsage)
                }
                lines = max(1, min(500, parsed))
                index += 2
            default:
                if token.hasPrefix("--") {
                    return .usageError(orchUsage)
                }
                if sessionId == nil {
                    sessionId = token
                    index += 1
                } else {
                    return .usageError(orchUsage)
                }
            }
        }

        return .command(.orchStatus(
            repositoryRoot: nonEmpty(repositoryRoot),
            sessionId: nonEmpty(sessionId),
            lines: lines
        ))
    }

    private static func normalizeSlashCommand(_ token: String) -> String {
        let lowercased = token.lowercased()
        if let atIndex = lowercased.firstIndex(of: "@") {
            return String(lowercased[..<atIndex])
        }
        return lowercased
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in text {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let bridgeUsage = """
    브리지 명령 사용법
    - /bridge open [codex|claude|aider] [--profile NAME] [--cwd PATH] [--force-cwd]
    - /bridge status [SESSION_ID]
    - /bridge send SESSION_ID COMMAND...
    - /bridge read SESSION_ID [LINES]
    """

    private static let orchUsage = """
    오케스트레이터 명령 사용법
    - /orch request COMMAND... [--repo PATH] [--ttl SECONDS]
    - /orch approve APPROVAL_ID CHALLENGE_CODE
    - /orch execute COMMAND... [--repo PATH] [--approval-id ID] [--confirmed]
    - /orch status [--repo PATH] [--session ID] [--lines N]
    """
}
