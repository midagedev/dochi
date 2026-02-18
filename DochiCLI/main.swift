import AppKit
import Foundation

// MARK: - Exit Codes

enum CLIExitCode: Int32 {
    case success = 0
    case runtimeError = 1
    case invalidUsage = 2
    case configError = 3
    case connectionError = 4
    case authError = 5
}

// MARK: - Runtime Result

struct CLIResult {
    let exitCode: CLIExitCode
    let command: String
    let message: String
    let data: [String: Any]

    init(
        exitCode: CLIExitCode,
        command: String,
        message: String,
        data: [String: Any] = [:]
    ) {
        self.exitCode = exitCode
        self.command = command
        self.message = message
        self.data = data
    }
}

// MARK: - Output

struct CLIPrinter {
    let outputMode: CLIOutputMode

    func emit(_ result: CLIResult) {
        switch outputMode {
        case .text:
            print(result.message)
            if !result.data.isEmpty {
                for key in result.data.keys.sorted() {
                    print("- \(key): \(result.data[key] ?? "")")
                }
            }

        case .json:
            var payload: [String: Any] = [
                "status": result.exitCode == .success ? "ok" : "error",
                "exit_code": result.exitCode.rawValue,
                "command": result.command,
                "message": result.message,
            ]
            if !result.data.isEmpty {
                payload["data"] = result.data
            }
            if let json = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: json, encoding: .utf8) {
                print(text)
            } else {
                print("{\"status\":\"error\",\"message\":\"failed to encode json\"}")
            }
        }
    }
}

// MARK: - App Connection

enum AppConnectionProbe {
    static func isDochiAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.hckim.dochi").isEmpty
    }
}

// MARK: - Dochi CLI

enum DochiCLI {
    static func run(arguments: [String] = Array(CommandLine.arguments.dropFirst())) async -> CLIExitCode {
        let parseOutputMode: CLIOutputMode = arguments.contains("--json") ? .json : .text
        let invocation: CLIInvocation

        do {
            invocation = try CLICommandParser.parse(arguments)
        } catch {
            let printer = CLIPrinter(outputMode: parseOutputMode)
            let message = "명령 파싱 오류: \(error.localizedDescription)\n\n\(usageText())"
            printer.emit(CLIResult(exitCode: .invalidUsage, command: "help", message: message))
            return .invalidUsage
        }

        let printer = CLIPrinter(outputMode: invocation.outputMode)
        let result = await execute(invocation)
        printer.emit(result)
        return result.exitCode
    }

    private static func execute(_ invocation: CLIInvocation) async -> CLIResult {
        switch invocation.command {
        case .help:
            return CLIResult(exitCode: .success, command: "help", message: usageText())

        case .version:
            return CLIResult(exitCode: .success, command: "version", message: "dochi-cli v1.1.0")

        case .ask(let query):
            return await handleAsk(query)

        case .chat:
            return await handleChat(outputMode: invocation.outputMode)

        case .context(let action):
            return handleContext(action)

        case .conversation(let action):
            return handleConversation(action)

        case .config(let action):
            return handleConfig(action)

        case .session(let action):
            return handleRequiresAppConnection(
                command: sessionCommandName(action),
                runtimeMode: invocation.runtimeMode,
                hint: "session 명령은 #228 Control Plane 구현 이후 활성화됩니다."
            )

        case .dev(let action):
            return handleDev(action, runtimeMode: invocation.runtimeMode)

        case .doctor:
            return handleDoctor(runtimeMode: invocation.runtimeMode)
        }
    }

    // MARK: - Ask / Chat

    private static func handleAsk(_ query: String) async -> CLIResult {
        let config = CLIConfig.load()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return CLIResult(
                exitCode: .authError,
                command: "ask",
                message: "API 키가 설정되지 않았습니다. dochi config set api_key <KEY>를 실행하세요."
            )
        }

