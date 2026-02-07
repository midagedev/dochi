import Foundation

/// 음성 알람 도구
@MainActor
final class AlarmTool: BuiltInTool {
    struct AlarmEntry: Identifiable, Sendable {
        let id: UUID
        let label: String
        let fireDate: Date
    }

    @Published private(set) var activeAlarms: [AlarmEntry] = []
    var onAlarmFired: ((String) -> Void)?

    private var alarmTimers: [UUID: Timer] = [:]

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
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
            ),
            MCPToolInfo(
                id: "builtin:list_alarms",
                name: "list_alarms",
                description: "List all active voice alarms set in this app.",
                inputSchema: [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ),
            MCPToolInfo(
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
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
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

    // MARK: - Set Alarm

    private func setAlarm(arguments: [String: Any]) -> MCPToolResult {
        guard let label = arguments["label"] as? String, !label.isEmpty else {
            return MCPToolResult(content: "label is required", isError: true)
        }

        print("[Alarm] setAlarm called: label=\(label), args=\(arguments)")

        var fireDate: Date?

        if let delay = arguments["delay_seconds"] as? NSNumber {
            let seconds = delay.doubleValue
            if seconds > 0 {
                fireDate = Date().addingTimeInterval(seconds)
                print("[Alarm] delay_seconds=\(seconds)")
            }
        }

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
