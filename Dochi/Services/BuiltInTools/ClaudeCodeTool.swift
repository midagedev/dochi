import Foundation
import AppKit

@MainActor
final class ClaudeCodeTool: BuiltInTool {
    struct Session: Codable {
        let id: String
        let summary: String
        let messageCount: Int
        let lastActivity: String
        let cwd: String
    }

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:claude_code.list_projects",
                name: "claude_code.list_projects",
                description: "List Claude Code projects discovered under ~/.claude/projects.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:claude_code.list_sessions",
                name: "claude_code.list_sessions",
                description: "List recent sessions for a given Claude Code project.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "project": ["type": "string"],
                        "limit": ["type": "integer"],
                        "offset": ["type": "integer"]
                    ],
                    "required": ["project"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_code.open_project",
                name: "claude_code.open_project",
                description: "Open a project's directory in Finder.",
                inputSchema: [
                    "type": "object",
                    "properties": ["project": ["type": "string"]],
                    "required": ["project"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String : Any]) async throws -> MCPToolResult {
        switch name {
        case "claude_code.list_projects":
            return listProjects()
        case "claude_code.list_sessions":
            guard let project = arguments["project"] as? String, !project.isEmpty else {
                return MCPToolResult(content: "project is required", isError: true)
            }
            let limit = (arguments["limit"] as? Int) ?? 10
            let offset = (arguments["offset"] as? Int) ?? 0
            return listSessions(project: project, limit: limit, offset: offset)
        case "claude_code.open_project":
            guard let project = arguments["project"] as? String, !project.isEmpty else {
                return MCPToolResult(content: "project is required", isError: true)
            }
            return openProject(project: project)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    private var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    private func listProjects() -> MCPToolResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsRoot.path) else {
            return MCPToolResult(content: "No projects found (~/.claude/projects not present)", isError: false)
        }
        do {
            let names = try fm.contentsOfDirectory(atPath: projectsRoot.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()
            let items: [[String: Any]] = names.map { name in
                ["name": name, "pathHint": name.replacingOccurrences(of: "-", with: "/")]
            }
            let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
            return MCPToolResult(content: String(data: data, encoding: .utf8) ?? "[]", isError: false)
        } catch {
            return MCPToolResult(content: "Failed to read projects: \(error.localizedDescription)", isError: true)
        }
    }

    private func listSessions(project: String, limit: Int, offset: Int) -> MCPToolResult {
        let dir = projectsRoot.appendingPathComponent(project, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            return MCPToolResult(content: "Project not found: \(project)", isError: true)
        }
        do {
            let files = try fm.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasSuffix(".jsonl") && !$0.hasPrefix("agent-") }
            // Sort by modification date desc
            let fileURLs = files.map { dir.appendingPathComponent($0) }
            let sorted = try fileURLs.sorted { lhs, rhs in
                let la = try fm.attributesOfItem(atPath: lhs.path)[.modificationDate] as? Date ?? .distantPast
                let ra = try fm.attributesOfItem(atPath: rhs.path)[.modificationDate] as? Date ?? .distantPast
                return la > ra
            }
            var sessionMap: [String: Session] = [:]
            var sessions: [Session] = []
            // Parse up to N files until we have enough sessions
            for url in sorted {
                try parseJSONL(fileURL: url) { entry in
                    guard let sessionId = entry["sessionId"] as? String else { return }
                    var sess = sessionMap[sessionId] ?? Session(id: sessionId, summary: "New Session", messageCount: 0, lastActivity: ISO8601DateFormatter().string(from: Date.distantPast), cwd: (entry["cwd"] as? String) ?? "")
                    if let tStr = entry["timestamp"] as? String, let t = ISO8601DateFormatter().date(from: tStr) {
                        let existing = ISO8601DateFormatter().date(from: sess.lastActivity) ?? .distantPast
                        if t > existing { sess = Session(id: sess.id, summary: sess.summary, messageCount: sess.messageCount, lastActivity: ISO8601DateFormatter().string(from: t), cwd: sess.cwd.isEmpty ? ((entry["cwd"] as? String) ?? "") : sess.cwd) }
                    }
                    if let type = entry["type"] as? String, type == "summary", let sum = entry["summary"] as? String, !sum.isEmpty {
                        sess = Session(id: sess.id, summary: sum, messageCount: sess.messageCount, lastActivity: sess.lastActivity, cwd: sess.cwd)
                    }
                    if let msg = (entry["message"] as? [String: Any]), let role = msg["role"] as? String, (role == "user" || role == "assistant") {
                        sess = Session(id: sess.id, summary: sess.summary, messageCount: sess.messageCount + 1, lastActivity: sess.lastActivity, cwd: sess.cwd)
                    }
                    sessionMap[sessionId] = sess
                }
                if sessionMap.count >= (offset + limit) * 2 { break }
            }
            sessions = Array(sessionMap.values)
                .filter { !$0.summary.hasPrefix("{ \"") }
                .sorted { ($0.lastActivity) > ($1.lastActivity) }

            let sliced = Array(sessions.dropFirst(max(0, offset)).prefix(max(0, limit)))
            let payload: [String: Any] = [
                "sessions": try JSONDecoder().decode([[String: String]].self, from: try JSONEncoder().encode(sliced.map { [
                    "id": $0.id,
                    "summary": $0.summary,
                    "lastActivity": $0.lastActivity,
                    "cwd": $0.cwd
                ] })),
                "total": sessions.count,
                "hasMore": (offset + limit) < sessions.count,
                "offset": offset,
                "limit": limit
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            return MCPToolResult(content: String(data: data, encoding: .utf8) ?? "{}", isError: false)
        } catch {
            return MCPToolResult(content: "Failed to read sessions: \(error.localizedDescription)", isError: true)
        }
    }

    private func openProject(project: String) -> MCPToolResult {
        let dir = projectsRoot.appendingPathComponent(project, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            return MCPToolResult(content: "Project not found: \(project)", isError: true)
        }
        let ok = NSWorkspace.shared.open(dir)
        return MCPToolResult(content: ok ? "Opened project in Finder" : "Failed to open project", isError: !ok)
    }

    private func parseJSONL(fileURL: URL, onEntry: ([String: Any]) -> Void) throws {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        let data = try handle.readToEnd() ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return }
        text.enumerateLines { line, _ in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return }
            if let d = t.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                onEntry(obj)
            }
        }
    }
}

