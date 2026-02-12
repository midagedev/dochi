import Foundation
import os

// MARK: - Git Helper

private struct CLIOutput: Sendable {
    let stdout: String
    let isSuccess: Bool
    let errorMessage: String

    var trimmedOutput: String { stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
    var trimmedError: String { errorMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
}

private func runGit(args: [String], at repoPath: String) async -> CLIOutput {
    await withCheckedContinuation { continuation in
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            process.environment = ProcessInfo.processInfo.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                continuation.resume(returning: CLIOutput(
                    stdout: outStr,
                    isSuccess: process.terminationStatus == 0,
                    errorMessage: errStr.isEmpty ? "exit code \(process.terminationStatus)" : errStr
                ))
            } catch {
                continuation.resume(returning: CLIOutput(stdout: "", isSuccess: false, errorMessage: error.localizedDescription))
            }
        }
    }
}

private func resolveRepoPath(_ arguments: [String: Any]) -> String {
    if let path = arguments["repo_path"] as? String, !path.isEmpty {
        return NSString(string: path).expandingTildeInPath
    }
    return NSHomeDirectory()
}

// MARK: - Git Status

@MainActor
final class GitStatusTool: BuiltInToolProtocol {
    let name = "git.status"
    let category: ToolCategory = .safe
    let description = "Git 저장소의 현재 상태를 조회합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "저장소 경로 (기본: 홈 디렉토리)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let path = resolveRepoPath(arguments)

        let branchResult = await runGit(args: ["branch", "--show-current"], at: path)
        let statusResult = await runGit(args: ["status", "--short"], at: path)

        guard statusResult.isSuccess else {
            return ToolResult(toolCallId: "", content: "git status 실패: \(statusResult.trimmedError)", isError: true)
        }
        guard branchResult.isSuccess else {
            return ToolResult(toolCallId: "", content: "git branch 실패: \(branchResult.trimmedError)", isError: true)
        }

        let branchName = branchResult.trimmedOutput
        let statusText = statusResult.trimmedOutput
        let statusDisplay = statusText.isEmpty ? "(변경사항 없음)" : statusText
        Log.tool.info("Git status at \(path)")
        return ToolResult(toolCallId: "", content: "브랜치: \(branchName)\n\(statusDisplay)")
    }
}

// MARK: - Git Log

@MainActor
final class GitLogTool: BuiltInToolProtocol {
    let name = "git.log"
    let category: ToolCategory = .safe
    let description = "Git 커밋 로그를 조회합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "저장소 경로"],
                "count": ["type": "integer", "description": "조회할 커밋 수 (기본: 10)"],
                "oneline": ["type": "boolean", "description": "한 줄 형식 (기본: true)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let path = resolveRepoPath(arguments)
        let count = arguments["count"] as? Int ?? 10
        let oneline = arguments["oneline"] as? Bool ?? true

        var args = ["log", "-\(count)"]
        if oneline {
            args.append("--oneline")
        } else {
            args.append(contentsOf: ["--format=%h %ad %an: %s", "--date=short"])
        }

        let result = await runGit(args: args, at: path)
        guard result.isSuccess else {
            return ToolResult(toolCallId: "", content: "git log 실패: \(result.trimmedError)", isError: true)
        }

        let trimmed = result.trimmedOutput
        if trimmed.isEmpty {
            return ToolResult(toolCallId: "", content: "커밋 로그가 없습니다.")
        }
        Log.tool.info("Git log at \(path)")
        return ToolResult(toolCallId: "", content: "최근 \(count)개 커밋:\n\(trimmed)")
    }
}

// MARK: - Git Diff

@MainActor
final class GitDiffTool: BuiltInToolProtocol {
    let name = "git.diff"
    let category: ToolCategory = .safe
    let description = "Git 변경사항(diff)을 조회합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "저장소 경로"],
                "staged": ["type": "boolean", "description": "스테이징된 변경사항만 (기본: false)"],
                "file": ["type": "string", "description": "특정 파일만 diff"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let path = resolveRepoPath(arguments)
        let staged = arguments["staged"] as? Bool ?? false

        if let file = arguments["file"] as? String, !file.isEmpty {
            var detailArgs = ["diff"]
            if staged { detailArgs.append("--cached") }
            detailArgs.append(file)
            let result = await runGit(args: detailArgs, at: path)
            guard result.isSuccess else {
                return ToolResult(toolCallId: "", content: "git diff 실패: \(result.trimmedError)", isError: true)
            }
            let trimmed = result.trimmedOutput
            if trimmed.isEmpty {
                return ToolResult(toolCallId: "", content: "\(file)에 변경사항이 없습니다.")
            }
            let truncated = trimmed.count > 6000 ? String(trimmed.prefix(6000)) + "\n…(잘림)" : trimmed
            return ToolResult(toolCallId: "", content: truncated)
        }

        var args = ["diff"]
        if staged { args.append("--cached") }
        args.append("--stat")

        let result = await runGit(args: args, at: path)
        guard result.isSuccess else {
            return ToolResult(toolCallId: "", content: "git diff 실패: \(result.trimmedError)", isError: true)
        }

        let trimmed = result.trimmedOutput
        if trimmed.isEmpty {
            return ToolResult(toolCallId: "", content: staged ? "스테이징된 변경사항이 없습니다." : "변경사항이 없습니다.")
        }
        Log.tool.info("Git diff at \(path)")
        return ToolResult(toolCallId: "", content: trimmed)
    }
}

