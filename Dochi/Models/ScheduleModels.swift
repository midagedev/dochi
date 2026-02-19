import Foundation

// MARK: - RepeatType

enum RepeatType: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case custom
}

// MARK: - ScheduleEntry

struct ScheduleEntry: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var name: String
    var icon: String
    var cronExpression: String
    var prompt: String
    var agentName: String
    var isEnabled: Bool
    var createdAt: Date
    var lastRunAt: Date?
    var nextRunAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "⏰",
        cronExpression: String,
        prompt: String,
        agentName: String = "도치",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.cronExpression = cronExpression
        self.prompt = prompt
        self.agentName = agentName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case cronExpression
        case prompt
        case agentName
        case isEnabled
        case createdAt
        case lastRunAt
        case nextRunAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.icon = try container.decode(String.self, forKey: .icon)
        self.cronExpression = try container.decode(String.self, forKey: .cronExpression)
        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.agentName = try container.decodeIfPresent(String.self, forKey: .agentName) ?? "도치"
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        self.nextRunAt = try container.decodeIfPresent(Date.self, forKey: .nextRunAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(cronExpression, forKey: .cronExpression)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(agentName, forKey: .agentName)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastRunAt, forKey: .lastRunAt)
        try container.encodeIfPresent(nextRunAt, forKey: .nextRunAt)
    }

    /// Human-readable summary of the schedule
    var repeatSummary: String {
        guard let parsed = CronExpression.parse(cronExpression) else {
            return cronExpression
        }
        return parsed.humanReadable
    }

    var targetSummary: String {
        "에이전트: \(agentName)"
    }
}

// MARK: - ScheduleTemplate

struct ScheduleTemplate: Identifiable, Sendable {
    let id: String
    let icon: String
    let name: String
    let description: String
    let cronExpression: String
    let prompt: String

    static let builtIn: [ScheduleTemplate] = [
        ScheduleTemplate(
            id: "morning-briefing",
            icon: "☀️",
            name: "아침 브리핑",
            description: "매일 09:00, 오늘 캘린더 일정과 미리알림을 요약해줘",
            cronExpression: "0 9 * * *",
            prompt: "오늘 캘린더 일정과 미리알림을 요약해줘"
        ),
        ScheduleTemplate(
            id: "weekly-report",
            icon: "📊",
            name: "주간 리포트",
            description: "매주 금요일 17:00, 이번 주 칸반 보드 진행 상황을 요약해줘",
            cronExpression: "0 17 * * 5",
            prompt: "이번 주 칸반 보드 진행 상황을 요약해줘"
        ),
        ScheduleTemplate(
            id: "memory-cleanup",
            icon: "🧹",
            name: "메모리 정리",
            description: "매주 일요일 03:00, 메모리를 정리하고 중복을 제거해줘",
            cronExpression: "0 3 * * 0",
            prompt: "메모리를 정리하고 중복을 제거해줘"
        ),
    ]
}

// MARK: - ScheduleExecutionRecord

struct ScheduleExecutionRecord: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let scheduleId: UUID
    let scheduleName: String
    let startedAt: Date
    var completedAt: Date?
    var status: ExecutionStatus
    var errorMessage: String?

    var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    enum ExecutionStatus: String, Codable, Sendable, Equatable {
        case running
        case success
        case failure
    }

    init(
        id: UUID = UUID(),
        scheduleId: UUID,
        scheduleName: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        status: ExecutionStatus = .running,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.scheduleId = scheduleId
        self.scheduleName = scheduleName
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.errorMessage = errorMessage
    }
}

// MARK: - CronExpression

/// Simplified cron parser supporting: minute hour dayOfMonth month dayOfWeek
struct CronExpression: Sendable, Equatable {
    let minute: CronField
    let hour: CronField
    let dayOfMonth: CronField
    let month: CronField
    let dayOfWeek: CronField

    enum CronField: Sendable, Equatable {
        case any
        case value(Int)
        case list([Int])

        func matches(_ value: Int) -> Bool {
            switch self {
            case .any: return true
            case .value(let v): return v == value
            case .list(let vs): return vs.contains(value)
            }
        }
    }

    /// Parse a cron expression string (5 fields: min hour dom month dow)
    static func parse(_ expression: String) -> CronExpression? {
        let parts = expression.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard parts.count == 5 else { return nil }

        guard let minute = parseField(parts[0], range: 0...59),
              let hour = parseField(parts[1], range: 0...23),
              let dom = parseField(parts[2], range: 1...31),
              let month = parseField(parts[3], range: 1...12),
              let dow = parseField(parts[4], range: 0...6) else {
            return nil
        }

        return CronExpression(
            minute: minute,
            hour: hour,
            dayOfMonth: dom,
            month: month,
            dayOfWeek: dow
        )
    }

    private static func parseField(_ field: String, range: ClosedRange<Int>) -> CronField? {
        if field == "*" { return .any }

        // Comma-separated list: "1,3,5"
        if field.contains(",") {
            let values = field.components(separatedBy: ",").compactMap { Int($0) }
            guard !values.isEmpty, values.allSatisfy({ range.contains($0) }) else { return nil }
            return .list(values)
        }

        // Single value
        if let value = Int(field), range.contains(value) {
            return .value(value)
        }

        return nil
    }

    /// Calculate the next run date after a given date
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        // Start from next minute
        components.second = 0
        if let currentMinute = components.minute {
            components.minute = currentMinute + 1
        }
        guard var candidate = calendar.date(from: components) else { return nil }

        // Search up to 366 days ahead
        let maxIterations = 366 * 24 * 60
        for _ in 0..<maxIterations {
            let comps = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)
            guard let m = comps.minute, let h = comps.hour,
                  let d = comps.day, let mo = comps.month,
                  let wd = comps.weekday else {
                return nil
            }

            // weekday: Sunday=1 in Calendar, cron uses 0=Sunday
            let cronWeekday = (wd + 6) % 7  // Convert: Sun=0, Mon=1, ..., Sat=6

            if minute.matches(m) && hour.matches(h) &&
               dayOfMonth.matches(d) && month.matches(mo) &&
               dayOfWeek.matches(cronWeekday) {
                return candidate
            }

            candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate
        }

        return nil
    }

    /// Human-readable description of the cron expression
    var humanReadable: String {
        let timeStr: String
        switch (hour, minute) {
        case (.value(let h), .value(let m)):
            timeStr = String(format: "%02d:%02d", h, m)
        default:
            timeStr = "매 분"
        }

        switch dayOfWeek {
        case .any:
            switch dayOfMonth {
            case .any:
                return "매일 \(timeStr)"
            case .value(let d):
                return "매월 \(d)일 \(timeStr)"
            case .list(let ds):
                let dayList = ds.map { "\($0)일" }.joined(separator: ", ")
                return "매월 \(dayList) \(timeStr)"
            }
        case .value(let d):
            return "매주 \(weekdayName(d)) \(timeStr)"
        case .list(let ds):
            let dayList = ds.map { weekdayName($0) }.joined(separator: ", ")
            return "매주 \(dayList) \(timeStr)"
        }
    }

    private func weekdayName(_ day: Int) -> String {
        switch day {
        case 0: return "일요일"
        case 1: return "월요일"
        case 2: return "화요일"
        case 3: return "수요일"
        case 4: return "목요일"
        case 5: return "금요일"
        case 6: return "토요일"
        default: return "?"
        }
    }
}
