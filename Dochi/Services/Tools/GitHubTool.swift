import Foundation
import os

// MARK: - GitHub CLI Helper

private struct GHOutput: Sendable {
    let stdout: String
    let isSuccess: Bool
    let errorMessage: String

    var trimmedOutput: String { stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
    var trimmedError: String { errorMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
}

private func runGH(args: [String], at repoPath: String) async -> GHOutput {
    await withCheckedContinuation { continuation in
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh"] + args
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

                continuation.resume(returning: GHOutput(
                    stdout: outStr,
                    isSuccess: process.terminationStatus == 0,
                    errorMessage: errStr.isEmpty ? "exit code \(process.terminationStatus)" : errStr
                ))
            } catch {
                continuation.resume(returning: GHOutput(stdout: "", isSuccess: false, errorMessage: error.localizedDescription))
            }
        }
    }
}

// MARK: - List Issues

@MainActor
final class GitHubListIssuesTool: BuiltInToolProtocol {
    let name = "github.list_issues"
    let category: ToolCategory = .safe
    let description = "GitHub 저장소의 이슈 목록을 조회합니다. (gh CLI 필요)"
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "로컬 저장소 경로"],
                "state": [
                    "type": "string",
                    "enum": ["open", "closed", "all"],
                    "description": "이슈 상태 필터 (기본: open)",
                ],
                "limit": ["type": "integer", "description": "최대 결과 수 (기본: 20)"],
                "label": ["type": "string", "description": "라벨 필터"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let path = arguments["repo_path"] as? String ?? "."
        let expandedPath = NSString(string: path).expandingTildeInPath
        let state = arguments["state"] as? String ?? "open"
        let limit = arguments["limit"] as? Int ?? 20

        var args = ["issue", "list", "--state", state, "--limit", "\(limit)"]
        if let label = arguments["label"] as? String, !label.isEmpty {
            args.append(contentsOf: ["--label", label])
        }

        let result = await runGH(args: args, at: expandedPath)
        guard result.isSuccess else {
            return ToolResult(toolCallId: "", content: "GitHub 이슈 조회 실패: \(result.trimmedError)\ngh CLI가 설치되어 있는지 확인해주세요.", isError: true)
        }

        let trimmed = result.trimmedOutput
        if trimmed.isEmpty {
            return ToolResult(toolCallId: "", content: "\(state) 상태 이슈가 없습니다.")
        }
        Log.tool.info("Listed GitHub issues")
        return ToolResult(toolCallId: "", content: "GitHub 이슈 (\(state)):\n\(trimmed)")
    }
}

// MARK: - Create Issue

@MainActor
final class GitHubCreateIssueTool: BuiltInToolProtocol {
    let name = "github.create_issue"
    let category: ToolCategory = .sensitive
    let description = "GitHub 저장소에 이슈를 생성합니다. (gh CLI 필요)"
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "로컬 저장소 경로"],
                "title": ["type": "string", "description": "이슈 제목"],
                "body": ["type": "string", "description": "이슈 본문"],
                "labels": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "라벨 목록",
                ] as [String: Any],
            ] as [String: Any],
            "required": ["title"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            return ToolResult(toolCallId: "", content: "title 파라미터가 필요합니다.", isError: true)
        }
        let path = arguments["repo_path"] as? String ?? "."
        let expandedPath = NSString(string: path).expandingTildeInPath

        var args = ["issue", "create", "--title", title]
        if let body = arguments["body"] as? String, !body.isEmpty {
            args.append(contentsOf: ["--body", body])
        }
        if let labels = arguments["labels"] as? [String], !labels.isEmpty {
            args.append(contentsOf: ["--label", labels.joined(separator: ",")])
        }

        let result = await runGH(args: args, at: expandedPath)
        guard result.isSuccess else {
            return ToolResult(toolCallId: "", content: "이슈 생성 실패: \(result.trimmedError)", isError: true)
        }

        Log.tool.info("Created GitHub issue: \(title)")
        return ToolResult(toolCallId: "", content: "이슈 생성 완료:\n\(result.trimmedOutput)")
    }
}

// MARK: - Create PR

@MainActor
final class GitHubCreatePRTool: BuiltInToolProtocol {
    let name = "github.create_pr"
    let category: ToolCategory = .sensitive
    let description = "GitHub Pull Request를 생성합니다. (gh CLI 필요)"
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "로컬 저장소 경로"],
                "title": ["type": "string", "description": "PR 제목"],
                "body": ["type": "string", "description": "PR 본문"],
                "base": ["type": "string", "description": "대상 브랜치 (기본: main)"],
                "draft": ["type": "boolean", "description": "드래프트 PR 여부 (기본: false)"],
            ] as [String: Any],
            "required": ["title"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            return ToolResult(toolCallId: "", content: "title 파라미터가 필요합니다.", isError: true)
        }
        let path = arguments["repo_path"] as? String ?? "."
        let expandedPath = NSString(string: path).expandingTildeInPath
        let draft = arguments["draft"] as? Bool ?? false

        var args = ["pr", "create", "--title", title]
        if let body = arguments["body"] as? String, !body.isEmpty {
            args.append(contentsOf: ["--body", body])
        }
        if let base = arguments["base"] as? String, !base.isEmpty {
            args.append(contentsOf: ["--base", base])
        }
        if draft {
            args.append("--draft")
        }

        let result = await runGH(args: args, at: expandedPath)
        guard result.isSuccess else {
            return ToolResult(toolCallId: "", content: "PR 생성 실패: \(result.trimmedError)", isError: true)
        }

        Log.tool.info("Created GitHub PR: \(title)")
        return ToolResult(toolCallId: "", content: "PR 생성 완료:\n\(result.trimmedOutput)")
    }
}

// MARK: - View PR / Issue

@MainActor
final class GitHubViewTool: BuiltInToolProtocol {
    let name = "github.view"
    let category: ToolCategory = .safe
    let description = "GitHub 이슈 또는 PR의 상세 내용을 조회합니다. (gh CLI 필요)"
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "repo_path": ["type": "string", "description": "로컬 저장소 경로"],
                "type": [
                    "type": "string",
                    "enum": ["issue", "pr"],
                    "description": "issue 또는 pr (기본: issue)",
                ],
                "number": ["type": "integer", "description": "이슈/PR 번호"],
            ] as [String: Any],
            "required": ["number"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let number = arguments["number"] as? Int else {
            return ToolResult(toolCallId: "", content: "number 파라미터가 필요합니다.", isError: true)
        }
        let path = arguments["repo_path"] as? String ?? "."
        let expandedPath = NSString(string: path).expandingTildeInPath
        let typeName = arguments["type"] as? String ?? "issue"

        let command = typeName == "pr" ? "pr" : "issue"
        let args = [command, "view", "\(number)"]

        let result = await runGH(args: args, at: expandedPath)
        guard result.isSuccess else {
            return ToolResult(toolCallId: "", content: "\(typeName) #\(number) 조회 실패: \(result.trimmedError)", isError: true)
        }

        let trimmed = result.trimmedOutput
        let truncated = trimmed.count > 6000 ? String(trimmed.prefix(6000)) + "\n…(잘림)" : trimmed
        Log.tool.info("Viewed GitHub \(typeName) #\(number)")
        return ToolResult(toolCallId: "", content: truncated)
    }
}