// MARK: - Git Commit

@MainActor
final class GitCommitTool: BuiltInToolProtocol {
    let name = "git.commit"
    let category: ToolCategory = .restricted
    let description = "Git 커밋을 생성합니다. 변경사항을 스테이징하고 커밋합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "저장소 경로"],
                "message": ["type": "string", "description": "커밋 메시지"],
                "add_all": ["type": "boolean", "description": "모든 변경사항을 스테이징 (기본: false)"],
                "files": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "스테이징할 파일 목록 (add_all이 false일 때)",
                ] as [String: Any],
            ] as [String: Any],
            "required": ["message"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let message = arguments["message"] as? String, !message.isEmpty else {
            return ToolResult(toolCallId: "", content: "message 파라미터가 필요합니다.", isError: true)
        }
        let path = resolveRepoPath(arguments)
        let addAll = arguments["add_all"] as? Bool ?? false

        if addAll {
            let addResult = await runGit(args: ["add", "-A"], at: path)
            guard addResult.isSuccess else {
                return ToolResult(toolCallId: "", content: "git add 실패: \(addResult.trimmedError)", isError: true)
            }
        } else if let files = arguments["files"] as? [String], !files.isEmpty {
            let addResult = await runGit(args: ["add"] + files, at: path)
            guard addResult.isSuccess else {
                return ToolResult(toolCallId: "", content: "git add 실패: \(addResult.trimmedError)", isError: true)
            }
        }

        let commitResult = await runGit(args: ["commit", "-m", message], at: path)
        guard commitResult.isSuccess else {
            return ToolResult(toolCallId: "", content: "git commit 실패: \(commitResult.trimmedError)", isError: true)
        }

        Log.tool.info("Git commit at \(path): \(message)")
        return ToolResult(toolCallId: "", content: "커밋 완료:\n\(commitResult.trimmedOutput)")
    }
}

// MARK: - Git Branch

@MainActor
final class GitBranchTool: BuiltInToolProtocol {
    let name = "git.branch"
    let category: ToolCategory = .safe
    let description = "Git 브랜치를 조회하거나 생성/전환합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "저장소 경로"],
                "action": [
                    "type": "string",
                    "enum": ["list", "create", "switch"],
                    "description": "list (기본), create, switch",
                ],
                "name": ["type": "string", "description": "브랜치 이름 (create/switch 시 필수)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let path = resolveRepoPath(arguments)
        let action = arguments["action"] as? String ?? "list"

        switch action {
        case "create":
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                return ToolResult(toolCallId: "", content: "name 파라미터가 필요합니다.", isError: true)
            }
            let result = await runGit(args: ["checkout", "-b", name], at: path)
            guard result.isSuccess else {
                return ToolResult(toolCallId: "", content: "브랜치 생성 실패: \(result.trimmedError)", isError: true)
            }
            Log.tool.info("Created branch: \(name)")
            return ToolResult(toolCallId: "", content: "브랜치 생성 + 전환: \(name)")

        case "switch":
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                return ToolResult(toolCallId: "", content: "name 파라미터가 필요합니다.", isError: true)
            }
            let result = await runGit(args: ["checkout", name], at: path)
            guard result.isSuccess else {
                return ToolResult(toolCallId: "", content: "브랜치 전환 실패: \(result.trimmedError)", isError: true)
            }
            Log.tool.info("Switched to branch: \(name)")
            return ToolResult(toolCallId: "", content: "브랜치 전환: \(name)")

        default:
            let result = await runGit(args: ["branch", "-a", "--format=%(HEAD) %(refname:short) %(upstream:short)"], at: path)
            guard result.isSuccess else {
                return ToolResult(toolCallId: "", content: "브랜치 조회 실패: \(result.trimmedError)", isError: true)
            }
            let trimmed = result.trimmedOutput
            if trimmed.isEmpty {
                return ToolResult(toolCallId: "", content: "브랜치가 없습니다.")
            }
            return ToolResult(toolCallId: "", content: "브랜치 목록:\n\(trimmed)")
        }
    }
}
