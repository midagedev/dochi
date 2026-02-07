import Foundation
@preconcurrency import EventKit

/// 내장 도구 서비스 - Tavily 웹검색, Apple 미리알림 등
@MainActor
final class BuiltInToolService: ObservableObject {
    @Published private(set) var error: String?

    private var tavilyApiKey: String = ""
    private let eventStore = EKEventStore()
    private var remindersAccessGranted = false

    var availableTools: [MCPToolInfo] {
        var tools: [MCPToolInfo] = []

        if !tavilyApiKey.isEmpty {
            tools.append(MCPToolInfo(
                id: "builtin:web_search",
                name: "web_search",
                description: "Search the web for current information. Use this when you need up-to-date information about events, facts, or topics.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The search query"
                        ]
                    ],
                    "required": ["query"]
                ]
            ))
        }

        // 미리알림 도구 (항상 사용 가능)
        tools.append(MCPToolInfo(
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
        ))

        tools.append(MCPToolInfo(
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
        ))

        tools.append(MCPToolInfo(
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
        ))

        return tools
    }

    func configure(tavilyApiKey: String) {
        self.tavilyApiKey = tavilyApiKey
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
        case "web_search":
            return try await webSearch(arguments: arguments)
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

    // MARK: - Reminders Access

    private func ensureRemindersAccess() async throws {
        if remindersAccessGranted { return }
        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else {
            throw BuiltInToolError.apiError("미리알림 접근 권한이 거부되었습니다. 시스템 설정에서 권한을 허용해주세요.")
        }
        remindersAccessGranted = true
    }

    // MARK: - Web Search (Tavily)

    private func webSearch(arguments: [String: Any]) async throws -> MCPToolResult {
        guard !tavilyApiKey.isEmpty else {
            throw BuiltInToolError.missingApiKey("Tavily")
        }

        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw BuiltInToolError.invalidArguments("query is required")
        }

        let url = URL(string: "https://api.tavily.com/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "api_key": tavilyApiKey,
            "query": query,
            "search_depth": "basic",
            "include_answer": true,
            "include_raw_content": false,
            "max_results": 5
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BuiltInToolError.apiError("Tavily API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BuiltInToolError.invalidResponse("Failed to parse Tavily response")
        }

        // 응답 포맷팅
        var resultText = ""

        // AI 요약 (있으면)
        if let answer = json["answer"] as? String, !answer.isEmpty {
            resultText += "## Summary\n\(answer)\n\n"
        }

        // 검색 결과
        if let results = json["results"] as? [[String: Any]] {
            resultText += "## Search Results\n\n"
            for (index, result) in results.prefix(5).enumerated() {
                let title = result["title"] as? String ?? "No title"
                let url = result["url"] as? String ?? ""
                let content = result["content"] as? String ?? ""

                resultText += "\(index + 1). **\(title)**\n"
                if !url.isEmpty {
                    resultText += "   URL: \(url)\n"
                }
                if !content.isEmpty {
                    // 내용 truncate
                    let truncated = content.prefix(300)
                    resultText += "   \(truncated)\(content.count > 300 ? "..." : "")\n"
                }
                resultText += "\n"
            }
        }

        if resultText.isEmpty {
            resultText = "No results found for: \(query)"
        }

        return MCPToolResult(content: resultText, isError: false)
    }

    // MARK: - Reminders Helper

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

    // MARK: - Create Reminder

    private func createReminder(arguments: [String: Any]) async throws -> MCPToolResult {
        try await ensureRemindersAccess()

        guard let title = arguments["title"] as? String, !title.isEmpty else {
            throw BuiltInToolError.invalidArguments("title is required")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title

        // 리스트 지정
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

        // 마감일
        if let dueDateStr = arguments["due_date"] as? String, !dueDateStr.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: dueDateStr)
            if date == nil {
                // fractionalSeconds 없는 형식도 시도
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: dueDateStr)
            }
            if date == nil {
                // T 포함 기본 형식 시도 (2026-02-07T15:00:00)
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
                // 마감일에 알림 추가
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
        }

        // 메모
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

    // MARK: - List Reminders

    private func listReminders(arguments: [String: Any]) async throws -> MCPToolResult {
        try await ensureRemindersAccess()

        let showCompleted = arguments["show_completed"] as? Bool ?? false
        let listName = arguments["list_name"] as? String

        var infos = await fetchReminderInfos(store: eventStore)

        // 리스트 필터
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

    // MARK: - Complete Reminder

    private func completeReminder(arguments: [String: Any]) async throws -> MCPToolResult {
        try await ensureRemindersAccess()

        guard let title = arguments["title"] as? String, !title.isEmpty else {
            throw BuiltInToolError.invalidArguments("title is required")
        }

        // 먼저 Sendable한 info로 매칭할 제목 확인
        let infos = await fetchReminderInfos(store: eventStore)
        let matchingTitles = infos.filter {
            !$0.isCompleted && $0.title.localizedCaseInsensitiveContains(title)
        }

        if matchingTitles.isEmpty {
            return MCPToolResult(content: "'\(title)' 미리알림을 찾을 수 없습니다.", isError: false)
        }

        // EventKit에서 직접 매칭하여 완료 처리
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

// MARK: - Errors

enum BuiltInToolError: LocalizedError {
    case unknownTool(String)
    case missingApiKey(String)
    case invalidArguments(String)
    case apiError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown built-in tool: \(name)"
        case .missingApiKey(let service):
            return "\(service) API key is not configured"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .apiError(let message):
            return message
        case .invalidResponse(let message):
            return message
        }
    }
}