        let client = DochiCLIClient(config: config)
        do {
            let response = try await client.query(query)
            return CLIResult(exitCode: .success, command: "ask", message: response)
        } catch {
            return CLIResult(exitCode: .runtimeError, command: "ask", message: "질의 실패: \(error.localizedDescription)")
        }
    }

    private static func handleChat(outputMode: CLIOutputMode) async -> CLIResult {
        if outputMode == .json {
            return CLIResult(exitCode: .invalidUsage, command: "chat", message: "chat 대화 모드는 --json 출력과 함께 사용할 수 없습니다.")
        }

        let config = CLIConfig.load()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return CLIResult(
                exitCode: .authError,
                command: "chat",
                message: "API 키가 설정되지 않았습니다. dochi config set api_key <KEY>를 실행하세요."
            )
        }

        print("도치 대화 모드 시작 (/quit 종료, /clear 기록 초기화)")
        let client = DochiCLIClient(config: config)

        while true {
            print("\n> ", terminator: "")
            fflush(stdout)

            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
                continue
            }

            if input == "/quit" || input == "/exit" {
                break
            }
            if input == "/clear" {
                client.clearHistory()
                print("대화 기록을 초기화했습니다.")
                continue
            }

            do {
                let response = try await client.chat(input)
                print("\n\(response)")
            } catch {
                print("\n오류: \(error.localizedDescription)")
            }
        }

        return CLIResult(exitCode: .success, command: "chat", message: "대화 모드를 종료했습니다.")
    }

    // MARK: - Context

    private static func handleContext(_ action: CLIContextAction) -> CLIResult {
        let contextDir = CLIConfig.contextDirectory
        let filename: String

        switch action {
        case .show(let target), .edit(let target):
            filename = target == .memory ? "memory.md" : "system_prompt.md"
        }

        let filePath = contextDir.appendingPathComponent(filename)

        switch action {
        case .show:
            if let content = try? String(contentsOf: filePath, encoding: .utf8) {
                return CLIResult(exitCode: .success, command: "context.show", message: content)
            }
            return CLIResult(exitCode: .configError, command: "context.show", message: "파일이 없습니다: \(filePath.path)")

        case .edit:
            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "nano"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [editor, filePath.path]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return CLIResult(exitCode: .success, command: "context.edit", message: "편집 완료: \(filePath.path)")
                }
                return CLIResult(exitCode: .runtimeError, command: "context.edit", message: "편집기 종료 코드: \(process.terminationStatus)")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "context.edit", message: "편집기 실행 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Conversation

    private static func handleConversation(_ action: CLIConversationAction) -> CLIResult {
        switch action {
        case .list(let limit):
            let convDir = CLIConfig.contextDirectory.appendingPathComponent("conversations")
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: convDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else {
                return CLIResult(exitCode: .success, command: "conversation.list", message: "대화가 없습니다.")
            }

            let jsonFiles = files.filter { $0.pathExtension == "json" }
                .sorted {
                    let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return d1 > d2
                }

            guard !jsonFiles.isEmpty else {
                return CLIResult(exitCode: .success, command: "conversation.list", message: "대화가 없습니다.")
            }

            var lines: [String] = ["최근 대화 (최대 \(limit)개)"]
            for (index, file) in jsonFiles.prefix(limit).enumerated() {
                lines.append("\(index + 1). \(file.deletingPathExtension().lastPathComponent)")
            }

            return CLIResult(
                exitCode: .success,
                command: "conversation.list",
                message: lines.joined(separator: "\n"),
                data: ["count": jsonFiles.count]
            )
        }
    }

    // MARK: - Config

    private static func handleConfig(_ action: CLIConfigAction) -> CLIResult {
        var config = CLIConfig.load()

        switch action {
        case .show:
            let masked = maskAPIKey(config.apiKey)
            let baseURL = config.baseURL ?? "(default)"
            let message = """
                provider: \(config.provider)
                model: \(config.model)
                api_key: \(masked)
                base_url: \(baseURL)
                """
            return CLIResult(exitCode: .success, command: "config.show", message: message)

        case .get(let key):
            guard let value = configValue(config, key: key) else {
                return CLIResult(exitCode: .invalidUsage, command: "config.get", message: "지원하지 않는 키입니다: \(key)")
            }
            return CLIResult(exitCode: .success, command: "config.get", message: "\(key)=\(value)")

        case .set(let key, let value):
            do {
                try setConfigValue(&config, key: key, value: value)
                try config.save()
                return CLIResult(exitCode: .success, command: "config.set", message: "설정 저장 완료: \(key)")
            } catch {
                return CLIResult(exitCode: .configError, command: "config.set", message: "설정 저장 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Dev / Session (App connection required)

    private static func handleDev(_ action: CLIDevAction, runtimeMode: CLIRuntimeMode) -> CLIResult {
        switch action {
        case .logRecent(let minutes):
            return handleRequiresAppConnection(
                command: "dev.log.recent",
                runtimeMode: runtimeMode,
                hint: "dev log recent (minutes=\(minutes))는 #228 이후 활성화됩니다."
            )

        case .tool(let name, let argumentsJSON):
            let argsHint = argumentsJSON ?? "{}"
            return handleRequiresAppConnection(
                command: "dev.tool",
                runtimeMode: runtimeMode,
                hint: "dev tool \(name) \(argsHint)는 #228 이후 활성화됩니다."
            )

        case .bridgeOpen(let agent):
            return handleRequiresAppConnection(
                command: "dev.bridge.open",
                runtimeMode: runtimeMode,
                hint: "dev bridge open \(agent)는 #228 이후 활성화됩니다."
            )

        case .bridgeStatus(let sessionId):
            return handleRequiresAppConnection(
                command: "dev.bridge.status",
                runtimeMode: runtimeMode,
                hint: "dev bridge status \(sessionId ?? "")는 #228 이후 활성화됩니다."
            )

        case .bridgeSend(let sessionId, let command):
            return handleRequiresAppConnection(
                command: "dev.bridge.send",
                runtimeMode: runtimeMode,
                hint: "dev bridge send \(sessionId) \(command) 는 #228 이후 활성화됩니다."
            )

        case .bridgeRead(let sessionId, let lines):
            return handleRequiresAppConnection(
                command: "dev.bridge.read",
                runtimeMode: runtimeMode,
                hint: "dev bridge read \(sessionId) \(lines)는 #228 이후 활성화됩니다."
            )
        }
    }

    private static func handleRequiresAppConnection(
        command: String,
        runtimeMode: CLIRuntimeMode,
        hint: String
    ) -> CLIResult {
        let appRunning = AppConnectionProbe.isDochiAppRunning()

        if runtimeMode == .standalone {
            return CLIResult(
                exitCode: .connectionError,
                command: command,
                message: "이 명령은 standalone 모드에서 지원하지 않습니다. --mode app 또는 auto를 사용하세요."
            )
        }

        if !appRunning {
            return CLIResult(
                exitCode: .connectionError,
                command: command,
                message: "Dochi 앱이 실행 중이 아닙니다. 앱을 실행한 뒤 다시 시도하세요."
            )
        }

        return CLIResult(exitCode: .connectionError, command: command, message: hint)
    }

    // MARK: - Doctor

    private static func handleDoctor(runtimeMode: CLIRuntimeMode) -> CLIResult {
        let contextDir = CLIConfig.contextDirectory
        let configFile = CLIConfig.configFile
        let config = CLIConfig.load()
        let appRunning = AppConnectionProbe.isDochiAppRunning()

        let checks: [(name: String, ok: Bool, detail: String)] = [
            ("context_dir", FileManager.default.fileExists(atPath: contextDir.path), contextDir.path),
            ("config_file", FileManager.default.fileExists(atPath: configFile.path), configFile.path),
            ("api_key", (config.apiKey?.isEmpty == false), "api_key configured"),
            ("app_running", appRunning, "bundle: com.hckim.dochi"),
            ("mode", true, runtimeMode.rawValue),
        ]

        let okCount = checks.filter { $0.ok }.count
        let status = okCount == checks.count ? "정상" : "확인 필요"

        var lines = ["doctor 결과: \(status) (\(okCount)/\(checks.count))"]
        for check in checks {
            lines.append("- \(check.ok ? "OK" : "FAIL") \(check.name): \(check.detail)")
        }

        return CLIResult(
            exitCode: okCount == checks.count ? .success : .connectionError,
            command: "doctor",
            message: lines.joined(separator: "\n")
        )
    }

    // MARK: - Helpers

    private static func configValue(_ config: CLIConfig, key: String) -> String? {
        switch key {
        case "api_key": return maskAPIKey(config.apiKey)
        case "model": return config.model
        case "provider": return config.provider
        case "base_url": return config.baseURL ?? ""
        default: return nil
        }
    }

    private static func setConfigValue(_ config: inout CLIConfig, key: String, value: String) throws {
        switch key {
        case "api_key":
            config.apiKey = value
        case "model":
            config.model = value
        case "provider":
            config.provider = value
        case "base_url":
            config.baseURL = value.isEmpty ? nil : value
        default:
            throw CLIParseError.invalidUsage("지원하지 않는 설정 키입니다: \(key)")
        }
    }

    private static func maskAPIKey(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "(empty)" }
        if key.count <= 8 { return "******" }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)****\(suffix)"
    }

    private static func sessionCommandName(_ action: CLISessionAction) -> String {
        switch action {
        case .list: return "session.list"
        }
    }

    static func usageText() -> String {
        """
        Dochi CLI v1.1.0

        사용자 명령:
          dochi ask <질문> [--json]
          dochi chat
          dochi conversation list [--limit N]
          dochi context show [system|memory]
          dochi context edit [system|memory]
          dochi config show
          dochi config get <key>
          dochi config set <key> <value>

        운영/개발 명령:
          dochi session list
          dochi dev tool <name> [arguments_json]
          dochi dev log recent [--minutes N]
          dochi dev bridge open [agent]
          dochi dev bridge status [session_id]
          dochi dev bridge send <session_id> <command>
          dochi dev bridge read <session_id> [lines]
          dochi doctor

        전역 옵션:
          --mode <auto|app|standalone>
          --json
          --help
          --version
        """
    }
}

// MARK: - CLI Config

struct CLIConfig: Codable {
    var apiKey: String?
    var model: String
    var provider: String
    var baseURL: String?

    init(apiKey: String? = nil, model: String = "claude-sonnet-4-5-20250929", provider: String = "anthropic", baseURL: String? = nil) {
        self.apiKey = apiKey
        self.model = model
        self.provider = provider
        self.baseURL = baseURL
    }

    static var contextDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
    }

    static var configFile: URL {
        contextDirectory.appendingPathComponent("cli_config.json")
    }

    static func load() -> CLIConfig {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(CLIConfig.self, from: data) else {
            return CLIConfig()
        }
        return config
    }

    func save() throws {
        let dir = Self.contextDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.configFile)
    }
}

