import Foundation

// MARK: - K-4: External Tool LLM Tools

/// Registers external AI tool management tools with the BuiltInToolService.
enum ExternalToolTools {

    @MainActor
    static func register(
        toolService: BuiltInToolService,
        manager: ExternalToolSessionManagerProtocol
    ) {
        toolService.registerTool(ExternalToolRegisterTool(manager: manager))
        toolService.registerTool(ExternalToolStartTool(manager: manager))
        toolService.registerTool(ExternalToolStatusTool(manager: manager))
        toolService.registerTool(ExternalToolDispatchTool(manager: manager))
        toolService.registerTool(ExternalToolReadOutputTool(manager: manager))
        toolService.registerTool(ExternalToolStopTool(manager: manager))
        Log.tool.info("Registered 6 external tool management tools (K-4)")
    }
}

// MARK: - external_tool.register (sensitive)

@MainActor
final class ExternalToolRegisterTool: BuiltInToolProtocol {
    let name = "external_tool.register"
    let category: ToolCategory = .sensitive
    let description = "외부 AI 도구 프로파일을 등록하거나 수정합니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "도구 이름"],
                "command": ["type": "string", "description": "실행 명령"],
                "arguments": ["type": "array", "items": ["type": "string"], "description": "명령 인자"],
                "working_directory": ["type": "string", "description": "작업 디렉토리"],
                "preset": ["type": "string", "enum": ["claude_code", "codex_cli", "aider"], "description": "프리셋"],
            ] as [String: Any],
            "required": ["name", "command"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let name = arguments["name"] as? String,
              let command = arguments["command"] as? String else {
            return ToolResult(toolCallId: "", content: "name과 command는 필수입니다.", isError: true)
        }

        let args = arguments["arguments"] as? [String] ?? []
        let workingDir = arguments["working_directory"] as? String ?? "~"

        var patterns = HealthCheckPatterns.claudeCode
        if let preset = arguments["preset"] as? String {
            switch preset {
            case "codex_cli": patterns = .codexCLI
            case "aider": patterns = .aider
            default: break
            }
        }

        let profile = ExternalToolProfile(
            name: name,
            command: command,
            arguments: args,
            workingDirectory: workingDir,
            healthCheckPatterns: patterns
        )
        manager.saveProfile(profile)

        return ToolResult(
            toolCallId: "",
            content: "프로파일 등록 완료: \(name) (ID: \(profile.id.uuidString))"
        )
    }
}

// MARK: - external_tool.start (restricted)

@MainActor
final class ExternalToolStartTool: BuiltInToolProtocol {
    let name = "external_tool.start"
    let category: ToolCategory = .restricted
    let description = "외부 AI 도구 세션을 시작합니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "profile_id": ["type": "string", "description": "프로파일 ID (UUID)"],
            ] as [String: Any],
            "required": ["profile_id"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let profileIdStr = arguments["profile_id"] as? String,
              let profileId = UUID(uuidString: profileIdStr) else {
            return ToolResult(toolCallId: "", content: "유효한 profile_id가 필요합니다.", isError: true)
        }

        do {
            try await manager.startSession(profileId: profileId)
            return ToolResult(toolCallId: "", content: "세션 시작됨: \(profileIdStr)")
        } catch {
            return ToolResult(toolCallId: "", content: error.localizedDescription, isError: true)
        }
    }
}

// MARK: - external_tool.status (safe)

@MainActor
final class ExternalToolStatusTool: BuiltInToolProtocol {
    let name = "external_tool.status"
    let category: ToolCategory = .safe
    let description = "등록된 외부 AI 도구 세션의 상태를 조회합니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 ID (UUID, 생략 시 전체)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        if let sessionIdStr = arguments["session_id"] as? String,
           let sessionId = UUID(uuidString: sessionIdStr) {
            guard let session = manager.sessions.first(where: { $0.id == sessionId }) else {
                return ToolResult(toolCallId: "", content: "세션을 찾을 수 없습니다: \(sessionIdStr)", isError: true)
            }
            let profileName = manager.profiles.first(where: { $0.id == session.profileId })?.name ?? "?"
            return ToolResult(
                toolCallId: "",
                content: "[\(profileName)] 상태: \(session.status.rawValue), tmux: \(session.tmuxSessionName)"
            )
        }

