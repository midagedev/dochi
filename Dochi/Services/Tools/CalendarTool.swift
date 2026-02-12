import Foundation
import os

// MARK: - List Calendar Events

@MainActor
final class ListCalendarEventsTool: BuiltInToolProtocol {
    let name = "calendar.list_events"
    let category: ToolCategory = .safe
    let description = "Apple 캘린더에서 일정을 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "days": ["type": "integer", "description": "오늘로부터 며칠간의 일정을 조회할지 (기본: 7)"],
                "calendar_name": ["type": "string", "description": "특정 캘린더 이름 (미지정 시 전체)"],
            ] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let days = arguments["days"] as? Int ?? 7
        let calendarName = arguments["calendar_name"] as? String

        let calendarFilter: String
        if let name = calendarName {
            calendarFilter = """
                set targetCalendars to {calendar "\(CreateReminderTool.escapeAppleScript(name))"}
                """
        } else {
            calendarFilter = "set targetCalendars to calendars"
        }

        let script = """
        tell application "Calendar"
            \(calendarFilter)
            set startDate to current date
            set time of startDate to 0
            set endDate to startDate + (\(days) * days)

            set output to ""
            repeat with cal in targetCalendars
                set calEvents to (every event of cal whose start date ≥ startDate and start date ≤ endDate)
                repeat with evt in calEvents
                    set evtStart to start date of evt
                    set evtEnd to end date of evt
                    set evtLine to (short date string of evtStart) & " " & (time string of evtStart) & " ~ " & (time string of evtEnd) & " | " & (summary of evt) & " [" & (name of cal) & "]"
                    if location of evt is not missing value and location of evt is not "" then
                        set evtLine to evtLine & " @ " & (location of evt)
                    end if
                    set output to output & evtLine & linefeed
                end repeat
            end repeat
            return output
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ToolResult(toolCallId: "", content: "향후 \(days)일 내 일정이 없습니다.")
            }
            Log.tool.info("Listed calendar events for \(days) days")
            return ToolResult(toolCallId: "", content: "캘린더 일정 (향후 \(days)일):\n\(trimmed)")
        case .failure(let error):
            Log.tool.error("Failed to list calendar events: \(error.message)")
            return ToolResult(toolCallId: "", content: "캘린더 조회 실패: \(error.message). 캘린더 앱 접근 권한을 확인해주세요.", isError: true)
        }
    }
}

// MARK: - Create Calendar Event

@MainActor
final class CreateCalendarEventTool: BuiltInToolProtocol {
    let name = "calendar.create_event"
    let category: ToolCategory = .sensitive
    let description = "Apple 캘린더에 새 일정을 생성합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "일정 제목"],
                "start_date": ["type": "string", "description": "시작 시간 (ISO 8601, 예: 2025-03-15T14:00:00)"],
                "end_date": ["type": "string", "description": "종료 시간 (ISO 8601)"],
                "duration_minutes": ["type": "integer", "description": "일정 길이 (분). end_date 미지정 시 사용 (기본: 60)"],
                "location": ["type": "string", "description": "장소"],
                "notes": ["type": "string", "description": "메모"],
                "calendar_name": ["type": "string", "description": "캘린더 이름 (기본: 기본 캘린더)"],
                "all_day": ["type": "boolean", "description": "종일 일정 여부 (기본: false)"],
            ] as [String: Any],
            "required": ["title", "start_date"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            return ToolResult(toolCallId: "", content: "title 파라미터가 필요합니다.", isError: true)
        }
        guard let startDateStr = arguments["start_date"] as? String,
              let startDate = CreateReminderTool.parseDate(startDateStr) else {
            return ToolResult(toolCallId: "", content: "start_date를 파싱할 수 없습니다.", isError: true)
        }

        let allDay = arguments["all_day"] as? Bool ?? false
        let durationMinutes = arguments["duration_minutes"] as? Int ?? 60

        let endDate: Date
        if let endDateStr = arguments["end_date"] as? String,
           let parsed = CreateReminderTool.parseDate(endDateStr) {
            endDate = parsed
        } else {
            endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let calendarPart: String
        if let calName = arguments["calendar_name"] as? String {
            calendarPart = "calendar \"\(CreateReminderTool.escapeAppleScript(calName))\""
        } else {
            calendarPart = "default calendar"
        }

        var properties = "summary:\"\(CreateReminderTool.escapeAppleScript(title))\""
        properties += ", start date:date \"\(dateFormatter.string(from: startDate))\""
        properties += ", end date:date \"\(dateFormatter.string(from: endDate))\""

        if allDay {
            properties += ", allday event:true"
        }

        var postScript = ""
        if let location = arguments["location"] as? String, !location.isEmpty {
            postScript += "\nset location of newEvent to \"\(CreateReminderTool.escapeAppleScript(location))\""
        }
        if let notes = arguments["notes"] as? String, !notes.isEmpty {
            postScript += "\nset description of newEvent to \"\(CreateReminderTool.escapeAppleScript(notes))\""
        }

        let script = """
        tell application "Calendar"
            set targetCal to \(calendarPart)
            set newEvent to make new event at end of events of targetCal with properties {\(properties)}
            \(postScript)
            return "OK"
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success:
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "M/d HH:mm"
            displayFormatter.locale = Locale(identifier: "ko_KR")
            let display = displayFormatter.string(from: startDate) + " ~ " + displayFormatter.string(from: endDate)
            Log.tool.info("Created calendar event: \(title)")
            return ToolResult(toolCallId: "", content: "캘린더 일정 생성: \(title) (\(display))")
        case .failure(let error):
            Log.tool.error("Failed to create calendar event: \(error.message)")
            return ToolResult(toolCallId: "", content: "캘린더 일정 생성 실패: \(error.message)", isError: true)
        }
    }
}

