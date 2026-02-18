import Foundation
import os

typealias AppleScriptRunner = (_ source: String, _ arguments: [String]) async -> Result<String, AppleScriptError>

func runAppleScriptWithArguments(_ source: String, _ arguments: [String]) async -> Result<String, AppleScriptError> {
    await withCheckedContinuation { continuation in
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source] + arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus == 0 {
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    continuation.resume(returning: .success(output))
                } else {
                    let errStr = String(data: errData, encoding: .utf8) ?? "알 수 없는 오류"
                    continuation.resume(returning: .failure(AppleScriptError(message: errStr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))))
                }
            } catch {
                continuation.resume(returning: .failure(AppleScriptError(message: error.localizedDescription)))
            }
        }
    }
}

private enum CodexDesktopScripts {
    static let activate = """
    on run argv
        if (count of argv) is less than 1 then error "APP_NAME_REQUIRED"
        set appName to item 1 of argv
        tell application appName to activate
        return "OK"
    end run
    """

    static let sendPrompt = """
    on run argv
        if (count of argv) is less than 5 then error "INVALID_ARGUMENTS"

        set appName to item 1 of argv
        set promptText to item 2 of argv
        set submitNow to item 3 of argv
        set startNewChat to item 4 of argv
        set activationDelayMs to (item 5 of argv) as integer
        set activationDelaySeconds to (activationDelayMs as real) / 1000

        tell application appName to activate
        if activationDelaySeconds > 0 then
            delay activationDelaySeconds
        end if

        tell application "System Events"
            if UI elements enabled is false then
                error "ACCESSIBILITY_DISABLED"
            end if

            if startNewChat is "true" then
                keystroke "n" using {command down}
                delay 0.15
            end if
        end tell

        set the clipboard to promptText
        tell application "System Events"
            keystroke "v" using {command down}
            if submitNow is "true" then
                key code 36
            end if
        end tell

        return "OK"
    end run
    """
}

private enum CodexDesktopErrorMapper {
    static func userMessage(from error: AppleScriptError, appName: String) -> String {
        let raw = error.message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let lower = raw.lowercased()

        if raw.contains("ACCESSIBILITY_DISABLED") || lower.contains("not allowed assistive access") {
            return "Codex 앱 제어 실패: macOS 접근성 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 접근성에서 Dochi를 허용하세요."
        }
        if lower.contains("not authorized to send apple events")
            || raw.contains("(-1743)")
            || lower.contains("erraeeventnotpermitted")
        {
            return "Codex 앱 제어 실패: 자동화 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 Dochi의 '\(appName)' 제어를 허용하세요."
        }
        if lower.contains("can't get application")
            || lower.contains("can’t get application")
            || lower.contains("application isn")
        {
            return "Codex 앱 제어 실패: '\(appName)' 앱을 찾을 수 없습니다. app_name 값을 확인하세요."
        }
        return "Codex 앱 제어 실패: \(raw)"
    }
}

private func codexAppName(from arguments: [String: Any]) -> String {
    let raw = arguments["app_name"] as? String
    let trimmed = raw?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "Codex" : trimmed
}

private func codexDelayMs(from arguments: [String: Any], defaultValue: Int = 350) -> Int {
    let delay: Int
    if let value = arguments["activation_delay_ms"] as? Int {
        delay = value
    } else if let value = arguments["activation_delay_ms"] as? Double {
        delay = Int(value)
    } else {
        delay = defaultValue
    }
    return max(0, min(5_000, delay))
}

@MainActor
final class CodexDesktopActivateTool: BuiltInToolProtocol {
    let name = "codex.desktop_activate"
    let category: ToolCategory = .sensitive
    let description = "Codex 데스크톱 앱을 활성화해 전면으로 가져옵니다."
    let isBaseline = false

    private let scriptRunner: AppleScriptRunner

    init(scriptRunner: @escaping AppleScriptRunner = runAppleScriptWithArguments) {
        self.scriptRunner = scriptRunner
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "app_name": ["type": "string", "description": "대상 앱 이름 (기본: Codex)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let appName = codexAppName(from: arguments)
        let result = await scriptRunner(CodexDesktopScripts.activate, [appName])

        switch result {
        case .success:
            Log.tool.info("Codex desktop app activated: \(appName)")
            return ToolResult(toolCallId: "", content: "'\(appName)' 앱을 전면으로 활성화했습니다.")
        case .failure(let error):
            let message = CodexDesktopErrorMapper.userMessage(from: error, appName: appName)
            Log.tool.error("Codex desktop activate failed: \(message)")
            return ToolResult(toolCallId: "", content: message, isError: true)
        }
    }
}

@MainActor
final class CodexDesktopSendPromptTool: BuiltInToolProtocol {
    let name = "codex.desktop_send_prompt"
    let category: ToolCategory = .restricted
    let description = "Codex 데스크톱 앱 입력창에 프롬프트를 붙여넣고 선택적으로 전송합니다. 접근성/자동화 권한이 필요합니다."
    let isBaseline = false

    private let scriptRunner: AppleScriptRunner

    init(scriptRunner: @escaping AppleScriptRunner = runAppleScriptWithArguments) {
        self.scriptRunner = scriptRunner
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "prompt": ["type": "string", "description": "Codex 앱에 보낼 텍스트"],
                "app_name": ["type": "string", "description": "대상 앱 이름 (기본: Codex)"],
                "submit": ["type": "boolean", "description": "붙여넣기 후 Enter 전송 여부 (기본: true)"],
                "new_chat": ["type": "boolean", "description": "붙여넣기 전 Command+N으로 새 대화 열기 (기본: false)"],
                "activation_delay_ms": ["type": "integer", "description": "앱 활성화 후 대기 시간(ms, 0~5000, 기본: 350)"],
            ] as [String: Any],
            "required": ["prompt"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let prompt = arguments["prompt"] as? String,
              !prompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            return ToolResult(toolCallId: "", content: "prompt 파라미터가 필요합니다.", isError: true)
        }

        let appName = codexAppName(from: arguments)
        let submit = arguments["submit"] as? Bool ?? true
        let newChat = arguments["new_chat"] as? Bool ?? false
        let delayMs = codexDelayMs(from: arguments)

        let runnerArgs = [
            appName,
            prompt,
            submit ? "true" : "false",
            newChat ? "true" : "false",
            "\(delayMs)",
        ]

        let result = await scriptRunner(CodexDesktopScripts.sendPrompt, runnerArgs)
        switch result {
        case .success:
            Log.tool.info("Codex desktop prompt dispatched (submit: \(submit), newChat: \(newChat))")
            let action = submit ? "전송했습니다" : "붙여넣었습니다"
            return ToolResult(toolCallId: "", content: "'\(appName)' 앱에 프롬프트를 \(action).")
        case .failure(let error):
            let message = CodexDesktopErrorMapper.userMessage(from: error, appName: appName)
            Log.tool.error("Codex desktop prompt dispatch failed: \(message)")
            return ToolResult(toolCallId: "", content: message, isError: true)
        }
    }
}
