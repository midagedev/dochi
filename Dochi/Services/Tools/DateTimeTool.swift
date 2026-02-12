import Foundation

@MainActor
final class DateTimeTool: BuiltInToolProtocol {
    let name = "datetime"
    let category: ToolCategory = .safe
    let description = "현재 날짜/시간 조회, 날짜 계산, 타임존 변환을 수행합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["now", "convert", "diff", "add"],
                    "description": "now: 현재 시각, convert: 타임존 변환, diff: 두 날짜 차이, add: 날짜에 기간 더하기",
                ],
                "timezone": ["type": "string", "description": "타임존 (예: Asia/Seoul, America/New_York, UTC). now/convert에서 사용"],
                "date": ["type": "string", "description": "ISO 8601 날짜 (예: 2025-03-15T14:30:00+09:00). convert/diff/add에서 사용"],
                "date2": ["type": "string", "description": "두 번째 날짜 (diff에서 사용)"],
                "add_days": ["type": "integer", "description": "더할 일수 (add에서 사용)"],
                "add_hours": ["type": "integer", "description": "더할 시간수 (add에서 사용)"],
                "add_minutes": ["type": "integer", "description": "더할 분수 (add에서 사용)"],
            ] as [String: Any],
            "required": ["action"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let action = arguments["action"] as? String else {
            return ToolResult(toolCallId: "", content: "action 파라미터가 필요합니다.", isError: true)
        }

        switch action {
        case "now":
            return handleNow(arguments: arguments)
        case "convert":
            return handleConvert(arguments: arguments)
        case "diff":
            return handleDiff(arguments: arguments)
        case "add":
            return handleAdd(arguments: arguments)
        default:
            return ToolResult(toolCallId: "", content: "알 수 없는 action: \(action). now/convert/diff/add 중 선택하세요.", isError: true)
        }
    }

    // MARK: - Actions

    private func handleNow(arguments: [String: Any]) -> ToolResult {
        let tzName = arguments["timezone"] as? String ?? "Asia/Seoul"
        guard let tz = TimeZone(identifier: tzName) else {
            return ToolResult(toolCallId: "", content: "알 수 없는 타임존: \(tzName)", isError: true)
        }

        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss (EEEE)"
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: "ko_KR")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = tz

        let display = formatter.string(from: now)
        let iso = isoFormatter.string(from: now)
        let offset = tz.secondsFromGMT(for: now)
        let offsetHours = offset / 3600
        let offsetMins = abs(offset % 3600) / 60
        let offsetStr = String(format: "UTC%+d:%02d", offsetHours, offsetMins)

        return ToolResult(toolCallId: "", content: """
            현재 시각 (\(tzName), \(offsetStr)):
            \(display)
            ISO: \(iso)
            """)
    }

    private func handleConvert(arguments: [String: Any]) -> ToolResult {
        guard let dateStr = arguments["date"] as? String else {
            return ToolResult(toolCallId: "", content: "date 파라미터가 필요합니다.", isError: true)
        }
        guard let date = parseDate(dateStr) else {
            return ToolResult(toolCallId: "", content: "날짜 파싱 실패: \(dateStr)", isError: true)
        }
        let tzName = arguments["timezone"] as? String ?? "UTC"
        guard let tz = TimeZone(identifier: tzName) else {
            return ToolResult(toolCallId: "", content: "알 수 없는 타임존: \(tzName)", isError: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss (EEEE)"
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: "ko_KR")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = tz

        return ToolResult(toolCallId: "", content: """
            \(dateStr) → \(tzName):
            \(formatter.string(from: date))
            ISO: \(isoFormatter.string(from: date))
            """)
    }

    private func handleDiff(arguments: [String: Any]) -> ToolResult {
        guard let dateStr1 = arguments["date"] as? String,
              let dateStr2 = arguments["date2"] as? String else {
            return ToolResult(toolCallId: "", content: "date와 date2 파라미터가 필요합니다.", isError: true)
        }
        guard let date1 = parseDate(dateStr1) else {
            return ToolResult(toolCallId: "", content: "첫 번째 날짜 파싱 실패: \(dateStr1)", isError: true)
        }
        guard let date2 = parseDate(dateStr2) else {
            return ToolResult(toolCallId: "", content: "두 번째 날짜 파싱 실패: \(dateStr2)", isError: true)
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute, .second], from: date1, to: date2)

        let totalSeconds = Int(date2.timeIntervalSince(date1))
        let totalDays = totalSeconds / 86400
        let totalHours = totalSeconds / 3600

        return ToolResult(toolCallId: "", content: """
            날짜 차이:
            \(dateStr1) → \(dateStr2)
            = \(components.day ?? 0)일 \(components.hour ?? 0)시간 \(components.minute ?? 0)분 \(components.second ?? 0)초
            (총 \(totalDays)일 / \(totalHours)시간 / \(totalSeconds)초)
            """)
    }

    private func handleAdd(arguments: [String: Any]) -> ToolResult {
        guard let dateStr = arguments["date"] as? String else {
            return ToolResult(toolCallId: "", content: "date 파라미터가 필요합니다.", isError: true)
        }
        guard let date = parseDate(dateStr) else {
            return ToolResult(toolCallId: "", content: "날짜 파싱 실패: \(dateStr)", isError: true)
        }

        let days = arguments["add_days"] as? Int ?? 0
        let hours = arguments["add_hours"] as? Int ?? 0
        let minutes = arguments["add_minutes"] as? Int ?? 0

        guard days != 0 || hours != 0 || minutes != 0 else {
            return ToolResult(toolCallId: "", content: "add_days, add_hours, add_minutes 중 하나 이상 지정해주세요.", isError: true)
        }

        var components = DateComponents()
        components.day = days
        components.hour = hours
        components.minute = minutes

        guard let result = Calendar.current.date(byAdding: components, to: date) else {
            return ToolResult(toolCallId: "", content: "날짜 계산 실패", isError: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss (EEEE)"
        formatter.locale = Locale(identifier: "ko_KR")

        let isoFormatter = ISO8601DateFormatter()

        var parts: [String] = []
        if days != 0 { parts.append("\(days)일") }
        if hours != 0 { parts.append("\(hours)시간") }
        if minutes != 0 { parts.append("\(minutes)분") }

        return ToolResult(toolCallId: "", content: """
            \(dateStr) + \(parts.joined(separator: " ")) =
            \(formatter.string(from: result))
            ISO: \(isoFormatter.string(from: result))
            """)
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }

        iso.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            df.dateFormat = fmt
            if let date = df.date(from: string) { return date }
        }
        return nil
    }
}
