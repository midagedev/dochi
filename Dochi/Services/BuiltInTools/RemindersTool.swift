import Foundation
@preconcurrency import EventKit
import os

/// Apple 미리알림 도구
@MainActor
final class RemindersTool: BuiltInTool {
    private let eventStore = EKEventStore()
    private var accessGranted = false

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:create_reminder",
                name: "create_reminder",
                description: "Create a new Apple Reminder. Use this when the user asks to set a reminder, alarm, or timer.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "The reminder title"
                        ],
                        "due_date": [
                            "type": "string",
                            "description": "Due date in ISO 8601 format (e.g. 2026-02-07T15:00:00). Optional."
                        ],
                        "notes": [
                            "type": "string",
                            "description": "Additional notes. Optional."
                        ],
                        "list_name": [
                            "type": "string",
                            "description": "Reminder list name. Uses default list if not specified. Optional."
                        ]
                    ],
                    "required": ["title"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:list_reminders",
                name: "list_reminders",
                description: "List Apple Reminders. Returns incomplete reminders, optionally filtered by list name.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "list_name": [
                            "type": "string",
                            "description": "Filter by list name. Shows all lists if not specified. Optional."
                        ],
                        "show_completed": [
                            "type": "boolean",
                            "description": "Include completed reminders. Default: false. Optional."
                        ]
                    ],
                    "required": []
                ]
            ),
            MCPToolInfo(
                id: "builtin:complete_reminder",
                name: "complete_reminder",
                description: "Mark an Apple Reminder as completed by its title.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "The title of the reminder to complete"
                        ]
                    ],
                    "required": ["title"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
        case "create_reminder":
            return try await createReminder(arguments: arguments)
        case "list_reminders":
            return try await listReminders(arguments: arguments)
        case "complete_reminder":
            return try await completeReminder(arguments: arguments)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    // MARK: - Access

    private func ensureAccess() async throws {
        if accessGranted { return }
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else {
            Log.tool.warning("미리알림 접근 권한 거부됨")
            throw BuiltInToolError.apiError("미리알림 접근 권한이 거부되었습니다. 시스템 설정에서 권한을 허용해주세요.")
        }
        accessGranted = true
    }

    // MARK: - Helper

    private struct ReminderInfo: Sendable {
        let title: String
        let isCompleted: Bool
        let dueDate: Date?
        let listName: String?
        let calendarIdentifier: String?
    }

    private nonisolated func fetchReminderInfos(store: EKEventStore) async -> [ReminderInfo] {
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let infos = (reminders ?? []).map { r in
                    ReminderInfo(
                        title: r.title ?? "",
                        isCompleted: r.isCompleted,
                        dueDate: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        listName: r.calendar?.title,
                        calendarIdentifier: r.calendarItemExternalIdentifier
                    )
                }
                continuation.resume(returning: infos)
            }
        }
    }

    // MARK: - Create

    private func createReminder(arguments: [String: Any]) async throws -> MCPToolResult {
        try await ensureAccess()

        guard let title = arguments["title"] as? String, !title.isEmpty else {
            throw BuiltInToolError.invalidArguments("title is required")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title

        if let listName = arguments["list_name"] as? String, !listName.isEmpty {
            let calendars = eventStore.calendars(for: .reminder)
            if let calendar = calendars.first(where: { $0.title == listName }) {
                reminder.calendar = calendar
            } else {
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
            }
        } else {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }

        if let dueDateStr = arguments["due_date"] as? String, !dueDateStr.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: dueDateStr)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: dueDateStr)
            }
            if date == nil {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                df.locale = Locale(identifier: "en_US_POSIX")
                date = df.date(from: dueDateStr)
            }
            if let date {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
        }

        if let notes = arguments["notes"] as? String, !notes.isEmpty {
            reminder.notes = notes
        }

        try eventStore.save(reminder, commit: true)

        var result = "미리알림 생성 완료: \(title)"
        if let due = reminder.dueDateComponents, let year = due.year, let month = due.month, let day = due.day {
            result += " (마감: \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
            if let hour = due.hour, let minute = due.minute {
                result += " \(String(format: "%02d", hour)):\(String(format: "%02d", minute))"
            }
            result += ")"
        }
        return MCPToolResult(content: result, isError: false)
    }

    // MARK: - List

    private func listReminders(arguments: [String: Any]) async throws -> MCPToolResult {
        try await ensureAccess()

        let showCompleted = arguments["show_completed"] as? Bool ?? false
        let listName = arguments["list_name"] as? String

        var infos = await fetchReminderInfos(store: eventStore)

        if let listName, !listName.isEmpty {
            infos = infos.filter { $0.listName == listName }
        }

        let filtered = showCompleted ? infos : infos.filter { !$0.isCompleted }

        if filtered.isEmpty {
            return MCPToolResult(content: "미리알림이 없습니다.", isError: false)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        var result = "## 미리알림 (\(filtered.count)개)\n\n"
        for (index, info) in filtered.prefix(30).enumerated() {
            let status = info.isCompleted ? "[완료]" : "[ ]"
            result += "\(index + 1). \(status) \(info.title.isEmpty ? "(제목 없음)" : info.title)"
            if let date = info.dueDate {
                result += " — \(dateFormatter.string(from: date))"
            }
            if let list = info.listName {
                result += " (\(list))"
            }
            result += "\n"
        }

        return MCPToolResult(content: result, isError: false)
    }

    // MARK: - Complete

    private func completeReminder(arguments: [String: Any]) async throws -> MCPToolResult {
        try await ensureAccess()

        guard let title = arguments["title"] as? String, !title.isEmpty else {
            throw BuiltInToolError.invalidArguments("title is required")
        }

        let infos = await fetchReminderInfos(store: eventStore)
        let matchingTitles = infos.filter {
            !$0.isCompleted && $0.title.localizedCaseInsensitiveContains(title)
        }

        if matchingTitles.isEmpty {
            return MCPToolResult(content: "'\(title)' 미리알림을 찾을 수 없습니다.", isError: false)
        }

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let completedCount = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            self.eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
                guard let self, let reminders else {
                    continuation.resume(returning: 0)
                    return
                }
                var count = 0
                for r in reminders {
                    if let rTitle = r.title, rTitle.localizedCaseInsensitiveContains(title) {
                        r.isCompleted = true
                        try? self.eventStore.save(r, commit: true)
                        count += 1
                    }
                }
                continuation.resume(returning: count)
            }
        }

        if completedCount == 1 {
            return MCPToolResult(content: "'\(matchingTitles[0].title)' 완료 처리했습니다.", isError: false)
        } else {
            return MCPToolResult(content: "\(completedCount)개 미리알림을 완료 처리했습니다.", isError: false)
        }
    }
}
