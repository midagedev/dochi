import Foundation

// MARK: - Dochi CLI Client

/// Lightweight CLI for interacting with Dochi.
/// Supports single-shot queries and interactive chat mode.

@MainActor
enum DochiCLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()

        if args.isEmpty || args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }

        let command = args.first!

        switch command {
        case "chat":
            await startChatMode()
        case "context":
            handleContext(Array(args.dropFirst()))
        case "conversations":
            handleConversations(Array(args.dropFirst()))
        case "version":
            print("dochi-cli v1.0.0")
        default:
            // Treat entire args as a single query
            let query = args.joined(separator: " ")
            await sendQuery(query)
        }
    }

    // MARK: - Single Query

    static func sendQuery(_ query: String) async {
        print("🔄 처리 중...", terminator: "")
        fflush(stdout)

        let config = CLIConfig.load()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            print("\n❌ API 키가 설정되지 않았습니다.")
            print("   설정: dochi config set api_key <YOUR_KEY>")
            return
        }

        let client = DochiCLIClient(config: config)
        do {
            let response = try await client.query(query)
            print("\r\(String(repeating: " ", count: 20))\r", terminator: "") // clear line
            print(response)
        } catch {
            print("\n❌ 오류: \(error.localizedDescription)")
        }
    }

    // MARK: - Chat Mode

    static func startChatMode() async {
        print("💬 도치 대화 모드 (종료: /quit)")
        print(String(repeating: "─", count: 40))

        let config = CLIConfig.load()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            print("❌ API 키가 설정되지 않았습니다.")
            return
        }

        let client = DochiCLIClient(config: config)

        while true {
            print("\n> ", terminator: "")
            fflush(stdout)
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty else { continue }

            if input == "/quit" || input == "/exit" {
                print("👋 대화를 종료합니다.")
                break
            }

            if input == "/clear" {
                client.clearHistory()
                print("🗑️ 대화 기록이 초기화되었습니다.")
                continue
            }

            do {
                let response = try await client.chat(input)
                print("\n\(response)")
            } catch {
                print("\n❌ 오류: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Context

    static func handleContext(_ args: [String]) {
        guard let sub = args.first else {
            print("사용법: dochi context [show|edit] [system|memory]")
            return
        }

        let contextDir = CLIConfig.contextDirectory
        let target = args.count > 1 ? args[1] : "system"
        let filename = target == "memory" ? "memory.md" : "system_prompt.md"
        let filePath = contextDir.appendingPathComponent(filename)

        switch sub {
        case "show":
            if let content = try? String(contentsOf: filePath, encoding: .utf8) {
                print(content)
            } else {
                print("(파일 없음: \(filePath.path))")
            }
        case "edit":
            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "nano"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [editor, filePath.path]
            try? process.run()
            process.waitUntilExit()
        default:
            print("알 수 없는 명령: \(sub)")
        }
    }

    // MARK: - Conversations

    static func handleConversations(_ args: [String]) {
        let sub = args.first ?? "list"
        let contextDir = CLIConfig.contextDirectory
        let convDir = contextDir.appendingPathComponent("conversations")

        switch sub {
        case "list":
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: convDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else {
                print("대화가 없습니다.")
                return
            }

            let jsonFiles = files.filter { $0.pathExtension == "json" }
                .sorted {
                    let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return d1 > d2
                }

            if jsonFiles.isEmpty {
                print("대화가 없습니다.")
                return
            }

            print("최근 대화 (\(jsonFiles.count)개):")
            for (i, file) in jsonFiles.prefix(10).enumerated() {
                let name = file.deletingPathExtension().lastPathComponent
                print("  \(i + 1). \(name)")
            }

        default:
            print("사용법: dochi conversations list")
        }
    }

    // MARK: - Usage

    static func printUsage() {
        print("""
        도치 CLI v1.0.0

        사용법:
          dochi <질문>                    단발 질문
          dochi chat                      대화 모드
          dochi context show [system|memory]  컨텍스트 보기
          dochi context edit [system|memory]  컨텍스트 편집
          dochi conversations list         대화 목록
          dochi version                    버전 정보
          dochi --help                     도움말

        설정:
          dochi config set api_key <KEY>   API 키 설정
          dochi config set model <MODEL>   모델 설정
          dochi config show                현재 설정 보기
        """)
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

@MainActor
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
        let url = URL(string: "\(baseURL)/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Load system prompt
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
            // Check for error
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
        case .noAPIKey: "API 키가 설정되지 않았습니다."
        case .invalidResponse: "잘못된 API 응답입니다."
        case .apiError(let msg): "API 오류: \(msg)"
        }
    }
}

// Entry point
await DochiCLI.main()
