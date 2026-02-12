import Foundation
import os

@MainActor
final class CreateReminderTool: BuiltInToolProtocol {
    let name = "create_reminder"
    let category: ToolCategory = .safe
    let description = "Apple 미리알림에 새 항목을 생성합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "미리알림 제목"],
                "due_date": ["type": "string", "description": "마감일 (ISO 8601 또는 한국어)"],
                "notes": ["type": "string", "description": "메모"],
                "list_name": ["type": "string", "description": "목록 이름 (기본: 미리알림)"]
            ],
            "required": ["title"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: title은 필수입니다.", isError: true)
        }

        let listName = arguments["list_name"] as? String ?? "미리알림"
        let notes = arguments["notes"] as? String
        let dueDate = arguments["due_date"] as? String

        var script = """
        tell application "Reminders"
            set targetList to list "\(Self.escapeAppleScript(listName))"
            set newReminder to make new reminder at end of targetList with properties {name:"\(Self.escapeAppleScript(title))"
        """

        if let notes {
            script += ", body:\"\(Self.escapeAppleScript(notes))\""
        }

        if let dueDate, let date = Self.parseDate(dueDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            let dateStr = formatter.string(from: date)
            script += """
            }
                set due date of newReminder to date "\(dateStr)"
            end tell
            """
        } else {
            script += """
            }
            end tell
            """
        }

        let result = await runAppleScript(script)
        switch result {
        case .success:
            var msg = "미리알림 '\(title)'을(를) '\(listName)' 목록에 생성했습니다."
            if let dueDate { msg += " 마감: \(dueDate)" }
            Log.tool.info("Created reminder: \(title)")
            return ToolResult(toolCallId: "", content: msg)
        case .failure(let error):
            Log.tool.error("Failed to create reminder: \(error.message)")
            return ToolResult(toolCallId: "", content: "미리알림 생성 실패: \(error.message). 미리알림 앱 접근 권한을 확인해주세요.", isError: true)
        }
    }

    static func escapeAppleScript(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func parseDate(_ str: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: str) { return d }

        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        if let d = isoBasic.date(from: str) { return d }

        // Try common formats
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]
        for fmt in formats {
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "ko_KR")
            if let d = f.date(from: str) { return d }
        }
        return nil
    }
}

@MainActor
final class ListRemindersTool: BuiltInToolProtocol {
    let name = "list_reminders"
    let category: ToolCategory = .safe
    let description = "Apple 미리알림 목록의 항목을 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "list_name": ["type": "string", "description": "목록 이름 (기본: 미리알림)"],
                "show_completed": ["type": "boolean", "description": "완료된 항목 포함 여부 (기본: false)"]
            ]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let listName = arguments["list_name"] as? String ?? "미리알림"
        let showCompleted = arguments["show_completed"] as? Bool ?? false

        let completedFilter = showCompleted
            ? "every reminder of targetList"
            : "every reminder of targetList whose completed is false"

        let script = """
        tell application "Reminders"
            set targetList to list "\(CreateReminderTool.escapeAppleScript(listName))"
            set reminderList to \(completedFilter)
            set output to ""
            repeat with r in reminderList
                set itemLine to name of r
                if due date of r is not missing value then
                    set itemLine to itemLine & " (마감: " & (due date of r as string) & ")"
                end if
                if completed of r then
                    set itemLine to "[완료] " & itemLine
                end if
                set output to output & itemLine & linefeed
            end repeat
            return output
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ToolResult(toolCallId: "", content: "'\(listName)' 목록에 미리알림이 없습니다.")
            }
            Log.tool.info("Listed reminders from: \(listName)")
            return ToolResult(toolCallId: "", content: "'\(listName)' 미리알림 목록:\n\(trimmed)")
        case .failure(let error):
            Log.tool.error("Failed to list reminders: \(error.message)")
            return ToolResult(toolCallId: "", content: "미리알림 조회 실패: \(error.message). 미리알림 앱 접근 권한을 확인해주세요.", isError: true)
        }
    }
}

@MainActor
final class CompleteReminderTool: BuiltInToolProtocol {
    let name = "complete_reminder"
    let category: ToolCategory = .safe
    let description = "Apple 미리알림 항목을 완료 처리합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "완료할 미리알림 제목"]
            ],
            "required": ["title"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: title은 필수입니다.", isError: true)
        }

        let script = """
        tell application "Reminders"
            set matchedReminders to (every reminder whose name is "\(CreateReminderTool.escapeAppleScript(title))" and completed is false)
            if (count of matchedReminders) is 0 then
                return "NOT_FOUND"
            end if
            set completed of item 1 of matchedReminders to true
            return "OK"
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            if output.contains("NOT_FOUND") {
                return ToolResult(toolCallId: "", content: "'\(title)' 미리알림을 찾을 수 없습니다.", isError: true)
            }
            Log.tool.info("Completed reminder: \(title)")
            return ToolResult(toolCallId: "", content: "미리알림 '\(title)'을(를) 완료했습니다.")
        case .failure(let error):
            Log.tool.error("Failed to complete reminder: \(error.message)")
            return ToolResult(toolCallId: "", content: "미리알림 완료 실패: \(error.message)", isError: true)
        }
    }
}

// MARK: - AppleScript runner

struct AppleScriptError: Error {
    let message: String
}

func runAppleScript(_ source: String) async -> Result<String, AppleScriptError> {
    await withCheckedContinuation { continuation in
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]

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
