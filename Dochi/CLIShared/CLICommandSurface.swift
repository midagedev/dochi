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
    case show(id: String, limit: Int)
    case tail(limit: Int)
}

enum CLIConfigAction: Equatable, Sendable {
    case show
    case get(key: String)
    case set(key: String, value: String)
}

enum CLISessionAction: Equatable, Sendable {
    case list
}

enum CLILogAction: Equatable, Sendable {
    case recent(minutes: Int, limit: Int, category: String?, level: String?, contains: String?)
}

enum CLIDevAction: Equatable, Sendable {
    case tool(name: String, argumentsJSON: String?)
    case logRecent(minutes: Int)
    case logTail(seconds: Int, category: String?, level: String?, contains: String?)
    case chatStream(prompt: String, secretMode: Bool, secretAllowedTools: [String])
    case bridgeOpen(agent: String, profileName: String?, workingDirectory: String?, forceWorkingDirectory: Bool)
    case bridgeRoots(limit: Int, searchPaths: [String])
    case bridgeStatus(sessionId: String?)
    case bridgeSend(sessionId: String, command: String)
    case bridgeRead(sessionId: String, lines: Int)
    case bridgeOrchestratorSelect(repositoryRoot: String?)
    case bridgeOrchestratorExecute(command: String, repositoryRoot: String?, confirmed: Bool)
    case bridgeOrchestratorStatus(repositoryRoot: String?, sessionId: String?, lines: Int)
    case bridgeOrchestratorInterrupt(repositoryRoot: String?, sessionId: String?)
    case bridgeOrchestratorSummarize(repositoryRoot: String?, sessionId: String?, lines: Int)
    case bridgeRepoList
    case bridgeRepoInit(path: String, defaultBranch: String, createReadme: Bool, createGitignore: Bool)
    case bridgeRepoClone(remoteURL: String, destinationPath: String, branch: String?)
    case bridgeRepoAttach(path: String)
    case bridgeRepoRemove(repositoryId: String, deleteDirectory: Bool)
}

