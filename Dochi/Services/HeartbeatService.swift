import Foundation
import UserNotifications
import os

/// Heartbeat-based proactive agent service.
/// Periodically checks calendar, kanban, reminders and decides if it should
/// proactively notify the user via a macOS notification.
@MainActor
final class HeartbeatService {
    private var heartbeatTask: Task<Void, Never>?
    private let settings: AppSettings
    private var onProactiveMessage: ((String) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Set a callback for when the heartbeat decides to proactively message the user.
    func setProactiveHandler(_ handler: @escaping (String) -> Void) {
        onProactiveMessage = handler
    }

    func start() {
        stop()
        guard settings.heartbeatEnabled else { return }

        Log.app.info("HeartbeatService started (interval: \(self.settings.heartbeatIntervalMinutes)min)")

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                let intervalSeconds = (self?.settings.heartbeatIntervalMinutes ?? 30) * 60
                try? await Task.sleep(for: .seconds(intervalSeconds))
                guard !Task.isCancelled else { break }
                await self?.tick()
            }
        }
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        Log.app.info("HeartbeatService stopped")
    }

    func restart() {
        stop()
        start()
    }

    // MARK: - Tick

    private func tick() async {
        guard settings.heartbeatEnabled else { return }

        // Quiet hours check
        let hour = Calendar.current.component(.hour, from: Date())
        let quietStart = settings.heartbeatQuietHoursStart
        let quietEnd = settings.heartbeatQuietHoursEnd
        if quietStart > quietEnd {
            // e.g., 23~8: quiet if hour >= 23 or hour < 8
            if hour >= quietStart || hour < quietEnd { return }
        } else {
            if hour >= quietStart && hour < quietEnd { return }
        }

        Log.app.debug("HeartbeatService tick")

        var contextParts: [String] = []

        // 1. Calendar — upcoming events
        if settings.heartbeatCheckCalendar {
            let calendarContext = await gatherCalendarContext()
            if !calendarContext.isEmpty {
                contextParts.append("📅 다가오는 일정:\n\(calendarContext)")
            }
        }

        // 2. Kanban — cards in progress
        if settings.heartbeatCheckKanban {
            let kanbanContext = gatherKanbanContext()
            if !kanbanContext.isEmpty {
                contextParts.append("📋 칸반 진행 중:\n\(kanbanContext)")
            }
        }

        // 3. Reminders — due soon
        if settings.heartbeatCheckReminders {
            let reminderContext = await gatherReminderContext()
            if !reminderContext.isEmpty {
                contextParts.append("⏰ 마감 임박 미리알림:\n\(reminderContext)")
            }
        }

        guard !contextParts.isEmpty else {
            Log.app.debug("HeartbeatService: no actionable context found")
            return
        }

        let fullContext = contextParts.joined(separator: "\n\n")

        // Decide whether to notify
        let message = composeProactiveMessage(context: fullContext)
        if let message {
            Log.app.info("HeartbeatService: sending proactive notification")
            sendNotification(message: message)
            onProactiveMessage?(message)
        }
    }

    // MARK: - Context Gathering

    private func gatherCalendarContext() async -> String {
        let script = """
        tell application "Calendar"
            set now to current date
            set endTime to now + (2 * hours)
            set output to ""
            repeat with cal in calendars
                set upcomingEvents to (every event of cal whose start date ≥ now and start date ≤ endTime)
                repeat with evt in upcomingEvents
                    set output to output & (time string of start date of evt) & " " & (summary of evt) & linefeed
                end repeat
            end repeat
            return output
        end tell
        """
        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        case .failure:
            return ""
        }
    }

    private func gatherKanbanContext() -> String {
        let boards = KanbanManager.shared.listBoards()
        var lines: [String] = []
        for board in boards {
            let inProgress = board.cards.filter { $0.column.contains("진행") }
            for card in inProgress {
                lines.append("- \(card.priority.icon) \(card.title) [\(board.name)]")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func gatherReminderContext() async -> String {
        let script = """
        tell application "Reminders"
            set now to current date
            set soon to now + (2 * hours)
            set output to ""
            repeat with r in (every reminder whose completed is false)
                if due date of r is not missing value then
                    if due date of r ≥ now and due date of r ≤ soon then
                        set output to output & name of r & " (마감: " & (time string of due date of r) & ")" & linefeed
                    end if
                end if
            end repeat
            return output
        end tell
        """
        let result = await runAppleScript(script)
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        case .failure:
            return ""
        }
    }

    // MARK: - Message Composition

    private func composeProactiveMessage(context: String) -> String? {
        // Simple rule-based decision for now.
        // TODO: Replace with LLM-based decision in future.
        let lines = context.split(separator: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        let timeStr = formatter.string(from: now)

        var parts: [String] = ["[\(timeStr)] 확인할 사항이 있어요:"]

        if context.contains("📅") {
            parts.append("곧 일정이 있습니다.")
        }
        if context.contains("📋") {
            parts.append("진행 중인 칸반 작업이 있습니다.")
        }
        if context.contains("⏰") {
            parts.append("마감 임박한 미리알림이 있습니다.")
        }

        parts.append("자세한 내용은 대화를 시작해주세요.")
        return parts.joined(separator: "\n")
    }

    // MARK: - Notification

    private func sendNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "도치"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "heartbeat-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
