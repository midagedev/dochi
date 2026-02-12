import Foundation

@MainActor
final class ShellCommandTool: BuiltInToolProtocol {
    let name = "shell_command"
    let category: ToolCategory = .restricted
    let description = "셸 명령을 실행합니다. 사용자 확인이 필요합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "command": ["type": "string", "description": "실행할 셸 명령"],
                "timeout": ["type": "integer", "description": "타임아웃 (초, 기본 30)"],
            ],
            "required": ["command"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let command = arguments["command"] as? String, !command.isEmpty else {
            return ToolResult(toolCallId: "", content: "command 파라미터가 필요합니다.", isError: true)
        }

        let timeout = arguments["timeout"] as? Int ?? 30

        do {
            let result = try await runShell(command: command, timeout: TimeInterval(timeout))
            let output = result.isEmpty ? "(출력 없음)" : result
            let truncated = output.count > 8000 ? String(output.prefix(8000)) + "\n…(잘림)" : output
            return ToolResult(toolCallId: "", content: "실행 결과:\n```\n\(truncated)\n```")
        } catch {
            return ToolResult(toolCallId: "", content: "명령 실행 실패: \(error.localizedDescription)", isError: true)
        }
    }

    private func runShell(command: String, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.environment = ProcessInfo.processInfo.environment

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
