import Foundation
import UserNotifications
import os

/// Result of a single heartbeat tick.
struct HeartbeatTickResult: Sendable {
    let timestamp: Date
    let checksPerformed: [String]
    let itemsFound: Int
    let notificationSent: Bool
    let error: String?
}

/// Heartbeat-based proactive agent service.
/// Periodically checks calendar, kanban, reminders, memory size and decides if it should
/// proactively notify the user via a macOS notification or inject a message into conversation.
@MainActor
final class HeartbeatService: Observable {
    private var heartbeatTask: Task<Void, Never>?
    private let settings: AppSettings
    private var contextService: ContextServiceProtocol?
    private var sessionContext: SessionContext?
    private var onProactiveMessage: ((String) -> Void)?
    private var notificationManager: NotificationManager?
    private var interestDiscoveryService: InterestDiscoveryServiceProtocol?
    private var externalToolManager: ExternalToolSessionManagerProtocol?
    private var resourceOptimizer: ResourceOptimizerProtocol?
    private var telegramRelay: TelegramProactiveRelayProtocol?

    // Observable state
    private(set) var lastTickDate: Date?
    private(set) var lastTickResult: HeartbeatTickResult?
    private(set) var tickHistory: [HeartbeatTickResult] = []
    private(set) var consecutiveErrors: Int = 0

    static let maxHistoryCount = 20

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Inject context dependencies for memory checks.
    func configure(contextService: ContextServiceProtocol, sessionContext: SessionContext) {
        self.contextService = contextService
        self.sessionContext = sessionContext
    }

    /// Inject NotificationManager for actionable notifications (H-3).
    func setNotificationManager(_ manager: NotificationManager) {
        self.notificationManager = manager
    }

    /// Inject InterestDiscoveryService for expiration checks (K-3).
    func setInterestDiscoveryService(_ service: InterestDiscoveryServiceProtocol) {
        self.interestDiscoveryService = service
    }

    /// Inject ExternalToolSessionManager for periodic health checks (K-4).
    func setExternalToolManager(_ manager: ExternalToolSessionManagerProtocol) {
        self.externalToolManager = manager
    }

    /// Inject ResourceOptimizerService for automatic resource task pipeline (J-5).
    func setResourceOptimizer(_ optimizer: ResourceOptimizerProtocol) {
        self.resourceOptimizer = optimizer
    }

    /// Inject TelegramProactiveRelay for Telegram notification delivery (K-6).
    func setTelegramRelay(_ relay: TelegramProactiveRelayProtocol) {
        self.telegramRelay = relay
    }

    /// Set a callback for when the heartbeat decides to proactively message the user.
    func setProactiveHandler(_ handler: @escaping (String) -> Void) {
        onProactiveMessage = handler
    }

    func start() {
        stop()
        guard settings.heartbeatEnabled else { return }

        consecutiveErrors = 0
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
            if hour >= quietStart || hour < quietEnd { return }
        } else if quietStart < quietEnd {
            if hour >= quietStart && hour < quietEnd { return }
        }

        Log.app.debug("HeartbeatService tick")

        var contextParts: [String] = []
        var checksPerformed: [String] = []
        var errorMessage: String?
        var calendarContext = ""
        var kanbanContext = ""
        var reminderContext = ""
        var memoryWarning: String?

