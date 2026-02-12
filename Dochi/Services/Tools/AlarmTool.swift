import Foundation
import os

@MainActor
final class AlarmManager {
    static let shared = AlarmManager()

    struct Alarm: Sendable {
        let label: String
        let fireDate: Date
        let timer: DispatchSourceTimer
    }

    private var alarms: [String: Alarm] = [:]

    func add(label: String, fireDate: Date, onFire: @escaping @Sendable () -> Void) {
        cancel(label: label)

        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler {
            onFire()
            Task { @MainActor in
                AlarmManager.shared.alarms.removeValue(forKey: label)
            }
        }
        timer.resume()

        alarms[label] = Alarm(label: label, fireDate: fireDate, timer: timer)
    }

    func cancel(label: String) {
        if let existing = alarms.removeValue(forKey: label) {
            existing.timer.cancel()
        }
    }

    func list() -> [(label: String, fireDate: Date)] {
        alarms.values
            .sorted { $0.fireDate < $1.fireDate }
            .map { ($0.label, $0.fireDate) }
    }
}

@MainActor
final class SetAlarmTool: BuiltInToolProtocol {
    let name = "set_alarm"
    let category: ToolCategory = .safe
    let description = "알람을 설정합니다. fire_date 또는 delay_seconds 중 하나를 지정해야 합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "label": ["type": "string", "description": "알람 이름"],
                "fire_date": ["type": "string", "description": "알람 시각 (ISO 8601)"],
                "delay_seconds": ["type": "number", "description": "현재로부터 초 단위 지연"]
            ],
            "required": ["label"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let label = arguments["label"] as? String, !label.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: label은 필수입니다.", isError: true)
        }

        let fireDate: Date

        if let fireDateStr = arguments["fire_date"] as? String {
            guard let parsed = CreateReminderTool.parseDate(fireDateStr) else {
                return ToolResult(toolCallId: "", content: "오류: fire_date 형식을 인식할 수 없습니다. ISO 8601 형식을 사용해주세요.", isError: true)
            }
            fireDate = parsed
        } else if let delaySec = arguments["delay_seconds"] as? Double {
            guard delaySec > 0 else {
                return ToolResult(toolCallId: "", content: "오류: delay_seconds는 양수여야 합니다.", isError: true)
            }
            fireDate = Date().addingTimeInterval(delaySec)
        } else if let delaySec = arguments["delay_seconds"] as? Int {
            guard delaySec > 0 else {
                return ToolResult(toolCallId: "", content: "오류: delay_seconds는 양수여야 합니다.", isError: true)
            }
            fireDate = Date().addingTimeInterval(Double(delaySec))
        } else {
            return ToolResult(toolCallId: "", content: "오류: fire_date 또는 delay_seconds 중 하나는 필수입니다.", isError: true)
        }

        guard fireDate > Date() else {
            return ToolResult(toolCallId: "", content: "오류: 알람 시각이 이미 지났습니다.", isError: true)
        }

        AlarmManager.shared.add(label: label, fireDate: fireDate) {
            Log.tool.info("Alarm fired: \(label)")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ko_KR")

        Log.tool.info("Alarm set: \(label) at \(fireDate)")
        return ToolResult(toolCallId: "", content: "알람 '\(label)' 설정 완료. 시각: \(formatter.string(from: fireDate))")
    }
}

@MainActor
final class ListAlarmsTool: BuiltInToolProtocol {
    let name = "list_alarms"
    let category: ToolCategory = .safe
    let description = "설정된 알람 목록을 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [String: Any]()
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let alarms = AlarmManager.shared.list()
        if alarms.isEmpty {
            return ToolResult(toolCallId: "", content: "설정된 알람이 없습니다.")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ko_KR")

        let lines = alarms.map { "- \($0.label): \(formatter.string(from: $0.fireDate))" }
        Log.tool.info("Listed \(alarms.count) alarms")
        return ToolResult(toolCallId: "", content: "알람 목록:\n\(lines.joined(separator: "\n"))")
    }
}

@MainActor
final class CancelAlarmTool: BuiltInToolProtocol {
    let name = "cancel_alarm"
    let category: ToolCategory = .safe
    let description = "알람을 취소합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "label": ["type": "string", "description": "취소할 알람 이름"]
            ],
            "required": ["label"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let label = arguments["label"] as? String, !label.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: label은 필수입니다.", isError: true)
        }

        AlarmManager.shared.cancel(label: label)
        Log.tool.info("Alarm cancelled: \(label)")
        return ToolResult(toolCallId: "", content: "알람 '\(label)'을(를) 취소했습니다.")
    }
}
