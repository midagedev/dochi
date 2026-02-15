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

    private let settings: AppSettings
    private weak var terminalService: TerminalService?

    init(settings: AppSettings, terminalService: TerminalService?) {
        self.settings = settings
        self.terminalService = terminalService
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
                process.waitUntilExit()
                timeoutTask.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

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