        do {
            // 1. Calendar -- upcoming events
            if settings.heartbeatCheckCalendar {
                checksPerformed.append("calendar")
                calendarContext = await gatherCalendarContext()
                if !calendarContext.isEmpty {
                    contextParts.append("📅 다가오는 일정:\n\(calendarContext)")
                }
            }

            // 2. Kanban -- cards in progress
            if settings.heartbeatCheckKanban {
                checksPerformed.append("kanban")
                kanbanContext = gatherKanbanContext()
                if !kanbanContext.isEmpty {
                    contextParts.append("📋 칸반 진행 중:\n\(kanbanContext)")
                }
            }

            // 3. Reminders -- due soon
            if settings.heartbeatCheckReminders {
                checksPerformed.append("reminders")
                reminderContext = await gatherReminderContext()
                if !reminderContext.isEmpty {
                    contextParts.append("⏰ 마감 임박 미리알림:\n\(reminderContext)")
                }
            }

            // 4. Memory size check
            if let contextService, let sessionContext {
                checksPerformed.append("memory")
                memoryWarning = checkMemorySize(
                    contextService: contextService,
                    workspaceId: sessionContext.workspaceId
                )
                if let memoryWarning {
                    contextParts.append("💾 메모리:\n\(memoryWarning)")
                }
            }

            // 5. Interest expiration check (K-3)
            interestDiscoveryService?.checkExpirations()

            // 6. Resource auto-task pipeline (J-5)
            if settings.resourceAutoTaskEnabled, let resourceOptimizer {
                let enabledTypes = Array(Set(settings.resourceAutoTaskTypes.compactMap(AutoTaskType.init(rawValue:))))
                if !enabledTypes.isEmpty {
                    checksPerformed.append("resourceAutoTask")
                    let queuedCount = await resourceOptimizer.evaluateAndQueueAutoTasks(
                        enabledTypes: enabledTypes,
                        onlyWasteRisk: settings.resourceAutoTaskOnlyWasteRisk
                    )
                    if queuedCount > 0 {
                        Log.app.info("Heartbeat queued \(queuedCount) resource auto task(s)")
                    }
                }
            }

            consecutiveErrors = 0
        } catch {
            consecutiveErrors += 1
            errorMessage = error.localizedDescription
            Log.app.error("HeartbeatService tick error: \(error.localizedDescription)")
        }

        let notificationSent: Bool
        let itemsFound = contextParts.count

        if !contextParts.isEmpty {
            let fullContext = contextParts.joined(separator: "\n\n")
            let message = composeProactiveMessage(context: fullContext)
            if let message {
                Log.app.info("HeartbeatService: sending proactive notification")
                // Delegate to NotificationManager for category-specific notifications (H-3)
                if let notificationManager {
                    if !calendarContext.isEmpty {
                        notificationManager.sendCalendarNotification(events: calendarContext)
                    }
                    if !kanbanContext.isEmpty {
                        notificationManager.sendKanbanNotification(tasks: kanbanContext)
                    }
                    if !reminderContext.isEmpty {
                        notificationManager.sendReminderNotification(reminders: reminderContext)
                    }
                    if let memoryWarning {
                        notificationManager.sendMemoryNotification(warning: memoryWarning)
                    }
                } else {
                    // Fallback: send generic notification if NotificationManager is not set
                    sendNotification(message: message)
                }

                // Telegram relay (K-6)
                if let telegramRelay {
                    await telegramRelay.sendHeartbeatAlert(
                        calendar: calendarContext,
                        kanban: kanbanContext,
                        reminder: reminderContext,
                        memory: memoryWarning
                    )
                }

                onProactiveMessage?(message)
                notificationSent = true
            } else {
                notificationSent = false
            }
        } else {
            notificationSent = false
            Log.app.debug("HeartbeatService: no actionable context found")
        }

        // Record result
        let result = HeartbeatTickResult(
            timestamp: Date(),
            checksPerformed: checksPerformed,
            itemsFound: itemsFound,
            notificationSent: notificationSent,
            error: errorMessage
        )
        lastTickDate = result.timestamp
        lastTickResult = result
        tickHistory.append(result)
        if tickHistory.count > Self.maxHistoryCount {
            tickHistory.removeFirst(tickHistory.count - Self.maxHistoryCount)
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

    /// Check if agent memory files are getting large and suggest compression.
    private func checkMemorySize(
        contextService: ContextServiceProtocol,
        workspaceId: UUID
    ) -> String? {
        let warningThreshold = 3000 // characters
        var warnings: [String] = []

        // Check workspace memory
        if let memory = contextService.loadWorkspaceMemory(workspaceId: workspaceId),
           memory.count > warningThreshold {
            warnings.append("워크스페이스 메모리가 \(memory.count)자로 커졌습니다.")
        }

        // Check active agent memory
        let agentName = settings.activeAgentName
        if let agentMemory = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentName),
           agentMemory.count > warningThreshold {
            warnings.append("\(agentName) 에이전트 메모리가 \(agentMemory.count)자로 커졌습니다.")
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    // MARK: - Message Composition

    private func composeProactiveMessage(context: String) -> String? {
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
        if context.contains("💾") {
            parts.append("메모리 정리가 필요합니다.")
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
