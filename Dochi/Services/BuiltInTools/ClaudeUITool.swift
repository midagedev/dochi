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
            // Sandbox-managed install using local prefix + launchd
            MCPToolInfo(
                id: "builtin:claude_ui.sandbox_install",
                name: "claude_ui.sandbox_install",
                description: "Install/start Claude UI in a sandbox (~Library/Application Support/Dochi/claude-ui) using launchd.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "port": ["type": "integer"],
                        "version": ["type": "string"]
                    ]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.sandbox_uninstall",
                name: "claude_ui.sandbox_uninstall",
                description: "Stop/remove launchd agent and delete sandbox files/logs.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.sandbox_status",
                name: "claude_ui.sandbox_status",
                description: "Show launchd status and /health result.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.sandbox_logs",
                name: "claude_ui.sandbox_logs",
                description: "Tail sandbox logs (out/err).",
                inputSchema: [
                    "type": "object",
                    "properties": ["lines": ["type": "integer"]]
                ]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.sandbox_upgrade",
                name: "claude_ui.sandbox_upgrade",
                description: "npm update in sandbox and restart launchd agent.",
                inputSchema: ["type": "object", "properties": [:]]
            ),
            MCPToolInfo(
                id: "builtin:claude_ui.setup",
                name: "claude_ui.setup",
                description: "One-shot install/start + register/login + configure token. Requires confirm=true.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "base_url": ["type": "string"],
                        "method": ["type": "string", "enum": ["npm", "npx"]],
                        "install_pm2": ["type": "boolean"],
                        "port": ["type": "integer"],
                        "username": ["type": "string"],
                        "password": ["type": "string"],
                        "confirm": ["type": "boolean"]
                    ],
                    "required": ["confirm", "username", "password"]
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
                    "properties": [
                        "action": ["type": "string", "enum": ["start", "stop", "status"]],
                        "port": ["type": "integer"]
                    ],
                    "required": ["action"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String : Any]) async throws -> MCPToolResult {
        guard let settings = settings else { return MCPToolResult(content: "Settings unavailable", isError: true) }
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

        case "claude_ui.setup":
            guard (arguments["confirm"] as? Bool) == true else { return MCPToolResult(content: "confirm=true is required", isError: true) }
            let baseURL = (arguments["base_url"] as? String) ?? settings.claudeUIBaseURL
            let method = (arguments["method"] as? String) ?? "npm"
            let installPm2 = (arguments["install_pm2"] as? Bool) ?? true
            let port = (arguments["port"] as? Int) ?? 3001
            guard let username = arguments["username"] as? String, !username.isEmpty, let password = arguments["password"] as? String, !password.isEmpty else {
                return MCPToolResult(content: "username and password required", isError: true)
            }
            // Configure settings
            settings.claudeUIEnabled = true
            settings.claudeUIBaseURL = baseURL
            var logs: [String] = []
            // Diagnostics
            let diag = envPrefix() + "echo PATH=$PATH; which node; node -v || true; which npm; npm -v || true; which npx || true; which cloudcli || true; which claude-code-ui || true; which pm2 || true"
            logs.append(runShell(diag))
            // Install/start with PATH fix for Homebrew
            let prefix = envPrefix()
            if method == "npm" { logs.append(runShell(prefix + "npm install -g @siteboon/claude-code-ui")) }
            if installPm2 {
                logs.append(runShell(prefix + "npm install -g pm2"))
                logs.append(runShell(prefix + "pm2 delete claude-code-ui || true"))
                logs.append(runShell(prefix + "pm2 start cloudcli --name 'claude-code-ui' -- --port \(port)"))
            } else {
                let launcher = (method == "npm") ? "claude-code-ui" : "npx @siteboon/claude-code-ui"
                // Ensure log directory using Swift
                let logDir = (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Dochi").path)
                try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
                let logFile = logDir + "/claude-ui.log"
                let cmd = prefix + "nohup " + launcher + " --port \(port) >> \"\(logFile)\" 2>&1 & echo $!"
                logs.append(runShell(cmd))
            }
            // Wait for server up
            let svc = ClaudeCodeUIService(settings: settings)
            var ok = false
            for _ in 0..<40 {
                do { _ = try await svc.health(); ok = true; break } catch { try? await Task.sleep(nanoseconds: 600_000_000) }
            }
            guard ok else { return MCPToolResult(content: (logs + ["Server did not respond to /health"]).joined(separator: "\n"), isError: true) }
            // Check auth status
            var needsSetup = false
            do {
                let status = try await svc.authStatus()
                needsSetup = status.contains("needsSetup") && status.contains("true")
            } catch {}
            do {
                let token: String = needsSetup ? try await svc.register(username: username, password: password) : try await svc.login(username: username, password: password)
                settings.claudeUIToken = token
                return MCPToolResult(content: (logs + ["Configured base URL and token", needsSetup ? "Registered new user" : "Logged in"]).joined(separator: "\n"), isError: false)
            } catch {
                return MCPToolResult(content: (logs + ["Auth failed: \(error.localizedDescription)"]).joined(separator: "\n"), isError: true)
            }

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

        case "claude_ui.sandbox_install":
            let port = (arguments["port"] as? Int) ?? 3001
            let version = (arguments["version"] as? String)
            let sandbox = sandboxDir().path
            let logs = logsDir().path
            try? FileManager.default.createDirectory(atPath: sandbox, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(atPath: logs, withIntermediateDirectories: true)
            let pkg = version == nil ? "@siteboon/claude-code-ui" : "@siteboon/claude-code-ui@\(version!)"
            var outputs: [String] = []
            outputs.append(runShell(envPrefix() + "npm install --prefix \"\(sandbox)\" \(pkg)"))
            // Write launchd plist
            let plist = launchdPlist(port: port)
            do {
                try plist.write(to: plistURL(), atomically: true, encoding: .utf8)
            } catch { return MCPToolResult(content: "Failed to write launchd plist: \(error.localizedDescription)", isError: true) }
            // Restart agent
            _ = runShell(envPrefix() + "launchctl bootout gui/$(id -u) \(launchdLabel()) || true")
            let boot = runShell(envPrefix() + "launchctl bootstrap gui/$(id -u) \"\(plistURL().path)\" && launchctl enable gui/$(id -u)/\(launchdLabel())")
            outputs.append(boot)
            // Update settings base URL
            if let s = self.settings { s.claudeUIBaseURL = "http://localhost:\(port)"; s.claudeUIEnabled = true }
            // Health check
            let svc = ClaudeCodeUIService(settings: self.settings ?? AppSettings())
            var ok = false
            for _ in 0..<40 { do { _ = try await svc.health(); ok = true; break } catch { try? await Task.sleep(nanoseconds: 600_000_000) } }
            outputs.append(ok ? "Health OK" : "Health timeout")
            return MCPToolResult(content: outputs.joined(separator: "\n"), isError: !ok)

        case "claude_ui.sandbox_uninstall":
            var outputs: [String] = []
            outputs.append(runShell(envPrefix() + "launchctl bootout gui/$(id -u) \(launchdLabel()) || true"))
            try? FileManager.default.removeItem(at: plistURL())
            try? FileManager.default.removeItem(at: sandboxDir())
            return MCPToolResult(content: (outputs + ["Removed sandbox and launchd plist"]).joined(separator: "\n"), isError: false)

        case "claude_ui.sandbox_status":
            var lines: [String] = []
            let printOut = runShell(envPrefix() + "launchctl print gui/$(id -u)/\(launchdLabel()) || true")
            lines.append(printOut)
            if let s = self.settings, s.claudeUIEnabled {
                do { let h = try await (service ?? ClaudeCodeUIService(settings: s)).health(); lines.append("Health: \(h)") } catch { lines.append("Health error: \(error.localizedDescription)") }
            }
            return MCPToolResult(content: lines.joined(separator: "\n"), isError: false)

        case "claude_ui.sandbox_logs":
            let n = (arguments["lines"] as? Int) ?? 200
            let out = tail(fileURL: logsDir().appendingPathComponent("claude-ui.out.log"), lines: n)
            let err = tail(fileURL: logsDir().appendingPathComponent("claude-ui.err.log"), lines: n)
            return MCPToolResult(content: "OUT:\n\(out)\n\nERR:\n\(err)", isError: false)

        case "claude_ui.sandbox_upgrade":
            let sandbox = sandboxDir().path
            var outputs: [String] = []
            outputs.append(runShell(envPrefix() + "npm update --prefix \"\(sandbox)\""))
            outputs.append(runShell(envPrefix() + "launchctl bootout gui/$(id -u) \(launchdLabel()) || true"))
            outputs.append(runShell(envPrefix() + "launchctl bootstrap gui/$(id -u) \"\(plistURL().path)\" && launchctl enable gui/$(id -u)/\(launchdLabel())"))
            return MCPToolResult(content: outputs.joined(separator: "\n"), isError: false)

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

    private func envPrefix() -> String {
        // Ensure Homebrew global bins and npm prefix are on PATH
        // Use a lightweight inline to avoid spawning subshells repeatedly
        return "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; "
    }

    private func sandboxDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dochi/claude-ui", isDirectory: true)
    }

    private func logsDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Dochi", isDirectory: true)
    }

    private func launchdLabel() -> String { "com.dochi.claude-ui" }

    private func plistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchdLabel()).plist")
    }

    private func launchdPlist(port: Int) -> String {
        let sandbox = sandboxDir().path
        let outLog = logsDir().appendingPathComponent("claude-ui.out.log").path
        let errLog = logsDir().appendingPathComponent("claude-ui.err.log").path
        // Use zsh -lc to ensure PATH is set correctly; wrap command in one ProgramArguments
        let cmd = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; \"\(sandbox)/node_modules/.bin/cloudcli\" --port \(port)"
        return """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>\(launchdLabel())</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>\(cmd)</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>\(outLog)</string>
  <key>StandardErrorPath</key><string>\(errLog)</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
"""
    }

    private func tail(fileURL: URL, lines: Int) -> String {
        guard let data = try? Data(contentsOf: fileURL), let text = String(data: data, encoding: .utf8) else { return "" }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        let n = max(0, parts.count - lines)
        return parts.dropFirst(n).joined(separator: "\n")
    }
}
