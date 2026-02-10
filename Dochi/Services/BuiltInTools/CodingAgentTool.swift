import Foundation
import AppKit

@MainActor
final class CodingAgentTool: BuiltInTool {
    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:coding.open_claude",
                name: "coding.open_claude",
                description: "Open Claude in the default browser (optionally a specific URL).",
                inputSchema: [
                    "type": "object",
                    "properties": ["url": ["type": "string"]]
                ]
            ),
            MCPToolInfo(
                id: "builtin:coding.open_ide",
                name: "coding.open_ide",
                description: "Open an IDE (vscode|xcode) optionally at a path.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "ide": ["type": "string", "enum": ["vscode", "xcode"]],
                        "path": ["type": "string"]
                    ],
                    "required": ["ide"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:coding.copy_task_context",
                name: "coding.copy_task_context",
                description: "Compose a concise task brief for Claude Code and copy to clipboard.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "task": ["type": "string"],
                        "project_path": ["type": "string"],
                        "include_git": ["type": "boolean"]
                    ],
                    "required": ["task"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String : Any]) async throws -> MCPToolResult {
        switch name {
        case "coding.open_claude":
            return openClaude(arguments)
        case "coding.open_ide":
            return openIDE(arguments)
        case "coding.copy_task_context":
            return copyTaskContext(arguments)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    // MARK: - Handlers

    private func openClaude(_ args: [String: Any]) -> MCPToolResult {
        let urlStr = (args["url"] as? String) ?? "https://claude.ai"
        guard let url = URL(string: urlStr) else { return MCPToolResult(content: "Invalid URL", isError: true) }
        let ok = NSWorkspace.shared.open(url)
        return MCPToolResult(content: ok ? "Opened Claude: \(urlStr)" : "Failed to open: \(urlStr)", isError: !ok)
    }

    private func openIDE(_ args: [String: Any]) -> MCPToolResult {
        guard let ide = args["ide"] as? String else {
            return MCPToolResult(content: "ide is required (vscode|xcode)", isError: true)
        }
        let path = (args["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var targetURL: URL? = nil
        if let path, !path.isEmpty { targetURL = URL(fileURLWithPath: path, isDirectory: true) }

        let ws = NSWorkspace.shared
        switch ide.lowercased() {
        case "vscode":
            let bundleId = "com.microsoft.VSCode"
            if let url = targetURL {
                let ok = ws.open([url], withAppBundleIdentifier: bundleId, options: [], additionalEventParamDescriptor: nil, launchIdentifiers: nil)
                return MCPToolResult(content: ok ? "Opened VS Code at \(url.path)" : "Failed to open VS Code at \(url.path)", isError: !ok)
            } else {
                let ok = ws.launchApplication(withBundleIdentifier: bundleId, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                return MCPToolResult(content: ok ? "Opened VS Code" : "Failed to open VS Code", isError: !ok)
            }
        case "xcode":
            let bundleId = "com.apple.dt.Xcode"
            if let url = targetURL {
                let ok = ws.open([url], withAppBundleIdentifier: bundleId, options: [], additionalEventParamDescriptor: nil, launchIdentifiers: nil)
                return MCPToolResult(content: ok ? "Opened Xcode at \(url.path)" : "Failed to open Xcode at \(url.path)", isError: !ok)
            } else {
                let ok = ws.launchApplication(withBundleIdentifier: bundleId, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
                return MCPToolResult(content: ok ? "Opened Xcode" : "Failed to open Xcode", isError: !ok)
            }
        default:
            return MCPToolResult(content: "Unsupported ide: \(ide)", isError: true)
        }
    }

    private func copyTaskContext(_ args: [String: Any]) -> MCPToolResult {
        guard let task = args["task"] as? String, !task.isEmpty else {
            return MCPToolResult(content: "task is required", isError: true)
        }
        let includeGit = (args["include_git"] as? Bool) ?? true
        var lines: [String] = []
        lines.append("Task:\n\(task)\n")

        if let path = args["project_path"] as? String, !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let fm = FileManager.default
            lines.append("Project: \(url.path)")
            if let items = try? fm.contentsOfDirectory(atPath: url.path) {
                let visible = items.filter { !$0.hasPrefix(".") }.prefix(40)
                if !visible.isEmpty {
                    lines.append("Top-level files (<=40):\n- " + visible.joined(separator: "\n- "))
                }
            }
            if includeGit {
                // Try to extract basic git info
                let gitDir = url.appendingPathComponent(".git", isDirectory: true)
                let headURL = gitDir.appendingPathComponent("HEAD")
                if let head = try? String(contentsOf: headURL, encoding: .utf8) {
                    lines.append("Git HEAD: \(head.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                let configURL = gitDir.appendingPathComponent("config")
                if let cfg = try? String(contentsOf: configURL, encoding: .utf8) {
                    if let originLine = cfg.split(separator: "\n").first(where: { $0.contains("url = ") }) {
                        lines.append("Git remote: \(originLine.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }

        lines.append("Please start a Claude Code session and follow the task succinctly. Prefer minimal diffs and update docs/tests as needed.")
        let joined = lines.joined(separator: "\n\n")

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)
        return MCPToolResult(content: "Copied task context to clipboard (\(joined.count) chars)", isError: false)
    }
}

