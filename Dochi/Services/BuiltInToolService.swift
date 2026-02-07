import Foundation
@preconcurrency import EventKit

/// 내장 도구 서비스 - Tavily 웹검색, Apple 미리알림 등
@MainActor
final class BuiltInToolService: ObservableObject {
    @Published private(set) var error: String?
    @Published private(set) var activeAlarms: [AlarmEntry] = []

    /// 알람 발동 시 호출 (message)
    var onAlarmFired: ((String) -> Void)?

    private var tavilyApiKey: String = ""
    private let eventStore = EKEventStore()
    private var remindersAccessGranted = false

    struct AlarmEntry: Identifiable, Sendable {
        let id: UUID
        let label: String
        let fireDate: Date
    }
    private var alarmTimers: [UUID: Timer] = [:]

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

        // 알람 도구 (항상 사용 가능)
        tools.append(MCPToolInfo(
            id: "builtin:set_alarm",
            name: "set_alarm",
            description: "Set a loud voice alarm. The app will speak the alarm message aloud via TTS when the time comes. Use this for timers, alarms, or time-sensitive reminders that must not be missed.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "label": [
                        "type": "string",
                        "description": "What to announce when the alarm fires (e.g. '라면 익었어요!', '회의 시간이에요!')"
                    ],
                    "fire_date": [
                        "type": "string",
                        "description": "When to fire, ISO 8601 format (e.g. 2026-02-07T15:00:00). Either fire_date or delay_seconds is required."
                    ],
                    "delay_seconds": [
                        "type": "number",
                        "description": "Seconds from now (e.g. 300 for 5 minutes). Either fire_date or delay_seconds is required."
                    ]
                ],
                "required": ["label"]
            ]
        ))

        tools.append(MCPToolInfo(
            id: "builtin:list_alarms",
            name: "list_alarms",
            description: "List all active voice alarms set in this app.",
            inputSchema: [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ))

        tools.append(MCPToolInfo(
            id: "builtin:cancel_alarm",
            name: "cancel_alarm",
            description: "Cancel an active voice alarm by its label.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "label": [
                        "type": "string",
                        "description": "The label of the alarm to cancel"
                    ]
                ],
                "required": ["label"]
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
        case "set_alarm":
            return setAlarm(arguments: arguments)
        case "list_alarms":
            return listAlarms()
        case "cancel_alarm":
            return cancelAlarm(arguments: arguments)
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
    // MARK: - Set Alarm

    private func setAlarm(arguments: [String: Any]) -> MCPToolResult {
        guard let label = arguments["label"] as? String, !label.isEmpty else {
            return MCPToolResult(content: "label is required", isError: true)
        }

        print("[Alarm] setAlarm called: label=\(label), args=\(arguments)")

        var fireDate: Date?

        // delay_seconds 우선 (NSNumber 호환)
        if let delay = arguments["delay_seconds"] as? NSNumber {
            let seconds = delay.doubleValue
            if seconds > 0 {
                fireDate = Date().addingTimeInterval(seconds)
                print("[Alarm] delay_seconds=\(seconds)")
            }
        }

        // fire_date
        if fireDate == nil, let fireDateStr = arguments["fire_date"] as? String, !fireDateStr.isEmpty {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            fireDate = iso.date(from: fireDateStr)
            if fireDate == nil {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                df.locale = Locale(identifier: "en_US_POSIX")
                fireDate = df.date(from: fireDateStr)
            }
            print("[Alarm] fire_date parsed: \(String(describing: fireDate))")
        }

        guard let fireDate, fireDate > Date() else {
            print("[Alarm] Invalid fireDate: \(String(describing: fireDate))")
            return MCPToolResult(content: "유효한 fire_date 또는 delay_seconds가 필요합니다.", isError: true)
        }

        let alarmId = UUID()
        let entry = AlarmEntry(id: alarmId, label: label, fireDate: fireDate)
        activeAlarms.append(entry)

        let interval = fireDate.timeIntervalSinceNow
        print("[Alarm] Scheduling timer: \(interval)s from now, id=\(alarmId)")

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            print("[Alarm] Timer fired! label=\(label)")
            Task { @MainActor [weak self] in
                guard let self else {
                    print("[Alarm] self is nil in timer callback")
                    return
                }
                self.activeAlarms.removeAll { $0.id == alarmId }
                self.alarmTimers.removeValue(forKey: alarmId)
                print("[Alarm] Calling onAlarmFired, handler exists: \(self.onAlarmFired != nil)")
                self.onAlarmFired?(label)
            }
        }
        alarmTimers[alarmId] = timer

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h시 m분"
        let timeStr = formatter.string(from: fireDate)

        let minutes = Int(interval / 60)
        let delayStr = minutes < 1 ? "\(Int(interval))초" : "\(minutes)분"

        return MCPToolResult(
            content: "알람 설정 완료: \"\(label)\" — \(timeStr) (\(delayStr) 후)",
            isError: false
        )
    }

    // MARK: - List Alarms

    private func listAlarms() -> MCPToolResult {
        if activeAlarms.isEmpty {
            return MCPToolResult(content: "설정된 알람이 없습니다.", isError: false)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h시 m분"

        var result = "## 활성 알람 (\(activeAlarms.count)개)\n\n"
        for (index, alarm) in activeAlarms.enumerated() {
            let remaining = Int(alarm.fireDate.timeIntervalSinceNow)
            let remainStr = remaining > 60 ? "\(remaining / 60)분 남음" : "\(max(0, remaining))초 남음"
            result += "\(index + 1). \(alarm.label) — \(formatter.string(from: alarm.fireDate)) (\(remainStr))\n"
        }
        return MCPToolResult(content: result, isError: false)
    }

    // MARK: - Cancel Alarm

    private func cancelAlarm(arguments: [String: Any]) -> MCPToolResult {
        guard let label = arguments["label"] as? String, !label.isEmpty else {
            return MCPToolResult(content: "label is required", isError: true)
        }

        let matching = activeAlarms.filter { $0.label.localizedCaseInsensitiveContains(label) }
        if matching.isEmpty {
            return MCPToolResult(content: "'\(label)' 알람을 찾을 수 없습니다.", isError: false)
        }

        for alarm in matching {
            alarmTimers[alarm.id]?.invalidate()
            alarmTimers.removeValue(forKey: alarm.id)
            activeAlarms.removeAll { $0.id == alarm.id }
        }

        return MCPToolResult(content: "\(matching.count)개 알람을 취소했습니다.", isError: false)
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
