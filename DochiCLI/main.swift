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
            return await handleAsk(query, runtimeMode: invocation.runtimeMode)

        case .chat:
            return await handleChat(outputMode: invocation.outputMode, runtimeMode: invocation.runtimeMode)

        case .context(let action):
            return handleContext(action)

        case .conversation(let action):
            return handleConversation(action)

        case .config(let action):
            return handleConfig(action)

        case .session(let action):
            return handleSession(action, runtimeMode: invocation.runtimeMode)

        case .dev(let action):
            return handleDev(action, runtimeMode: invocation.runtimeMode, outputMode: invocation.outputMode)

        case .doctor:
            return handleDoctor(runtimeMode: invocation.runtimeMode)
        }
    }

    // MARK: - Ask / Chat

    private static func handleAsk(_ query: String, runtimeMode: CLIRuntimeMode) async -> CLIResult {
        if runtimeMode == .standalone {
            return await handleStandaloneAsk(query)
        }

        guard let client = appConnectedClient(runtimeMode: runtimeMode) else {
            return appConnectionFailure(command: "ask", reason: "Dochi 앱이 실행 중이 아닙니다.")
        }

        do {
            let result = try client.call(method: "chat.send", params: ["prompt": query])
            let assistantMessage = result["assistant_message"] as? String ?? "(응답 없음)"
            return CLIResult(exitCode: .success, command: "ask", message: assistantMessage, data: result)
        } catch let error as CLIControlPlaneError {
            return mapControlPlaneError(error, command: "ask")
        } catch {
            return CLIResult(exitCode: .runtimeError, command: "ask", message: "요청 실패: \(error.localizedDescription)")
        }
    }

    private static func handleStandaloneAsk(_ query: String) async -> CLIResult {
        let config = CLIConfig.load()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return CLIResult(
                exitCode: .authError,
                command: "ask",
                message: "standalone API 키가 없습니다. dochi config set api_key <KEY>를 실행하세요."
            )
        }

        let client = DochiCLIClient(config: config)
        do {
            let response = try await client.query(query)
            return CLIResult(exitCode: .success, command: "ask", message: response)
        } catch {
            return CLIResult(exitCode: .runtimeError, command: "ask", message: "standalone 질의 실패: \(error.localizedDescription)")
        }
    }

    private static func handleChat(outputMode: CLIOutputMode, runtimeMode: CLIRuntimeMode) async -> CLIResult {
        if outputMode == .json {
            return CLIResult(exitCode: .invalidUsage, command: "chat", message: "chat 대화 모드는 --json 출력과 함께 사용할 수 없습니다.")
        }

        if runtimeMode == .standalone {
            return await handleStandaloneChat(outputMode: outputMode)
        }

        guard let client = appConnectedClient(runtimeMode: runtimeMode) else {
            return appConnectionFailure(command: "chat", reason: "Dochi 앱이 실행 중이 아닙니다.")
        }

        print("도치 대화 모드 시작 (앱 연결 모드, /quit 종료)")

        while true {
            print("\n> ", terminator: "")
            fflush(stdout)

            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
                continue
            }
            if input == "/quit" || input == "/exit" {
                break
            }

            do {
                let result = try client.call(method: "chat.send", params: ["prompt": input])
                let assistantMessage = result["assistant_message"] as? String ?? "(응답 없음)"
                print("\n\(assistantMessage)")
            } catch let error as CLIControlPlaneError {
                let mapped = mapControlPlaneError(error, command: "chat")
                print("\n오류: \(mapped.message)")
            } catch {
                print("\n오류: \(error.localizedDescription)")
            }
        }

        return CLIResult(exitCode: .success, command: "chat", message: "대화 모드를 종료했습니다.")
    }

    private static func handleStandaloneChat(outputMode: CLIOutputMode) async -> CLIResult {
        if outputMode == .json {
            return CLIResult(exitCode: .invalidUsage, command: "chat", message: "chat 대화 모드는 --json 출력과 함께 사용할 수 없습니다.")
        }

        let config = CLIConfig.load()
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            return CLIResult(
                exitCode: .authError,
                command: "chat",
                message: "standalone API 키가 없습니다. dochi config set api_key <KEY>를 실행하세요."
            )
        }

        print("도치 standalone 대화 모드 시작 (/quit 종료, /clear 기록 초기화)")
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

    private static func handleSession(_ action: CLISessionAction, runtimeMode: CLIRuntimeMode) -> CLIResult {
        guard let client = appConnectedClient(runtimeMode: runtimeMode) else {
            return appConnectionFailure(
                command: sessionCommandName(action),
                reason: "Dochi 앱이 실행 중이 아니거나 연결할 수 없습니다."
            )
        }

        switch action {
        case .list:
            do {
                let result = try client.call(method: "session.list")
                let sessions = result["sessions"] as? [[String: Any]] ?? []
                if sessions.isEmpty {
                    return CLIResult(exitCode: .success, command: "session.list", message: "활성 대화 세션이 없습니다.", data: result)
                }

                var lines: [String] = ["세션 \(sessions.count)개"]
                for (index, session) in sessions.enumerated() {
                    let title = session["title"] as? String ?? "(제목 없음)"
                    let id = session["id"] as? String ?? "unknown"
                    let active = (session["is_active"] as? Bool == true) ? " [active]" : ""
                    lines.append("\(index + 1). \(title)\(active) (\(id))")
                }
                return CLIResult(exitCode: .success, command: "session.list", message: lines.joined(separator: "\n"), data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "session.list")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "session.list", message: "요청 실패: \(error.localizedDescription)")
            }
        }
    }

    private static func handleDev(_ action: CLIDevAction, runtimeMode: CLIRuntimeMode, outputMode: CLIOutputMode) -> CLIResult {
        guard let client = appConnectedClient(runtimeMode: runtimeMode) else {
            return appConnectionFailure(command: "dev", reason: "Dochi 앱이 실행 중이 아니거나 연결할 수 없습니다.")
        }

        switch action {
        case .logRecent(let minutes):
            do {
                let result = try client.call(method: "log.recent", params: ["minutes": minutes])
                let entries = result["entries"] as? [[String: Any]] ?? []
                if entries.isEmpty {
                    return CLIResult(exitCode: .success, command: "dev.log.recent", message: "최근 로그가 없습니다.", data: result)
                }
                let lines = entries.map { entry in
                    let ts = entry["timestamp"] as? String ?? "-"
                    let category = entry["category"] as? String ?? "-"
                    let level = entry["level"] as? String ?? "-"
                    let message = entry["message"] as? String ?? ""
                    return "[\(ts)] [\(category)] [\(level)] \(message)"
                }
                return CLIResult(exitCode: .success, command: "dev.log.recent", message: lines.joined(separator: "\n"), data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.log.recent")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.log.recent", message: "요청 실패: \(error.localizedDescription)")
            }

        case .logTail(let seconds, let category, let level, let contains):
            return handleDevLogTail(
                client: client,
                outputMode: outputMode,
                seconds: seconds,
                category: category,
                level: level,
                contains: contains
            )

        case .chatStream(let prompt):
            return handleDevChatStream(client: client, outputMode: outputMode, prompt: prompt)

        case .tool(let name, let argumentsJSON):
            do {
                let arguments = try parseJSONArguments(argumentsJSON)
                let result = try client.call(method: "tool.execute", params: [
                    "name": name,
                    "arguments": arguments,
                ])
                let content = result["content"] as? String ?? "(도구 응답 없음)"
                return CLIResult(exitCode: .success, command: "dev.tool", message: content, data: result)
            } catch let error as CLIParseError {
                return CLIResult(exitCode: .invalidUsage, command: "dev.tool", message: error.localizedDescription)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.tool")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.tool", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeOpen(let agent, let profileName, let workingDirectory, let forceWorkingDirectory):
            do {
                var params: [String: Any] = ["agent": agent]
                if let profileName, !profileName.isEmpty {
                    params["profile_name"] = profileName
                }
                if let workingDirectory, !workingDirectory.isEmpty {
                    params["working_directory"] = workingDirectory
                }
                if forceWorkingDirectory {
                    params["force_working_directory"] = true
                }

                let result = try client.call(method: "bridge.open", params: params)
                let sessionId = result["session_id"] as? String ?? "-"
                let profile = result["profile_name"] as? String ?? "-"
                let cwd = result["working_directory"] as? String ?? "-"
                let selectionReason = result["selection_reason"] as? String ?? "-"
                let selectionDetail = result["selection_detail"] as? String ?? "-"
                let status = result["status"] as? String ?? "-"
                let reused = (result["reused"] as? Bool == true) ? "재사용" : "새로 생성"
                let message = """
                bridge.open \(reused): profile=\(profile), session_id=\(sessionId), status=\(status), cwd=\(cwd), reason=\(selectionReason)
                detail: \(selectionDetail)
                """
                return CLIResult(exitCode: .success, command: "dev.bridge.open", message: message, data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.open")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.open", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeRoots(let limit, let searchPaths):
            do {
                var params: [String: Any] = ["limit": max(1, min(200, limit))]
                if !searchPaths.isEmpty {
                    params["search_paths"] = searchPaths
                }
                let result = try client.call(method: "bridge.roots", params: params)
                let roots = result["roots"] as? [[String: Any]] ?? []
                guard !roots.isEmpty else {
                    return CLIResult(exitCode: .success, command: "dev.bridge.roots", message: "추천 가능한 Git 루트를 찾지 못했습니다.", data: result)
                }

                let lines = roots.enumerated().map { index, root -> String in
                    let score = root["score"] as? Int ?? 0
                    let name = root["name"] as? String ?? "-"
                    let path = root["path"] as? String ?? "-"
                    let branch = root["branch"] as? String ?? "-"
                    let workDomain = root["work_domain"] as? String ?? "unknown"
                    let relative = root["last_commit_relative"] as? String ?? "unknown"
                    let upstreamRelative = root["upstream_last_commit_relative"] as? String ?? "unknown"
                    let recentCommitCount30d = root["recent_commit_count_30d"] as? Int ?? 0
                    let changedFileCount = root["changed_file_count"] as? Int ?? 0
                    let untrackedFileCount = root["untracked_file_count"] as? Int ?? 0
                    return "\(index + 1). [\(score)] \(name) (\(branch)) | \(workDomain) | local:\(relative) / origin:\(upstreamRelative) | 30d:\(recentCommitCount30d) | dirty:\(changedFileCount)+\(untrackedFileCount)\n   \(path)"
                }
                return CLIResult(exitCode: .success, command: "dev.bridge.roots", message: lines.joined(separator: "\n"), data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.roots")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.roots", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeStatus(let sessionId):
            do {
                let params: [String: Any]
                if let sessionId {
                    params = ["session_id": sessionId]
                } else {
                    params = [:]
                }
                let result = try client.call(method: "bridge.status", params: params)
                if let sessions = result["sessions"] as? [[String: Any]] {
                    var lines = sessions.map { session -> String in
                        let id = session["session_id"] as? String ?? "-"
                        let profile = session["profile_name"] as? String ?? "-"
                        let status = session["status"] as? String ?? "-"
                        return "- \(profile): \(status) (\(id))"
                    }

                    if let unified = result["unified_sessions"] as? [[String: Any]], !unified.isEmpty {
                        if !lines.isEmpty {
                            lines.append("")
                        }
                        let unassignedCount = result["unassigned_count"] as? Int ?? 0
                        lines.append("통합 세션 \(unified.count)개 (unassigned: \(unassignedCount))")
                        for item in unified.prefix(30) {
                            let provider = item["provider"] as? String ?? "unknown"
                            let nativeSessionId = item["native_session_id"] as? String ?? "-"
                            let tier = item["controllability_tier"] as? String ?? "-"
                            let runtimeType = item["runtime_type"] as? String ?? "-"
                            let active = (item["is_active"] as? Bool == true) ? "active" : "inactive"
                            let repositoryRoot = item["repository_root"] as? String ?? "(unassigned)"
                            lines.append("- [\(provider)] \(nativeSessionId) \(active) tier=\(tier) runtime=\(runtimeType) repo=\(repositoryRoot)")
                        }
                        if unified.count > 30 {
                            lines.append("... \(unified.count - 30)개 추가")
                        }
                    } else if let discovered = result["discovered_sessions"] as? [[String: Any]], !discovered.isEmpty {
                        if !lines.isEmpty {
                            lines.append("")
                        }
                        lines.append("파일 기반 감지 세션 \(discovered.count)개")
                        for item in discovered.prefix(20) {
                            let provider = item["provider"] as? String ?? "unknown"
                            let sessionId = item["session_id"] as? String ?? "-"
                            let active = (item["is_active"] as? Bool == true) ? "active" : "inactive"
                            let path = item["path"] as? String ?? "-"
                            lines.append("- [\(provider)] \(sessionId) \(active) @ \(path)")
                        }
                        if discovered.count > 20 {
                            lines.append("... \(discovered.count - 20)개 추가")
                        }
                    }

                    let message = lines.isEmpty ? "브리지/파일 기반 세션이 없습니다." : lines.joined(separator: "\n")
                    return CLIResult(exitCode: .success, command: "dev.bridge.status", message: message, data: result)
                }

                let id = result["session_id"] as? String ?? "-"
                let profile = result["profile_name"] as? String ?? "-"
                let status = result["status"] as? String ?? "-"
                return CLIResult(
                    exitCode: .success,
                    command: "dev.bridge.status",
                    message: "\(profile): \(status) (\(id))",
                    data: result
                )
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.status")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.status", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeSend(let sessionId, let command):
            do {
                let result = try client.call(method: "bridge.send", params: [
                    "session_id": sessionId,
                    "command": command,
                ])
                return CLIResult(exitCode: .success, command: "dev.bridge.send", message: "전송 완료", data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.send")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.send", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeRead(let sessionId, let lines):
            do {
                let result = try client.call(method: "bridge.read", params: [
                    "session_id": sessionId,
                    "lines": lines,
                ])
                let output = result["lines"] as? [String] ?? []
                let message = output.isEmpty ? "(출력 없음)" : output.joined(separator: "\n")
                return CLIResult(exitCode: .success, command: "dev.bridge.read", message: message, data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.read")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.read", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeRepoList:
            do {
                let result = try client.call(method: "bridge.repo.list")
                let repositories = result["repositories"] as? [[String: Any]] ?? []
                guard !repositories.isEmpty else {
                    return CLIResult(exitCode: .success, command: "dev.bridge.repo.list", message: "등록된 레포가 없습니다.", data: result)
                }

                let lines = repositories.enumerated().map { index, repository in
                    let id = repository["repository_id"] as? String ?? "-"
                    let name = repository["name"] as? String ?? "-"
                    let path = repository["root_path"] as? String ?? "-"
                    let branch = repository["default_branch"] as? String ?? "-"
                    let source = repository["source"] as? String ?? "unknown"
                    return "\(index + 1). \(name) [\(source)] (\(branch))\n   id=\(id)\n   \(path)"
                }
                return CLIResult(exitCode: .success, command: "dev.bridge.repo.list", message: lines.joined(separator: "\n"), data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.repo.list")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.repo.list", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeRepoInit(let path, let defaultBranch, let createReadme, let createGitignore):
            do {
                let result = try client.call(method: "bridge.repo.init", params: [
                    "path": path,
                    "default_branch": defaultBranch,
                    "create_readme": createReadme,
                    "create_gitignore": createGitignore,
                ])
                let repository = result["repository"] as? [String: Any]
                let rootPath = repository?["root_path"] as? String ?? path
                return CLIResult(exitCode: .success, command: "dev.bridge.repo.init", message: "레포 초기화 및 등록 완료: \(rootPath)", data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.repo.init")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.repo.init", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeRepoClone(let remoteURL, let destinationPath, let branch):
            do {
                var params: [String: Any] = [
                    "remote_url": remoteURL,
                    "destination_path": destinationPath,
                ]
                if let branch, !branch.isEmpty {
                    params["branch"] = branch
                }
                let result = try client.call(method: "bridge.repo.clone", params: params)
                let repository = result["repository"] as? [String: Any]
                let rootPath = repository?["root_path"] as? String ?? destinationPath
                return CLIResult(exitCode: .success, command: "dev.bridge.repo.clone", message: "레포 클론 및 등록 완료: \(rootPath)", data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.repo.clone")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.repo.clone", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeRepoAttach(let path):
            do {
                let result = try client.call(method: "bridge.repo.attach", params: ["path": path])
                let repository = result["repository"] as? [String: Any]
                let rootPath = repository?["root_path"] as? String ?? path
                return CLIResult(exitCode: .success, command: "dev.bridge.repo.attach", message: "레포 연결 완료: \(rootPath)", data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.repo.attach")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.repo.attach", message: "요청 실패: \(error.localizedDescription)")
            }

        case .bridgeRepoRemove(let repositoryId, let deleteDirectory):
            do {
                let result = try client.call(method: "bridge.repo.remove", params: [
                    "repository_id": repositoryId,
                    "delete_directory": deleteDirectory,
                ])
                return CLIResult(exitCode: .success, command: "dev.bridge.repo.remove", message: "레포 제거 완료: \(repositoryId)", data: result)
            } catch let error as CLIControlPlaneError {
                return mapControlPlaneError(error, command: "dev.bridge.repo.remove")
            } catch {
                return CLIResult(exitCode: .runtimeError, command: "dev.bridge.repo.remove", message: "요청 실패: \(error.localizedDescription)")
            }
        }
    }

    private static func handleDevChatStream(
        client: CLIControlPlaneClient,
        outputMode: CLIOutputMode,
        prompt: String
    ) -> CLIResult {
        do {
            let openResult = try client.call(method: "chat.stream.open", params: ["prompt": prompt])
            guard let streamId = openResult["stream_id"] as? String, !streamId.isEmpty else {
                return CLIResult(exitCode: .runtimeError, command: "dev.chat.stream", message: "chat.stream.open 응답에 stream_id가 없습니다.")
            }
            let correlationId = openResult["correlation_id"] as? String ?? "-"

            var collected: [[String: Any]] = []
            defer {
                _ = try? client.call(method: "chat.stream.close", params: ["stream_id": streamId])
            }

            if outputMode == .text {
                print("chat.stream 시작: stream_id=\(streamId), correlation_id=\(correlationId)")
            }

            while true {
                let readResult = try client.call(method: "chat.stream.read", params: [
                    "stream_id": streamId,
                    "limit": 80,
                ])
                let events = readResult["events"] as? [[String: Any]] ?? []
                collected.append(contentsOf: events)

                if outputMode == .text {
                    renderChatStreamEvents(events)
                }

                let done = readResult["done"] as? Bool ?? false
                if done {
                    let errorMessage = readResult["error_message"] as? String
                    if let errorMessage, !errorMessage.isEmpty {
                        return CLIResult(
                            exitCode: .runtimeError,
                            command: "dev.chat.stream",
                            message: "스트림 실패: \(errorMessage)",
                            data: [
                                "stream_id": streamId,
                                "correlation_id": correlationId,
                                "events": collected,
                            ]
                        )
                    }

                    return CLIResult(
                        exitCode: .success,
                        command: "dev.chat.stream",
                        message: "chat.stream 완료 (events: \(collected.count), correlation_id: \(correlationId))",
                        data: [
                            "stream_id": streamId,
                            "correlation_id": correlationId,
                            "events": collected,
                        ]
                    )
                }

                Thread.sleep(forTimeInterval: 0.2)
            }
        } catch let error as CLIControlPlaneError {
            return mapControlPlaneError(error, command: "dev.chat.stream")
        } catch {
            return CLIResult(exitCode: .runtimeError, command: "dev.chat.stream", message: "요청 실패: \(error.localizedDescription)")
        }
    }

    private static func handleDevLogTail(
        client: CLIControlPlaneClient,
        outputMode: CLIOutputMode,
        seconds: Int,
        category: String?,
        level: String?,
        contains: String?
    ) -> CLIResult {
        do {
            let lookbackSeconds = max(1, min(3_600, seconds))
            var openParams: [String: Any] = [
                "lookback_seconds": lookbackSeconds,
            ]
            if let category, !category.isEmpty {
                openParams["category"] = category
            }
            if let level, !level.isEmpty {
                openParams["level"] = level
            }
            if let contains, !contains.isEmpty {
                openParams["contains"] = contains
            }

            let openResult = try client.call(method: "log.tail.open", params: openParams)
            guard let tailId = openResult["tail_id"] as? String, !tailId.isEmpty else {
                return CLIResult(exitCode: .runtimeError, command: "dev.log.tail", message: "log.tail.open 응답에 tail_id가 없습니다.")
            }
            let correlationId = openResult["correlation_id"] as? String ?? "-"

            var collected: [[String: Any]] = []
            defer {
                _ = try? client.call(method: "log.tail.close", params: ["tail_id": tailId])
            }

            if outputMode == .text {
                print("log.tail 시작: tail_id=\(tailId), correlation_id=\(correlationId), duration=\(seconds)s")
            }

            let deadline = Date().addingTimeInterval(TimeInterval(max(1, seconds)))
            while Date() < deadline {
                let readResult = try client.call(method: "log.tail.read", params: [
                    "tail_id": tailId,
                    "limit": 200,
                ])
                let events = readResult["events"] as? [[String: Any]] ?? []
                collected.append(contentsOf: events)

                if outputMode == .text {
                    renderLogTailEvents(events)
                }

                Thread.sleep(forTimeInterval: 1.0)
            }

            return CLIResult(
                exitCode: .success,
                command: "dev.log.tail",
                message: "log.tail 종료 (events: \(collected.count), correlation_id: \(correlationId))",
                data: [
                    "tail_id": tailId,
                    "correlation_id": correlationId,
                    "events": collected,
                ]
            )
        } catch let error as CLIControlPlaneError {
            return mapControlPlaneError(error, command: "dev.log.tail")
        } catch {
            return CLIResult(exitCode: .runtimeError, command: "dev.log.tail", message: "요청 실패: \(error.localizedDescription)")
        }
    }

    private static func renderChatStreamEvents(_ events: [[String: Any]]) {
        for event in events {
            let type = event["type"] as? String ?? "unknown"
            switch type {
            case "partial":
                let text = event["text"] as? String ?? ""
                if !text.isEmpty {
                    print(text, terminator: "")
                    fflush(stdout)
                }
            case "tool_call":
                let toolName = event["tool_name"] as? String ?? "unknown"
                print("\n[tool_call] \(toolName)")
            case "tool_result":
                let text = event["text"] as? String ?? ""
                let preview = text.isEmpty ? "(empty)" : text
                print("\n[tool_result] \(preview)")
            case "done":
                print("\n[done]")
            case "error":
                let text = event["text"] as? String ?? "(error)"
                print("\n[error] \(text)")
            default:
                let text = event["text"] as? String ?? ""
                print("\n[\(type)] \(text)")
            }
        }
    }

    private static func renderLogTailEvents(_ events: [[String: Any]]) {
        guard !events.isEmpty else { return }
        for event in events {
            let ts = event["timestamp"] as? String ?? "-"
            let category = event["category"] as? String ?? "-"
            let level = event["level"] as? String ?? "-"
            let message = event["message"] as? String ?? ""
            print("[\(ts)] [\(category)] [\(level)] \(message)")
        }
    }

    // MARK: - Doctor

    private static func handleDoctor(runtimeMode: CLIRuntimeMode) -> CLIResult {
        let contextDir = CLIConfig.contextDirectory
        let configFile = CLIConfig.configFile
        let config = CLIConfig.load()
        let appRunning = AppConnectionProbe.isDochiAppRunning()
        let socketPath = CLIControlPlaneClient.defaultSocketURL.path
        let socketExists = FileManager.default.fileExists(atPath: socketPath)
        let tokenPath = CLIControlPlaneClient.defaultTokenURL.path
        let tokenExists = FileManager.default.fileExists(atPath: tokenPath)
        let tokenReadable = (try? String(contentsOfFile: tokenPath, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false

        let pingOK: Bool
        let pingDetail: String
        if appRunning && socketExists {
            do {
                let pingResult = try CLIControlPlaneClient().call(method: "app.ping")
                let version = pingResult["version"] as? String ?? "unknown"
                pingOK = true
                pingDetail = "connected (version: \(version))"
            } catch {
                pingOK = false
                pingDetail = "connection failed: \(error.localizedDescription)"
            }
        } else {
            pingOK = false
            pingDetail = "skipped (app/socket unavailable)"
        }

        let checks: [(name: String, ok: Bool, detail: String)] = [
            ("context_dir", FileManager.default.fileExists(atPath: contextDir.path), contextDir.path),
            ("config_file", FileManager.default.fileExists(atPath: configFile.path), configFile.path),
            ("app_running", appRunning, "bundle: com.hckim.dochi"),
            ("control_plane_socket", socketExists, socketPath),
            ("control_plane_token_file", (tokenExists && tokenReadable), tokenPath),
            ("control_plane_ping", pingOK, pingDetail),
            ("mode", true, runtimeMode.rawValue),
        ]

        var mutableChecks = checks
        if runtimeMode == .standalone {
            mutableChecks.append(("standalone_api_key", (config.apiKey?.isEmpty == false), "cli_config api_key"))
        }

        let okCount = mutableChecks.filter { $0.ok }.count
        let status = okCount == mutableChecks.count ? "정상" : "확인 필요"

        var lines = ["doctor 결과: \(status) (\(okCount)/\(mutableChecks.count))"]
        for check in mutableChecks {
            lines.append("- \(check.ok ? "OK" : "FAIL") \(check.name): \(check.detail)")
        }

        let structuredChecks = mutableChecks.map { check -> [String: Any] in
            [
                "name": check.name,
                "ok": check.ok,
                "detail": check.detail,
            ]
        }

        return CLIResult(
            exitCode: okCount == mutableChecks.count ? .success : .connectionError,
            command: "doctor",
            message: lines.joined(separator: "\n"),
            data: [
                "status": status,
                "ok_count": okCount,
                "total_count": mutableChecks.count,
                "checks": structuredChecks,
            ]
        )
    }

    // MARK: - Helpers

    private static func appConnectedClient(runtimeMode: CLIRuntimeMode) -> CLIControlPlaneClient? {
        if runtimeMode == .standalone {
            return nil
        }
        guard AppConnectionProbe.isDochiAppRunning() else {
            return nil
        }
        return CLIControlPlaneClient()
    }

    private static func appConnectionFailure(command: String, reason: String) -> CLIResult {
        let message = """
            \(reason)
            확인할 항목:
            1) Dochi 앱이 실행 중인지 확인하세요.
            2) `dochi doctor`로 연결 상태를 점검하세요.
            3) 디버그용 standalone은 `--mode standalone --allow-standalone`으로만 사용하세요.
            """
        return CLIResult(exitCode: .connectionError, command: command, message: message)
    }

    private static func mapControlPlaneError(_ error: CLIControlPlaneError, command: String) -> CLIResult {
        switch error {
        case .connectFailed, .responseReadFailed:
            return appConnectionFailure(command: command, reason: "Control Plane 연결에 실패했습니다.")
        case .socketPathTooLong, .requestEncodeFailed, .responseDecodeFailed:
            return CLIResult(exitCode: .runtimeError, command: command, message: "Control Plane 처리 오류: \(error.localizedDescription)")
        case .remoteError(let code, let message):
            if code == "unauthorized" {
                return CLIResult(
                    exitCode: .authError,
                    command: command,
                    message: """
                        로컬 API 인증에 실패했습니다.
                        확인할 항목:
                        1) Dochi 앱이 실행 중인지 확인하세요.
                        2) `dochi doctor`로 토큰/소켓 상태를 점검하세요.
                        상세: \(message)
                        """
                )
            }
            return CLIResult(exitCode: .runtimeError, command: command, message: "앱 요청 실패 (\(code)): \(message)")
        }
    }

    private static func parseJSONArguments(_ argumentsJSON: String?) throws -> [String: Any] {
        guard let argumentsJSON, !argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }
        guard let data = argumentsJSON.data(using: .utf8) else {
            throw CLIParseError.invalidUsage("arguments_json은 유효한 UTF-8 문자열이어야 합니다.")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIParseError.invalidUsage("arguments_json은 JSON object 형태여야 합니다.")
        }
        return json
    }

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
          dochi dev log tail [--seconds N] [--category C] [--level L] [--contains K]
          dochi dev chat stream <prompt>
          dochi dev bridge open [agent] [--profile NAME] [--cwd DIR] [--force-working-directory]
          dochi dev bridge roots [--limit N] [--path DIR]...
          dochi dev bridge status [session_id]
          dochi dev bridge send <session_id> <command>
          dochi dev bridge read <session_id> [lines]
          dochi dev bridge repo list
          dochi dev bridge repo init <path> [--branch NAME] [--readme] [--gitignore]
          dochi dev bridge repo clone <remote_url> <destination_path> [--branch NAME]
          dochi dev bridge repo attach <path>
          dochi dev bridge repo remove <repository_id> [--delete-directory]
          dochi doctor

        전역 옵션:
          --mode <auto|app|standalone>
          --allow-standalone (디버그 전용)
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

// MARK: - Standalone Client (Debug Only)

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
