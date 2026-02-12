import Foundation
import UserNotifications

// MARK: - Timer Manager

@MainActor
final class TimerManager {
    static let shared = TimerManager()

    struct TimerEntry: Sendable {
        let label: String
        let endDate: Date
        let durationSeconds: Int
    }

    private var timers: [String: (entry: TimerEntry, task: Task<Void, Never>)] = [:]

    var onTimerFired: (@MainActor @Sendable (String) -> Void)?

    func start(label: String, seconds: Int) {
        cancel(label: label)

        let endDate = Date().addingTimeInterval(TimeInterval(seconds))
        let entry = TimerEntry(label: label, endDate: endDate, durationSeconds: seconds)

        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.timers.removeValue(forKey: label)
            self?.onTimerFired?(label)
            Self.sendNotification(label: label)
        }

        timers[label] = (entry, task)
    }

    func cancel(label: String) {
        if let existing = timers.removeValue(forKey: label) {
            existing.task.cancel()
        }
    }

    func list() -> [TimerEntry] {
        timers.values
            .map(\.entry)
            .sorted { $0.endDate < $1.endDate }
    }

    private static func sendNotification(label: String) {
        let content = UNMutableNotificationContent()
        content.title = "타이머 완료"
        content.body = label
        content.sound = .default

        let request = UNNotificationRequest(identifier: "timer-\(label)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Set Timer

@MainActor
final class SetTimerTool: BuiltInToolProtocol {
    let name = "set_timer"
    let category: ToolCategory = .safe
    let description = "카운트다운 타이머를 설정합니다. 완료 시 알림을 보냅니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "label": ["type": "string", "description": "타이머 이름"],
                "seconds": ["type": "integer", "description": "타이머 시간 (초)"],
                "minutes": ["type": "integer", "description": "타이머 시간 (분, seconds와 함께 사용 가능)"],
            ],
            "required": ["label"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let label = arguments["label"] as? String, !label.isEmpty else {
            return ToolResult(toolCallId: "", content: "label 파라미터가 필요합니다.", isError: true)
        }

        let seconds = arguments["seconds"] as? Int ?? 0
        let minutes = arguments["minutes"] as? Int ?? 0
        let totalSeconds = seconds + (minutes * 60)

        guard totalSeconds > 0 else {
            return ToolResult(toolCallId: "", content: "seconds 또는 minutes를 지정해주세요.", isError: true)
        }

        TimerManager.shared.start(label: label, seconds: totalSeconds)

        let display = totalSeconds >= 60
            ? "\(totalSeconds / 60)분 \(totalSeconds % 60)초"
            : "\(totalSeconds)초"
        return ToolResult(toolCallId: "", content: "타이머 설정: \(label) — \(display) 후 알림")
    }
}

// MARK: - List Timers

@MainActor
final class ListTimersTool: BuiltInToolProtocol {
    let name = "list_timers"
    let category: ToolCategory = .safe
    let description = "활성 타이머 목록을 조회합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [:] as [String: Any],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        let timers = TimerManager.shared.list()
        guard !timers.isEmpty else {
            return ToolResult(toolCallId: "", content: "활성 타이머가 없습니다.")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .full

        let lines = timers.map { entry in
            let remaining = formatter.localizedString(for: entry.endDate, relativeTo: Date())
            return "- \(entry.label): \(remaining)"
        }
        return ToolResult(toolCallId: "", content: "활성 타이머:\n\(lines.joined(separator: "\n"))")
    }
}

// MARK: - Cancel Timer

@MainActor
final class CancelTimerTool: BuiltInToolProtocol {
    let name = "cancel_timer"
    let category: ToolCategory = .safe
    let description = "타이머를 취소합니다."
    let isBaseline = true

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "label": ["type": "string", "description": "취소할 타이머 이름"],
            ],
            "required": ["label"],
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let label = arguments["label"] as? String else {
            return ToolResult(toolCallId: "", content: "label 파라미터가 필요합니다.", isError: true)
        }

        TimerManager.shared.cancel(label: label)
        return ToolResult(toolCallId: "", content: "타이머 취소: \(label)")
    }
}
