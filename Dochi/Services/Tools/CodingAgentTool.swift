import Foundation
import os

// MARK: - Coding Agent Helper

private struct CodingOutput: Sendable {
    let stdout: String
    let isSuccess: Bool
    let errorMessage: String

    var trimmedOutput: String { stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
    var trimmedError: String { errorMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
}

private func findCLI(_ name: String) -> String? {
    let paths = [
        "/usr/local/bin/\(name)",
        "/opt/homebrew/bin/\(name)",
        NSHomeDirectory() + "/.local/bin/\(name)",
        NSHomeDirectory() + "/.npm-global/bin/\(name)",
    ]
    for path in paths {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [name]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if let path, !path.isEmpty { return path }
    }
    return nil
}

private func runCodingCLI(executable: String, args: [String], workDir: String, timeout: TimeInterval = 300) async -> CodingOutput {
    await withCheckedContinuation { continuation in
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)
            process.environment = ProcessInfo.processInfo.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let timeoutItem = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            do {
                try process.run()
                process.waitUntilExit()
                timeoutItem.cancel()

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                continuation.resume(returning: CodingOutput(
                    stdout: outStr + (errStr.isEmpty ? "" : "\nstderr: " + errStr),
                    isSuccess: process.terminationStatus == 0,
                    errorMessage: (outStr + "\n" + errStr).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                ))
            } catch {
                timeoutItem.cancel()
                continuation.resume(returning: CodingOutput(stdout: "", isSuccess: false, errorMessage: error.localizedDescription))
            }
        }
    }
}

// MARK: - Run Coding Task

@MainActor
final class CodingRunTaskTool: BuiltInToolProtocol {
    let name = "coding.run_task"
    let category: ToolCategory = .restricted
    let description = "Claude Code 또는 Codex CLI로 코딩 작업을 실행합니다. 디렉토리에서 코드를 생성/수정/리뷰합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "task": ["type": "string", "description": "수행할 코딩 작업 설명"],
                "work_dir": ["type": "string", "description": "작업 디렉토리 경로"],
                "tool": [
                    "type": "string",
                    "enum": ["claude", "codex"],
                    "description": "사용할 CLI 도구 (기본: claude). claude = Claude Code, codex = OpenAI Codex",
                ],
                "timeout_seconds": ["type": "integer", "description": "타임아웃 (초, 기본: 300)"],
            ] as [String: Any],
            "required": ["task", "work_dir"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let task = arguments["task"] as? String, !task.isEmpty else {
            return ToolResult(toolCallId: "", content: "task 파라미터가 필요합니다.", isError: true)
        }
        guard let workDir = arguments["work_dir"] as? String, !workDir.isEmpty else {
            return ToolResult(toolCallId: "", content: "work_dir 파라미터가 필요합니다.", isError: true)
        }

        let expandedDir = NSString(string: workDir).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedDir) else {
            return ToolResult(toolCallId: "", content: "디렉토리를 찾을 수 없습니다: \(workDir)", isError: true)
        }

        let toolName = arguments["tool"] as? String ?? "claude"
        let timeout = TimeInterval(arguments["timeout_seconds"] as? Int ?? 300)

        let cliName = toolName == "codex" ? "codex" : "claude"
        guard let cliPath = findCLI(cliName) else {
            return ToolResult(toolCallId: "", content: "\(cliName) CLI를 찾을 수 없습니다. 설치 후 다시 시도해주세요.", isError: true)
        }

        Log.tool.info("Running coding task with \(cliName): \(task.prefix(100))")

        let args: [String]
        if toolName == "codex" {
            args = ["--quiet", task]
        } else {
            args = ["--print", task]
        }

        let result = await runCodingCLI(executable: cliPath, args: args, workDir: expandedDir, timeout: timeout)

        guard result.isSuccess else {
            let truncated = result.trimmedError.count > 4000 ? String(result.trimmedError.prefix(4000)) + "\n…(잘림)" : result.trimmedError
            Log.tool.error("Coding task failed")
            return ToolResult(toolCallId: "", content: "코딩 작업 실패:\n\(truncated)", isError: true)
        }

        let trimmed = result.trimmedOutput
        let truncated = trimmed.count > 8000 ? String(trimmed.prefix(8000)) + "\n…(잘림)" : trimmed
        Log.tool.info("Coding task completed")
        return ToolResult(toolCallId: "", content: "코딩 작업 완료:\n\(truncated)")
    }
}

// MARK: - Code Review

@MainActor
final class CodingReviewTool: BuiltInToolProtocol {
    let name = "coding.review"
    let category: ToolCategory = .sensitive
    let description = "현재 디렉토리의 변경사항을 코드 리뷰합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "work_dir": ["type": "string", "description": "저장소 경로"],
                "focus": ["type": "string", "description": "리뷰 초점 (예: 보안, 성능, 코드스타일)"],
            ] as [String: Any],
            "required": ["work_dir"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let workDir = arguments["work_dir"] as? String, !workDir.isEmpty else {
            return ToolResult(toolCallId: "", content: "work_dir 파라미터가 필요합니다.", isError: true)
        }

        let expandedDir = NSString(string: workDir).expandingTildeInPath
        let focus = arguments["focus"] as? String ?? "전반적인 코드 품질"

        guard let cliPath = findCLI("claude") else {
            return ToolResult(toolCallId: "", content: "claude CLI를 찾을 수 없습니다.", isError: true)
        }

        // Get diff first
        let diffResult = await runCodingCLI(
            executable: "/usr/bin/git",
            args: ["diff", "--cached", "--stat"],
            workDir: expandedDir,
            timeout: 10
        )

        let diffContext: String
        if diffResult.isSuccess && !diffResult.trimmedOutput.isEmpty {
            diffContext = diffResult.trimmedOutput
        } else {
            diffContext = "(스테이징된 변경 없음, unstaged diff 사용)"
        }

        let reviewPrompt = """
            다음 코드 변경사항을 리뷰해주세요. 초점: \(focus)

            변경사항 요약:
            \(diffContext)

            git diff를 분석하고 개선점, 버그, 보안 이슈를 찾아주세요.
            """

        let result = await runCodingCLI(
            executable: cliPath,
            args: ["--print", reviewPrompt],
            workDir: expandedDir,
            timeout: 120
        )

        guard result.isSuccess else {
            return ToolResult(toolCallId: "", content: "코드 리뷰 실패: \(String(result.trimmedError.prefix(2000)))", isError: true)
        }

        let trimmed = result.trimmedOutput
        let truncated = trimmed.count > 6000 ? String(trimmed.prefix(6000)) + "\n…(잘림)" : trimmed
        Log.tool.info("Code review completed")
        return ToolResult(toolCallId: "", content: "코드 리뷰 결과:\n\(truncated)")
    }
}