enum CLICommand: Equatable, Sendable {
    case help
    case version
    case ask(query: String)
    case chat
    case context(CLIContextAction)
    case conversation(CLIConversationAction)
    case log(CLILogAction)
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
    static func parse(
        _ args: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CLIInvocation {
        var outputMode: CLIOutputMode = .text
        var runtimeMode: CLIRuntimeMode = .auto
        var allowStandalone = false
        if let flag = environment["DOCHI_CLI_ALLOW_STANDALONE"]?.lowercased() {
            allowStandalone = flag == "1" || flag == "true" || flag == "yes"
        }

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
            case "--allow-standalone":
                allowStandalone = true
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

        if runtimeMode == .standalone && !allowStandalone {
            throw CLIParseError.invalidUsage("standalone 모드는 디버그 전용입니다. `--allow-standalone`을 함께 지정하세요.")
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

        case "log":
            command = try parseLog(tail)

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
        let sub: String
        let rest: [String]
        if let first = args.first, !first.hasPrefix("--") {
            sub = first
            rest = Array(args.dropFirst())
        } else {
            sub = "list"
            rest = args
        }

        switch sub {
        case "list":
            let limit = try parseSingleIntOption(rest, option: "--limit", defaultValue: 10, usage: "conversation list --limit <N>")
            return .conversation(.list(limit: limit))

        case "show":
            guard let id = rest.first, !id.hasPrefix("--") else {
                throw CLIParseError.invalidUsage("conversation show <conversation_id> [--limit N] 형식이 필요합니다.")
            }
            let optionArgs = Array(rest.dropFirst())
            let limit = try parseSingleIntOption(optionArgs, option: "--limit", defaultValue: 20, usage: "conversation show <conversation_id> [--limit N]")
            return .conversation(.show(id: id, limit: limit))

        case "tail", "latest":
            let limit = try parseSingleIntOption(rest, option: "--limit", defaultValue: 20, usage: "conversation tail [--limit N]")
            return .conversation(.tail(limit: limit))

        default:
            throw CLIParseError.invalidUsage("conversation 하위 명령은 list/show/tail만 지원합니다.")
        }
    }

    private static func parseLog(_ args: [String]) throws -> CLICommand {
        let sub: String
        let rest: [String]
        if let first = args.first, !first.hasPrefix("--") {
            sub = first
            rest = Array(args.dropFirst())
        } else {
            sub = "recent"
            rest = args
        }
        guard sub == "recent" else {
            throw CLIParseError.invalidUsage("log 하위 명령은 recent만 지원합니다.")
        }

        var minutes = 15
        var limit = 200
        var category: String?
        var level: String?
        var contains: String?

        var index = 0
        while index < rest.count {
            switch rest[index] {
            case "--minutes":
                guard index + 1 < rest.count, let parsed = Int(rest[index + 1]) else {
                    throw CLIParseError.invalidUsage("log recent --minutes <N> 형식이 필요합니다.")
                }
                minutes = max(1, parsed)
                index += 2
            case "--limit":
                guard index + 1 < rest.count, let parsed = Int(rest[index + 1]) else {
                    throw CLIParseError.invalidUsage("log recent --limit <N> 형식이 필요합니다.")
                }
                limit = max(1, parsed)
                index += 2
            case "--category":
                guard index + 1 < rest.count else {
                    throw CLIParseError.invalidUsage("log recent --category <name> 형식이 필요합니다.")
                }
                category = rest[index + 1]
                index += 2
            case "--level":
                guard index + 1 < rest.count else {
                    throw CLIParseError.invalidUsage("log recent --level <name> 형식이 필요합니다.")
                }
                level = rest[index + 1]
                index += 2
            case "--contains":
                guard index + 1 < rest.count else {
                    throw CLIParseError.invalidUsage("log recent --contains <keyword> 형식이 필요합니다.")
                }
                contains = rest[index + 1]
                index += 2
            default:
                throw CLIParseError.invalidUsage("알 수 없는 옵션입니다: \(rest[index])")
            }
        }

        return .log(.recent(
            minutes: minutes,
            limit: limit,
            category: category,
            level: level,
            contains: contains
        ))
    }

    private static func parseSingleIntOption(
        _ args: [String],
        option: String,
        defaultValue: Int,
        usage: String
    ) throws -> Int {
        guard !args.isEmpty else { return defaultValue }
        guard args.count == 2, args[0] == option, let parsed = Int(args[1]) else {
            throw CLIParseError.invalidUsage("\(usage) 형식이 필요합니다.")
        }
        return max(1, parsed)
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
            let rest = Array(args.dropFirst(2))

            switch sub {
            case "recent":
                var minutes = 10
                if rest.count >= 2, rest[0] == "--minutes", let parsed = Int(rest[1]) {
                    minutes = max(1, parsed)
                }
                return .dev(.logRecent(minutes: minutes))

            case "tail":
                var seconds = 10
                var category: String?
                var level: String?
                var contains: String?

                var index = 0
                while index < rest.count {
                    switch rest[index] {
                    case "--seconds":
                        guard index + 1 < rest.count, let parsed = Int(rest[index + 1]) else {
                            throw CLIParseError.invalidUsage("dev log tail --seconds <N> 형식이 필요합니다.")
                        }
                        seconds = max(1, parsed)
                        index += 2
                    case "--category":
                        guard index + 1 < rest.count else {
                            throw CLIParseError.invalidUsage("dev log tail --category <name> 형식이 필요합니다.")
                        }
                        category = rest[index + 1]
                        index += 2
                    case "--level":
                        guard index + 1 < rest.count else {
                            throw CLIParseError.invalidUsage("dev log tail --level <name> 형식이 필요합니다.")
                        }
                        level = rest[index + 1]
                        index += 2
                    case "--contains":
                        guard index + 1 < rest.count else {
                            throw CLIParseError.invalidUsage("dev log tail --contains <keyword> 형식이 필요합니다.")
                        }
                        contains = rest[index + 1]
                        index += 2
                    default:
                        throw CLIParseError.invalidUsage("알 수 없는 옵션입니다: \(rest[index])")
                    }
                }
                return .dev(.logTail(seconds: seconds, category: category, level: level, contains: contains))

            default:
                throw CLIParseError.invalidUsage("dev log 하위 명령은 recent/tail만 지원합니다.")
            }

        case "chat":
            let sub = args.dropFirst().first ?? "stream"
            guard sub == "stream" else {
                throw CLIParseError.invalidUsage("dev chat 하위 명령은 stream만 지원합니다.")
            }

            let streamArgs = Array(args.dropFirst(2))
            var secretMode = false
            var secretAllowedTools: [String] = []
            var promptParts: [String] = []
            var index = 0

            while index < streamArgs.count {
                let token = streamArgs[index]
                if promptParts.isEmpty {
                    switch token {
                    case "--secret":
                        secretMode = true
                        index += 1
                        continue
                    case "--secret-allow-tool", "--allow-tool":
                        guard index + 1 < streamArgs.count else {
                            throw CLIParseError.invalidUsage("dev chat stream --secret-allow-tool <tool_name> 형식이 필요합니다.")
                        }
                        secretAllowedTools.append(streamArgs[index + 1])
                        index += 2
                        continue
                    case "--":
                        promptParts.append(contentsOf: streamArgs.dropFirst(index + 1))
                        index = streamArgs.count
                        continue
                    default:
                        if token.hasPrefix("--") {
                            throw CLIParseError.invalidUsage("dev chat stream의 알 수 없는 옵션입니다: \(token)")
                        }
                    }
                }

                promptParts.append(contentsOf: streamArgs.dropFirst(index))
                break
            }

            let prompt = promptParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                throw CLIParseError.invalidUsage("dev chat stream <prompt> 형식이 필요합니다.")
            }

            let normalizedAllowedTools = secretAllowedTools
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { result, value in
                    if !result.contains(value) {
                        result.append(value)
                    }
                }

            return .dev(.chatStream(
                prompt: prompt,
                secretMode: secretMode,
                secretAllowedTools: normalizedAllowedTools
            ))

        case "bridge":
            let sub = args.dropFirst().first ?? "status"
            let rest = Array(args.dropFirst(2))
            switch sub {
            case "open":
                var agent = "codex"
                var profileName: String?
                var workingDirectory: String?
                var forceWorkingDirectory = false
                var index = 0

                if index < rest.count, !rest[index].hasPrefix("--") {
                    agent = rest[index]
                    index += 1
                }

                while index < rest.count {
                    switch rest[index] {
                    case "--profile":
                        guard index + 1 < rest.count else {
                            throw CLIParseError.invalidUsage("dev bridge open --profile <name> 형식이 필요합니다.")
                        }
                        profileName = rest[index + 1]
                        index += 2
                    case "--working-directory", "--cwd":
                        guard index + 1 < rest.count else {
                            throw CLIParseError.invalidUsage("dev bridge open --working-directory <DIR> 형식이 필요합니다.")
                        }
                        workingDirectory = rest[index + 1]
                        index += 2
                    case "--force-working-directory":
                        forceWorkingDirectory = true
                        index += 1
                    default:
                        throw CLIParseError.invalidUsage("dev bridge open의 알 수 없는 옵션입니다: \(rest[index])")
                    }
                }

                return .dev(.bridgeOpen(
                    agent: agent,
                    profileName: profileName,
                    workingDirectory: workingDirectory,
                    forceWorkingDirectory: forceWorkingDirectory
                ))
            case "roots":
                var limit = 20
                var searchPaths: [String] = []
                var index = 0
                while index < rest.count {
                    switch rest[index] {
                    case "--limit":
                        guard index + 1 < rest.count, let parsed = Int(rest[index + 1]) else {
                            throw CLIParseError.invalidUsage("dev bridge roots --limit <N> 형식이 필요합니다.")
                        }
                        limit = max(1, parsed)
                        index += 2
                    case "--path":
                        guard index + 1 < rest.count else {
                            throw CLIParseError.invalidUsage("dev bridge roots --path <DIR> 형식이 필요합니다.")
                        }
                        searchPaths.append(rest[index + 1])
                        index += 2
                    default:
                        throw CLIParseError.invalidUsage("dev bridge roots의 알 수 없는 옵션입니다: \(rest[index])")
                    }
                }
                return .dev(.bridgeRoots(limit: limit, searchPaths: searchPaths))
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
            case "orchestrator":
                let orchestratorSub = rest.first ?? "status"
                let orchestratorArgs = Array(rest.dropFirst())
                switch orchestratorSub {
                case "select":
                    var repositoryRoot: String?
                    var index = 0
                    while index < orchestratorArgs.count {
                        switch orchestratorArgs[index] {
                        case "--repo", "--repository-root":
                            guard index + 1 < orchestratorArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator select --repo <path> 형식이 필요합니다.")
                            }
                            repositoryRoot = orchestratorArgs[index + 1]
                            index += 2
                        default:
                            throw CLIParseError.invalidUsage("dev bridge orchestrator select의 알 수 없는 옵션입니다: \(orchestratorArgs[index])")
                        }
                    }
                    return .dev(.bridgeOrchestratorSelect(repositoryRoot: repositoryRoot))
                case "execute":
                    var commandParts: [String] = []
                    var index = 0
                    var repositoryRoot: String?
                    var confirmed = false
                    while index < orchestratorArgs.count {
                        let token = orchestratorArgs[index]
                        switch token {
                        case "--repo", "--repository-root":
                            guard index + 1 < orchestratorArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator execute --repo <path> 형식이 필요합니다.")
                            }
                            repositoryRoot = orchestratorArgs[index + 1]
                            index += 2
                        case "--confirmed":
                            confirmed = true
                            index += 1
                        default:
                            commandParts.append(token)
                            index += 1
                        }
                    }
                    let command = commandParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !command.isEmpty else {
                        throw CLIParseError.invalidUsage("dev bridge orchestrator execute <command> [--repo <path>] [--confirmed] 형식이 필요합니다.")
                    }
                    return .dev(.bridgeOrchestratorExecute(
                        command: command,
                        repositoryRoot: repositoryRoot,
                        confirmed: confirmed
                    ))
                case "status":
                    var repositoryRoot: String?
                    var sessionId: String?
                    var lines = 120
                    var index = 0
                    while index < orchestratorArgs.count {
                        switch orchestratorArgs[index] {
                        case "--repo", "--repository-root":
                            guard index + 1 < orchestratorArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator status --repo <path> 형식이 필요합니다.")
                            }
                            repositoryRoot = orchestratorArgs[index + 1]
                            index += 2
                        case "--session":
                            guard index + 1 < orchestratorArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator status --session <id> 형식이 필요합니다.")
                            }
                            sessionId = orchestratorArgs[index + 1]
                            index += 2
                        case "--lines":
                            guard index + 1 < orchestratorArgs.count, let parsed = Int(orchestratorArgs[index + 1]) else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator status --lines <N> 형식이 필요합니다.")
                            }
                            lines = max(1, parsed)
                            index += 2
                        default:
                            throw CLIParseError.invalidUsage("dev bridge orchestrator status의 알 수 없는 옵션입니다: \(orchestratorArgs[index])")
                        }
                    }
                    return .dev(.bridgeOrchestratorStatus(
                        repositoryRoot: repositoryRoot,
                        sessionId: sessionId,
                        lines: lines
                    ))
                case "interrupt":
                    var repositoryRoot: String?
                    var sessionId: String?
                    var index = 0
                    while index < orchestratorArgs.count {
                        switch orchestratorArgs[index] {
                        case "--repo", "--repository-root":
                            guard index + 1 < orchestratorArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator interrupt --repo <path> 형식이 필요합니다.")
                            }
                            repositoryRoot = orchestratorArgs[index + 1]
                            index += 2
                        case "--session":
                            guard index + 1 < orchestratorArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator interrupt --session <id> 형식이 필요합니다.")
                            }
                            sessionId = orchestratorArgs[index + 1]
                            index += 2
                        default:
                            throw CLIParseError.invalidUsage("dev bridge orchestrator interrupt의 알 수 없는 옵션입니다: \(orchestratorArgs[index])")
                        }
                    }
                    return .dev(.bridgeOrchestratorInterrupt(
                        repositoryRoot: repositoryRoot,
                        sessionId: sessionId
                    ))
                case "summarize":
                    var repositoryRoot: String?
                    var sessionId: String?
                    var lines = 160
                    var index = 0
                    while index < orchestratorArgs.count {
                        switch orchestratorArgs[index] {
                        case "--repo", "--repository-root":
                            guard index + 1 < orchestratorArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator summarize --repo <path> 형식이 필요합니다.")
                            }
                            repositoryRoot = orchestratorArgs[index + 1]
                            index += 2
                        case "--session":
                            guard index + 1 < orchestratorArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator summarize --session <id> 형식이 필요합니다.")
                            }
                            sessionId = orchestratorArgs[index + 1]
                            index += 2
                        case "--lines":
                            guard index + 1 < orchestratorArgs.count, let parsed = Int(orchestratorArgs[index + 1]) else {
                                throw CLIParseError.invalidUsage("dev bridge orchestrator summarize --lines <N> 형식이 필요합니다.")
                            }
                            lines = max(1, parsed)
                            index += 2
                        default:
                            throw CLIParseError.invalidUsage("dev bridge orchestrator summarize의 알 수 없는 옵션입니다: \(orchestratorArgs[index])")
                        }
                    }
                    return .dev(.bridgeOrchestratorSummarize(
                        repositoryRoot: repositoryRoot,
                        sessionId: sessionId,
                        lines: lines
                    ))
                default:
                    throw CLIParseError.invalidUsage("dev bridge orchestrator 하위 명령은 select/execute/status/interrupt/summarize만 지원합니다.")
                }
            case "repo":
                let repoSub = rest.first ?? "list"
                let repoArgs = Array(rest.dropFirst())
                switch repoSub {
                case "list":
                    return .dev(.bridgeRepoList)
                case "init":
                    guard let path = repoArgs.first, !path.hasPrefix("--") else {
                        throw CLIParseError.invalidUsage("dev bridge repo init <path> [--branch B] [--readme] [--gitignore] 형식이 필요합니다.")
                    }
                    var defaultBranch = "main"
                    var createReadme = false
                    var createGitignore = false
                    var index = 1
                    while index < repoArgs.count {
                        switch repoArgs[index] {
                        case "--branch":
                            guard index + 1 < repoArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge repo init --branch <name> 형식이 필요합니다.")
                            }
                            defaultBranch = repoArgs[index + 1]
                            index += 2
                        case "--readme":
                            createReadme = true
                            index += 1
                        case "--gitignore":
                            createGitignore = true
                            index += 1
                        default:
                            throw CLIParseError.invalidUsage("dev bridge repo init의 알 수 없는 옵션입니다: \(repoArgs[index])")
                        }
                    }
                    return .dev(.bridgeRepoInit(
                        path: path,
                        defaultBranch: defaultBranch,
                        createReadme: createReadme,
                        createGitignore: createGitignore
                    ))
                case "clone":
                    guard repoArgs.count >= 2 else {
                        throw CLIParseError.invalidUsage("dev bridge repo clone <remote_url> <destination_path> [--branch B] 형식이 필요합니다.")
                    }
                    let remoteURL = repoArgs[0]
                    let destinationPath = repoArgs[1]
                    var branch: String?
                    var index = 2
                    while index < repoArgs.count {
                        switch repoArgs[index] {
                        case "--branch":
                            guard index + 1 < repoArgs.count else {
                                throw CLIParseError.invalidUsage("dev bridge repo clone --branch <name> 형식이 필요합니다.")
                            }
                            branch = repoArgs[index + 1]
                            index += 2
                        default:
                            throw CLIParseError.invalidUsage("dev bridge repo clone의 알 수 없는 옵션입니다: \(repoArgs[index])")
                        }
                    }
                    return .dev(.bridgeRepoClone(
                        remoteURL: remoteURL,
                        destinationPath: destinationPath,
                        branch: branch
                    ))
                case "attach":
                    guard let path = repoArgs.first else {
                        throw CLIParseError.invalidUsage("dev bridge repo attach <path> 형식이 필요합니다.")
                    }
                    return .dev(.bridgeRepoAttach(path: path))
                case "remove":
                    guard let repositoryId = repoArgs.first else {
                        throw CLIParseError.invalidUsage("dev bridge repo remove <repository_id> [--delete-directory] 형식이 필요합니다.")
                    }
                    var deleteDirectory = false
                    var index = 1
                    while index < repoArgs.count {
                        switch repoArgs[index] {
                        case "--delete-directory":
                            deleteDirectory = true
                            index += 1
                        default:
                            throw CLIParseError.invalidUsage("dev bridge repo remove의 알 수 없는 옵션입니다: \(repoArgs[index])")
                        }
                    }
                    return .dev(.bridgeRepoRemove(repositoryId: repositoryId, deleteDirectory: deleteDirectory))
                default:
                    throw CLIParseError.invalidUsage("dev bridge repo 하위 명령은 list/init/clone/attach/remove만 지원합니다.")
                }
            default:
                throw CLIParseError.invalidUsage("dev bridge 하위 명령은 open/roots/status/send/read/orchestrator/repo만 지원합니다.")
            }

        default:
            throw CLIParseError.invalidUsage("dev 하위 명령은 tool/log/chat/bridge만 지원합니다.")
        }
    }
}
