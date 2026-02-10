import Foundation
import os

@MainActor
final class ClaudeUITool: BuiltInTool {
    weak var settings: AppSettings?
    var service: ClaudeCodeUIService?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:claude_ui.configure",
                name: "claude_ui.configure",
                description: "Configure Claude Code UI integration (enable, base_url, token).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "enabled": ["type": "boolean"],
                        "base_url": ["type": "string"],
                        "token": ["type": "string"]
                    ]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.health",
                name: "claude_ui.health",
                description: "GET /health from Claude Code UI server.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.auth_status",
                name: "claude_ui.auth_status",
                description: "GET /api/auth/status from server.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.mcp_list",
                name: "claude_ui.mcp_list",
                description: "List Claude CLI MCP servers via server (CLI wrapper).",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.mcp_add_json",
                name: "claude_ui.mcp_add_json",
                description: "Add MCP server via JSON config using server CLI wrapper.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "config": ["type": "object"],
                        "scope": ["type": "string"],
                        "project_path": ["type": "string"]
                    ],
                    "required": ["name", "config"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.projects_list",
                name: "claude_ui.projects_list",
                description: "List projects from Claude Code UI API.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.sessions_list",
                name: "claude_ui.sessions_list",
                description: "List sessions for a project.",
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
                id: "builtin:claude_ui.project_rename",
                name: "claude_ui.project_rename",
                description: "Rename a project display name.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "project": ["type": "string"],
                        "display_name": ["type": "string"]
                    ],
                    "required": ["project", "display_name"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.session_delete",
                name: "claude_ui.session_delete",
                description: "Delete a session by id from a project.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "project": ["type": "string"],
                        "session_id": ["type": "string"]
                    ],
                    "required": ["project", "session_id"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.project_delete",
                name: "claude_ui.project_delete",
                description: "Delete a project (force=true by default).",
                inputSchema: [
                    "type": "object",
                    "properties": ["project": ["type": "string"], "force": ["type": "boolean"]],
                    "required": ["project"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.project_add",
                name: "claude_ui.project_add",
                description: "Add existing project path to Claude Code UI.",
                inputSchema: [
                    "type": "object",
                    "properties": ["path": ["type": "string"]],
                    "required": ["path"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.mcp_remove",
                name: "claude_ui.mcp_remove",
                description: "Remove MCP server by name (optionally scope).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "scope": ["type": "string"]
                    ],
                    "required": ["name"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.install",
                name: "claude_ui.install",
                description: "Install and/or start Claude Code UI via npm/pm2. Requires confirm=true.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "method": ["type": "string", "enum": ["npm", "npx"]],
                        "install_pm2": ["type": "boolean"],
                        "port": ["type": "integer"],
                        "confirm": ["type": "boolean"]
                    ],
                    "required": ["confirm"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.pm2",
                name: "claude_ui.pm2",
                description: "Manage pm2 process for Claude Code UI (start|stop|status).",
                inputSchema: [
                    "type": "object",
                    "properties": {
                        "action": ["type": "string", "enum": ["start", "stop", "status"]],
                        "port": ["type": "integer"]
                    },
                    "required": ["action"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String : Any]) async throws -> MCPToolResult {
        guard let settings else { return MCPToolResult(content: "Settings unavailable", isError: true) }
        switch name {
        case "claude_ui.configure":
            if let enabled = arguments["enabled"] as? Bool { settings.claudeUIEnabled = enabled }
            if let url = arguments["base_url"] as? String, !url.isEmpty { settings.claudeUIBaseURL = url }
            if let token = arguments["token"] as? String, !token.isEmpty { settings.claudeUIToken = token }
            if settings.claudeUIEnabled && service == nil { service = ClaudeCodeUIService(settings: settings) }
            return MCPToolResult(content: "Configured Claude Code UI", isError: false)

        case "claude_ui.health":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            do { return MCPToolResult(content: try await svc.health(), isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.auth_status":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            do { return MCPToolResult(content: try await svc.authStatus(), isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.mcp_list":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            do { return MCPToolResult(content: try await svc.mcpList(), isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.projects_list":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            do {
                let arr = try await svc.listProjects()
                let data = try JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted])
                return MCPToolResult(content: String(data: data, encoding: .utf8) ?? "[]", isError: false)
            } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.sessions_list":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            guard let project = arguments["project"] as? String, !project.isEmpty else { return MCPToolResult(content: "project is required", isError: true) }
            let limit = (arguments["limit"] as? Int) ?? 5
            let offset = (arguments["offset"] as? Int) ?? 0
            do {
                let obj = try await svc.listSessions(projectName: project, limit: limit, offset: offset)
                let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
                return MCPToolResult(content: String(data: data, encoding: .utf8) ?? "{}", isError: false)
            } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.project_rename":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            guard let project = arguments["project"] as? String, let display = arguments["display_name"] as? String, !project.isEmpty, !display.isEmpty else {
                return MCPToolResult(content: "project and display_name are required", isError: true)
            }
            do { try await svc.renameProject(projectName: project, displayName: display); return MCPToolResult(content: "Renamed", isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.session_delete":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            guard let project = arguments["project"] as? String, let sid = arguments["session_id"] as? String else { return MCPToolResult(content: "project and session_id are required", isError: true) }
            do { try await svc.deleteSession(projectName: project, sessionId: sid); return MCPToolResult(content: "Deleted", isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.project_delete":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            guard let project = arguments["project"] as? String else { return MCPToolResult(content: "project is required", isError: true) }
            let force = (arguments["force"] as? Bool) ?? true
            do { try await svc.deleteProject(projectName: project, force: force); return MCPToolResult(content: "Deleted", isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.project_add":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            guard let path = arguments["path"] as? String, !path.isEmpty else { return MCPToolResult(content: "path is required", isError: true) }
            do { let res = try await svc.addProject(path: path); let data = try JSONSerialization.data(withJSONObject: res, options: [.prettyPrinted]); return MCPToolResult(content: String(data: data, encoding: .utf8) ?? "{}", isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }
        case "claude_ui.mcp_add_json":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                return MCPToolResult(content: "name is required", isError: true)
            }
            guard let cfg = arguments["config"] else { return MCPToolResult(content: "config is required", isError: true) }
            let scope = arguments["scope"] as? String
            let projectPath = arguments["project_path"] as? String
            do { return MCPToolResult(content: try await svc.mcpAddJSON(name: name, jsonConfig: cfg, scope: scope, projectPath: projectPath), isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.mcp_remove":
            guard let svc = service ?? (settings.claudeUIEnabled ? ClaudeCodeUIService(settings: settings) : nil) else {
                return MCPToolResult(content: "Integration disabled", isError: true)
            }
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                return MCPToolResult(content: "name is required", isError: true)
            }
            let scope = arguments["scope"] as? String
            do { return MCPToolResult(content: try await svc.mcpRemove(name: name, scope: scope), isError: false) } catch { return MCPToolResult(content: error.localizedDescription, isError: true) }

        case "claude_ui.install":
            guard (arguments["confirm"] as? Bool) == true else {
                return MCPToolResult(content: "Confirmation required: set confirm=true", isError: true)
            }
            let method = (arguments["method"] as? String) ?? "npm"
            let installPm2 = (arguments["install_pm2"] as? Bool) ?? true
            let port = (arguments["port"] as? Int) ?? 3001
            var logs: [String] = []
            if method == "npm" {
                logs.append(runShell("npm install -g @siteboon/claude-code-ui"))
            }
            if installPm2 {
                logs.append(runShell("npm install -g pm2"))
                logs.append(runShell("pm2 start cloudcli --name 'claude-code-ui' -- --port \(port)"))
            } else if method == "npx" {
                logs.append("Launching via npx in foreground; consider pm2 for background.")
                logs.append(runShell("npx @siteboon/claude-code-ui --port \(port)"))
            }
            return MCPToolResult(content: logs.joined(separator: "\n"), isError: false)

        case "claude_ui.pm2":
            guard let action = arguments["action"] as? String else { return MCPToolResult(content: "action is required", isError: true) }
            switch action {
            case "start":
                let port = (arguments["port"] as? Int) ?? 3001
                let out = runShell("pm2 start cloudcli --name 'claude-code-ui' -- --port \(port)")
                return MCPToolResult(content: out, isError: false)
            case "stop":
                let out = runShell("pm2 delete claude-code-ui || true")
                return MCPToolResult(content: out, isError: false)
            case "status":
                let out = runShell("pm2 list || pm2 status")
                return MCPToolResult(content: out, isError: false)
            default:
                return MCPToolResult(content: "Unknown action", isError: true)
            }

        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    private func runShell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return "Failed to start: \(error.localizedDescription)" }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