// MARK: - CLI Client

final class DochiCLIClient {
    private let config: CLIConfig
    private var history: [[String: String]] = []

    init(config: CLIConfig) {
        self.config = config
    }

    func query(_ text: String) async throws -> String {
        let messages = [["role": "user", "content": text]]
        return try await callAPI(messages: messages)
    }

    func chat(_ text: String) async throws -> String {
        history.append(["role": "user", "content": text])
        let response = try await callAPI(messages: history)
        history.append(["role": "assistant", "content": response])
        return response
    }

    func clearHistory() {
        history.removeAll()
    }

    private func callAPI(messages: [[String: String]]) async throws -> String {
        guard let apiKey = config.apiKey else {
            throw CLIError.noAPIKey
        }

        let baseURL = config.baseURL ?? "https://api.anthropic.com"
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw CLIError.apiError("base_url 형식이 올바르지 않습니다.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = loadSystemPrompt()

        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let msg = error["message"] as? String {
                throw CLIError.apiError(msg)
            }
            throw CLIError.invalidResponse
        }
        return text
    }

    private func loadSystemPrompt() -> String {
        let file = CLIConfig.contextDirectory.appendingPathComponent("system_prompt.md")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? "당신은 도치라는 이름의 AI 어시스턴트입니다."
    }
}

// MARK: - CLI Errors

enum CLIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API 키가 설정되지 않았습니다."
        case .invalidResponse: return "잘못된 API 응답입니다."
        case .apiError(let msg): return "API 오류: \(msg)"
        }
    }
}

let code = await DochiCLI.run()
Foundation.exit(code.rawValue)
