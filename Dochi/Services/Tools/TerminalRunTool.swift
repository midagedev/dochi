import Foundation

/// terminal.run — LLM이 터미널에서 명령을 실행하는 도구 (restricted)
@MainActor
final class TerminalRunTool: BuiltInToolProtocol {
    let name = "terminal.run"
    let category: ToolCategory = .restricted
    let description = "터미널에서 명령을 실행하고 결과를 반환합니다."
    let isBaseline = false

    private nonisolated(unsafe) static let maxOutputSize = 8000
    private nonisolated(unsafe) static let defaultTimeout = 30

    /// 위험 명령 차단 패턴 (C-3)
    static let dangerousPatterns: [String] = [
        "rm -rf /",
        "rm -rf /*",
        "sudo ",
        "shutdown",
        "reboot",
        "mkfs",
        "dd if=",
        ":(){:|:&};:",
        "chmod -R 777 /",
        "mv /* ",
        "> /dev/sda",
        "curl | bash",
        "curl | sh",
        "wget | bash",
        "wget | sh",
        "| bash",
        "| sh -",
    ]

    private let settings: AppSettings
    private weak var terminalService: (any TerminalServiceProtocol)?

    /// Confirmation handler — BuiltInToolService에서 주입 (C-4)
    var confirmationHandler: ToolConfirmationHandler?

    init(settings: AppSettings, terminalService: (any TerminalServiceProtocol)?) {
        self.settings = settings
        self.terminalService = terminalService
    }

    /// 서비스 후주입 (C-6)
    func updateTerminalService(_ service: TerminalServiceProtocol) {
        self.terminalService = service
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "command": ["type": "string", "description": "실행할 명령"],
                "timeout": ["type": "integer", "description": "타임아웃 (초, 기본 30)"],
            ] as [String: Any],
            "required": ["command"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard settings.terminalLLMEnabled else {
            return ToolResult(
                toolCallId: "",
                content: "터미널 LLM 연동이 비활성화되어 있습니다. 설정 > 터미널에서 활성화하세요.",
                isError: true
            )
        }

        guard let command = arguments["command"] as? String, !command.isEmpty else {
            return ToolResult(
                toolCallId: "",
                content: "command 파라미터가 필요합니다.",
                isError: true
            )
        }

        // C-3: 위험 명령 차단
        if let blockedPattern = Self.checkDangerousCommand(command) {
            Log.tool.warning("terminal.run blocked dangerous command: \(command) (pattern: \(blockedPattern))")
            return ToolResult(
                toolCallId: "",
                content: "위험한 명령이 차단되었습니다: \(blockedPattern)",
                isError: true
            )
        }

        // C-4: terminalLLMConfirmAlways가 true이면 사용자 확인 요청
        if settings.terminalLLMConfirmAlways {
            if let handler = confirmationHandler {
                let approved = await handler(name, "터미널 명령 실행: \(command)")
                if !approved {
                    Log.tool.info("terminal.run denied by user: \(command)")
                    return ToolResult(
                        toolCallId: "",
                        content: "명령 실행이 사용자에 의해 거부되었습니다.",
                        isError: true
                    )
                }
            }
        }

        let timeout = arguments["timeout"] as? Int ?? Self.defaultTimeout

        guard let service = terminalService else {
            // Fallback: direct execution without terminal UI
            return await executeDirectly(command: command, timeout: timeout)
        }

        Log.tool.info("terminal.run executing: \(command)")

        let result = await service.runCommand(command, timeout: timeout)

        let statusText = result.isError ? "실패 (exit \(result.exitCode))" : "성공"
        let output = result.output.isEmpty ? "(출력 없음)" : result.output

        return ToolResult(
            toolCallId: "",
            content: "[\(statusText)]\n\(output)",
            isError: result.isError
        )
    }

    /// 위험 명령 패턴 검사 (C-3). 차단된 패턴 문자열을 반환, 안전하면 nil
    static func checkDangerousCommand(_ command: String) -> String? {
        let lowered = command.lowercased()
        // Normalize pipe whitespace for pattern matching
        let normalized = lowered.replacingOccurrences(of: "\\s*\\|\\s*", with: " | ", options: .regularExpression)
        for pattern in dangerousPatterns {
            if normalized.contains(pattern.lowercased()) {
                return pattern
            }
        }
        return nil
    }

    private func executeDirectly(command: String, timeout: Int) async -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings.terminalShellPath)
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ToolResult(toolCallId: "", content: "실행 실패: \(error.localizedDescription)", isError: true)
        }

        return await withCheckedContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                if process.isRunning { process.terminate() }
            }

            Task.detached {
                // Read pipe data BEFORE waitUntilExit to avoid deadlock
                // when output exceeds pipe buffer (64KB)
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                process.waitUntilExit()
                timeoutTask.cancel()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let output = stdout.isEmpty ? stderr : (stderr.isEmpty ? stdout : stdout + "\n" + stderr)
                let trimmed = String(output.prefix(Self.maxOutputSize))
                let isError = process.terminationStatus != 0

                let statusText = isError ? "실패 (exit \(process.terminationStatus))" : "성공"
                let displayOutput = trimmed.isEmpty ? "(출력 없음)" : trimmed

                continuation.resume(returning: ToolResult(
                    toolCallId: "",
                    content: "[\(statusText)]\n\(displayOutput)",
                    isError: isError
                ))
            }
        }
    }
}