        // Return all sessions
        if manager.sessions.isEmpty {
            return ToolResult(toolCallId: "", content: "실행 중인 세션이 없습니다.")
        }
        let lines = manager.sessions.map { session -> String in
            let profileName = manager.profiles.first(where: { $0.id == session.profileId })?.name ?? "?"
            return "- \(profileName): \(session.status.rawValue) (ID: \(session.id.uuidString))"
        }
        return ToolResult(toolCallId: "", content: lines.joined(separator: "\n"))
    }
}

// MARK: - external_tool.dispatch (sensitive)

@MainActor
final class ExternalToolDispatchTool: BuiltInToolProtocol {
    let name = "external_tool.dispatch"
    let category: ToolCategory = .sensitive
    let description = "외부 AI 도구 세션에 작업 명령을 전송합니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 ID (UUID)"],
                "command": ["type": "string", "description": "전송할 명령"],
            ] as [String: Any],
            "required": ["session_id", "command"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let sessionIdStr = arguments["session_id"] as? String,
              let sessionId = UUID(uuidString: sessionIdStr),
              let command = arguments["command"] as? String else {
            return ToolResult(toolCallId: "", content: "session_id와 command는 필수입니다.", isError: true)
        }

        do {
            try await manager.sendCommand(sessionId: sessionId, command: command)
            return ToolResult(toolCallId: "", content: "명령 전송됨: \(command)")
        } catch {
            return ToolResult(toolCallId: "", content: error.localizedDescription, isError: true)
        }
    }
}

// MARK: - external_tool.read_output (safe)

@MainActor
final class ExternalToolReadOutputTool: BuiltInToolProtocol {
    let name = "external_tool.read_output"
    let category: ToolCategory = .safe
    let description = "외부 AI 도구 세션의 최근 출력을 읽습니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 ID (UUID)"],
                "lines": ["type": "integer", "description": "읽을 줄 수 (기본: 50)"],
            ] as [String: Any],
            "required": ["session_id"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let sessionIdStr = arguments["session_id"] as? String,
              let sessionId = UUID(uuidString: sessionIdStr) else {
            return ToolResult(toolCallId: "", content: "유효한 session_id가 필요합니다.", isError: true)
        }

        let lineCount = arguments["lines"] as? Int ?? 50
        let output = await manager.captureOutput(sessionId: sessionId, lines: lineCount)
        if output.isEmpty {
            return ToolResult(toolCallId: "", content: "(출력 없음)")
        }
        return ToolResult(toolCallId: "", content: output.joined(separator: "\n"))
    }
}

// MARK: - external_tool.stop (restricted)

@MainActor
final class ExternalToolStopTool: BuiltInToolProtocol {
    let name = "external_tool.stop"
    let category: ToolCategory = .restricted
    let description = "외부 AI 도구 세션을 종료합니다."
    let isBaseline = false

    private let manager: ExternalToolSessionManagerProtocol

    init(manager: ExternalToolSessionManagerProtocol) {
        self.manager = manager
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "session_id": ["type": "string", "description": "세션 ID (UUID)"],
            ] as [String: Any],
            "required": ["session_id"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let sessionIdStr = arguments["session_id"] as? String,
              let sessionId = UUID(uuidString: sessionIdStr) else {
            return ToolResult(toolCallId: "", content: "유효한 session_id가 필요합니다.", isError: true)
        }

        await manager.stopSession(id: sessionId)
        return ToolResult(toolCallId: "", content: "세션 종료됨: \(sessionIdStr)")
    }
}
