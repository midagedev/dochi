import Foundation
import AppKit
import os

/// macOS 디바이스 제어 도구 (안전 가드레일 포함)
@MainActor
final class SystemControlTool: BuiltInTool {
    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:device.open_app",
                name: "device.open_app",
                description: "Open an application by bundle id or display name.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "bundle_id": ["type": "string"],
                        "name": ["type": "string"]
                    ]
                ]
            ),
            MCPToolInfo(
                id: "builtin:device.open_url",
                name: "device.open_url",
                description: "Open a URL with the default handler (http(s), mailto, file).",
                inputSchema: [
                    "type": "object",
                    "properties": ["url": ["type": "string"]],
                    "required": ["url"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:device.run_applescript",
                name: "device.run_applescript",
                description: "Run a short AppleScript with explicit confirmation.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "script": ["type": "string"],
                        "confirm": ["type": "boolean", "description": "Must be true to execute"]
                    ],
                    "required": ["script", "confirm"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:device.run_shortcut",
                name: "device.run_shortcut",
                description: "Run an Apple Shortcuts automation by name using 'shortcuts run'.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "input": ["type": "string"],
                        "timeout_seconds": ["type": "integer"]
                    ],
                    "required": ["name"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String : Any]) async throws -> MCPToolResult {
        switch name {
        case "device.open_app":
            return openApp(arguments)
        case "device.open_url":
            return openURL(arguments)
        case "device.run_applescript":
            return runAppleScript(arguments)
        case "device.run_shortcut":
            return await runShortcut(arguments)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    // MARK: - Handlers

    private func openApp(_ args: [String: Any]) -> MCPToolResult {
        let bundleId = args["bundle_id"] as? String
        let displayName = args["name"] as? String

        if let bundleId, !bundleId.isEmpty {
            var psn: ProcessSerialNumber = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
            let ok = NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleId,
                                                          options: [.default],
                                                          additionalEventParamDescriptor: nil,
                                                          launchIdentifier: nil)
            return MCPToolResult(content: ok ? "Opened app (bundle_id=\(bundleId))" : "Failed to open app (bundle_id=\(bundleId))", isError: !ok)
        }

        if let displayName, !displayName.isEmpty {
            let ok = NSWorkspace.shared.launchApplication(displayName)
            return MCPToolResult(content: ok ? "Opened app (name=\(displayName))" : "Failed to open app (name=\(displayName))", isError: !ok)
        }
        return MCPToolResult(content: "Provide 'bundle_id' or 'name'", isError: true)
    }

    private func openURL(_ args: [String: Any]) -> MCPToolResult {
        guard let urlStr = args["url"] as? String, let url = URL(string: urlStr) else {
            return MCPToolResult(content: "Valid 'url' is required", isError: true)
        }
        let ok = NSWorkspace.shared.open(url)
        return MCPToolResult(content: ok ? "Opened URL: \(urlStr)" : "Failed to open URL: \(urlStr)", isError: !ok)
    }

    private func runAppleScript(_ args: [String: Any]) -> MCPToolResult {
        guard (args["confirm"] as? Bool) == true else {
            return MCPToolResult(content: "Confirmation required: set confirm=true to execute AppleScript", isError: true)
        }
        guard let script = args["script"] as? String, !script.isEmpty else {
            return MCPToolResult(content: "'script' is required", isError: true)
        }
        // Restrict script length to reduce risk
        if script.count > 2000 {
            return MCPToolResult(content: "Script too long (>2000 chars)", isError: true)
        }
        let appleScript = NSAppleScript(source: script)
        var errorDict: NSDictionary?
        let result = appleScript?.executeAndReturnError(&errorDict)
        if let errorDict {
            return MCPToolResult(content: "AppleScript error: \(errorDict)", isError: true)
        }
        let output = result?.stringValue ?? "OK"
        return MCPToolResult(content: output, isError: false)
    }

    private func runWithTimeout(_ process: Process, seconds: Int) async -> (String, String, Int32) {
        let stdout = Pipe(); process.standardOutput = stdout
        let stderr = Pipe(); process.standardError = stderr
        do {
            try process.run()
        } catch {
            return ("", "Failed to launch: \(error.localizedDescription)", -1)
        }

        let start = Date()
        while process.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            if Date().timeIntervalSince(start) > Double(seconds) {
                process.terminate()
                break
            }
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return (String(data: outData, encoding: .utf8) ?? "", String(data: errData, encoding: .utf8) ?? "", process.terminationStatus)
    }

    private func runShortcut(_ args: [String: Any]) async -> MCPToolResult {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return MCPToolResult(content: "'name' is required", isError: true)
        }
        let input = (args["input"] as? String) ?? ""
        let timeout = (args["timeout_seconds"] as? Int) ?? 20
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        var arguments = ["run", name]
        if !input.isEmpty { arguments += ["--input", input] }
        process.arguments = arguments

        let (out, err, status) = await runWithTimeout(process, seconds: timeout)
        if status == 0 {
            return MCPToolResult(content: out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "OK" : out, isError: false)
        }
        return MCPToolResult(content: err.isEmpty ? "Shortcuts failed (exit=\(status))" : err, isError: true)
    }
}