// MARK: - Delete Calendar Event

@MainActor
final class DeleteCalendarEventTool: BuiltInToolProtocol {
    let name = "calendar.delete_event"
    let category: ToolCategory = .sensitive
    let description = "Apple 캘린더에서 일정을 삭제합니다."
    let isBaseline = false

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "삭제할 일정 제목"],
                "date": ["type": "string", "description": "일정 날짜 (yyyy-MM-dd). 같은 제목의 일정이 여러 개일 때 특정"],
            ] as [String: Any],
            "required": ["title"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let title = arguments["title"] as? String, !title.isEmpty else {
            return ToolResult(toolCallId: "", content: "title 파라미터가 필요합니다.", isError: true)
        }

        let dateFilter: String
        if let dateStr = arguments["date"] as? String {
            dateFilter = """
                set filterDate to date "\(CreateReminderTool.escapeAppleScript(dateStr))"
                set filterEndDate to filterDate + (1 * days)
                set matchedEvents to (every event of cal whose summary is "\(CreateReminderTool.escapeAppleScript(title))" and start date ≥ filterDate and start date < filterEndDate)
                """
        } else {
            dateFilter = """
                set matchedEvents to (every event of cal whose summary is "\(CreateReminderTool.escapeAppleScript(title))")
                """
        }

        let script = """
        tell application "Calendar"
            set found to false
            repeat with cal in calendars
                \(dateFilter)
                if (count of matchedEvents) > 0 then
                    delete item 1 of matchedEvents
                    set found to true
                    exit repeat
                end if
            end repeat
            if found then
                return "OK"
            else
                return "NOT_FOUND"
            end if
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            if output.contains("NOT_FOUND") {
                return ToolResult(toolCallId: "", content: "'\(title)' 일정을 찾을 수 없습니다.", isError: true)
            }
            Log.tool.info("Deleted calendar event: \(title)")
            return ToolResult(toolCallId: "", content: "캘린더 일정 삭제: \(title)")
        case .failure(let error):
            Log.tool.error("Failed to delete calendar event: \(error.message)")
            return ToolResult(toolCallId: "", content: "캘린더 일정 삭제 실패: \(error.message)", isError: true)
        }
    }
}
