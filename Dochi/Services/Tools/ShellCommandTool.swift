import Foundation

@MainActor
final class ShellCommandTool: BuiltInToolProtocol {
    let name = "shell.execute"
    let category: ToolCategory = .restricted
    let description = "셸 명령을 실행합니다. 사용자 확인이 필요합니다."
    let isBaseline = false

    private static let maxOutputSize = 8000
    private static let defaultTimeout = 30

    private let contextService: ContextServiceProtocol
    private let sessionContext: SessionContext
    private let settings: AppSettings

    /// Confirmation handler injected by BuiltInToolService
    var confirmationHandler: ToolConfirmationHandler?

    init(
        contextService: ContextServiceProtocol,
        sessionContext: SessionContext,
        settings: AppSettings
    ) {
        self.contextService = contextService
        self.sessionContext = sessionContext
        self.settings = settings
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "command": ["type": "string", "description": "실행할 셸 명령"],
                "timeout": ["type": "integer", "description": "타임아웃 (초, 기본 30)"],
                "working_directory": ["type": "string", "description": "작업 디렉토리 (선택, 기본: 홈 디렉토리)"],
            ] as [String: Any],
            "required": ["command"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let command = arguments["command"] as? String, !command.isEmpty else {
            return ToolResult(toolCallId: "", content: "command 파라미터가 필요합니다.", isError: true)
        }

        // Load the active agent's shell permission config
        let agentName = settings.activeAgentName
        let agentConfig = contextService.loadAgentConfig(
            workspaceId: sessionContext.workspaceId,
            agentName: agentName
        )
        let shellConfig = agentConfig?.effectiveShellPermissions ?? .default

        // Check permission
        let permissionResult = shellConfig.matchResult(for: command)

        switch permissionResult {
        case .blocked(let pattern):
            Log.tool.warning("Blocked dangerous command: \(command) (pattern: \(pattern))")
            return ToolResult(toolCallId: "", content: "위험한 명령이 차단되었습니다: \(pattern)", isError: true)

        case .confirm(let pattern):
            Log.tool.info("Command requires confirmation: \(command) (pattern: \(pattern))")
            if let handler = confirmationHandler {
                let approved = await handler(name, "셸 명령 실행: \(command)")
                if !approved {
                    Log.tool.info("Shell command denied by user: \(command)")
                    return ToolResult(toolCallId: "", content: "명령 실행이 사용자에 의해 거부되었습니다.", isError: true)
                }
            }

        case .allowed:
            Log.tool.debug("Command allowed by shell permissions: \(command)")
            // No confirmation needed

        case .defaultCategory:
            // No pattern matched — ask for confirmation as default restricted behavior
            Log.tool.debug("Command not in any shell permission list, requesting confirmation: \(command)")
            if let handler = confirmationHandler {
                let approved = await handler(name, "셸 명령 실행: \(command)")
                if !approved {
                    Log.tool.info("Shell command denied by user: \(command)")
                    return ToolResult(toolCallId: "", content: "명령 실행이 사용자에 의해 거부되었습니다.", isError: true)
                }
            }
        }

        let timeout = arguments["timeout"] as? Int ?? Self.defaultTimeout
        let workingDir: String?
        if let dir = arguments["working_directory"] as? String, !dir.isEmpty {
            let expanded = NSString(string: dir).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                return ToolResult(toolCallId: "", content: "작업 디렉토리를 찾을 수 없습니다: \(dir)", isError: true)
            }
            workingDir = expanded
        } else {
            workingDir = nil
        }

        do {
            let result = try await runShell(command: command, timeout: TimeInterval(timeout), workingDirectory: workingDir)
            let output = result.isEmpty ? "(출력 없음)" : result
            let truncated = output.count > Self.maxOutputSize
                ? String(output.prefix(Self.maxOutputSize)) + "\n…(잘림)"
                : output
            return ToolResult(toolCallId: "", content: "실행 결과:\n```\n\(truncated)\n```")
        } catch {
            return ToolResult(toolCallId: "", content: "명령 실행 실패: \(error.localizedDescription)", isError: true)
        }
    }

    private func runShell(command: String, timeout: TimeInterval, workingDirectory: String?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]
                process.environment = ProcessInfo.processInfo.environment
                if let dir = workingDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: dir)
                }

                let pipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errPipe

                let timeoutItem = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

                do {
                    try process.run()
                    process.waitUntilExit()
                    timeoutItem.cancel()

                    let stdout = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                    let exitCode = process.terminationStatus
                    var result = stdout
                    if !stderr.isEmpty {
                        result += (result.isEmpty ? "" : "\n") + "stderr: " + stderr
                    }
                    if exitCode != 0 {
                        result += "\n(exit code: \(exitCode))"
                    }
                    continuation.resume(returning: result)
                } catch {
                    timeoutItem.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
