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
    let opportunities: [TaskOpportunity]
    let gitContextSummary: String?
    let detectedChanges: [HeartbeatChangeEvent]
    let orchestrationOpportunitySummary: String?
    let sessionHistoryIndexRefreshed: Bool

    init(
        timestamp: Date,
        checksPerformed: [String],
        itemsFound: Int,
        notificationSent: Bool,
        error: String?,
        opportunities: [TaskOpportunity] = [],
        gitContextSummary: String? = nil,
        detectedChanges: [HeartbeatChangeEvent] = [],
        orchestrationOpportunitySummary: String? = nil,
        sessionHistoryIndexRefreshed: Bool = false
    ) {
        self.timestamp = timestamp
        self.checksPerformed = checksPerformed
        self.itemsFound = itemsFound
        self.notificationSent = notificationSent
        self.error = error
        self.opportunities = opportunities
        self.gitContextSummary = gitContextSummary
        self.detectedChanges = detectedChanges
        self.orchestrationOpportunitySummary = orchestrationOpportunitySummary
        self.sessionHistoryIndexRefreshed = sessionHistoryIndexRefreshed
    }
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
    private var changeJournalService: HeartbeatChangeJournalProtocol?
    private var workQueueService: WorkQueueServiceProtocol?

    // Observable state
    private(set) var lastTickDate: Date?
    private(set) var lastTickResult: HeartbeatTickResult?
    private(set) var tickHistory: [HeartbeatTickResult] = []
    private(set) var consecutiveErrors: Int = 0
    private var previousGitInsightSnapshot: [String: GitRepositoryInsight] = [:]
    private var previousCodingSessionSnapshot: [String: UnifiedCodingSession] = [:]
    private var lastSessionHistoryIndexRefreshAt: Date?
    private var changeAlertLastSentAt: [String: Date] = [:]

    static let maxHistoryCount = 20
    private static let sessionHistoryRefreshInterval: TimeInterval = 6 * 60 * 60
    private static let maxChangeAlertsPerTick = 3
    private static let maxChangeAlertDedupeEntries = 300

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

    /// Inject change journal persistence service for heartbeat change events.
    func setChangeJournalService(_ service: HeartbeatChangeJournalProtocol) {
        self.changeJournalService = service
    }

    /// Inject WorkQueue service for change-to-work-item bridge.
    func setWorkQueueService(_ service: WorkQueueServiceProtocol) {
        self.workQueueService = service
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

    #if DEBUG
    func runTickForTesting() async {
        await tick()
    }
    #endif

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
        var gitContextSummary: String?
        var gitInsights: [GitRepositoryInsight] = []
        var unifiedCodingSessions: [UnifiedCodingSession] = []
        var detectedChanges: [HeartbeatChangeEvent] = []
        var orchestrationOpportunitySummary: String?
        var sessionHistoryIndexRefreshed = false

        do {
            try Task.checkCancellation()

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

            // 5. Git context summary (repo activity + work domain). Keep it as enrichment
            // and avoid sending heartbeat notifications based on git state alone.
            if let externalToolManager {
                checksPerformed.append("git")
                let roots = await externalToolManager.discoverGitRepositoryInsights(
                    searchPaths: nil,
                    limit: 3
                )
                gitInsights = roots
                gitContextSummary = summarizeGitContext(roots)

                checksPerformed.append("codingSessions")
                unifiedCodingSessions = await externalToolManager.listUnifiedCodingSessions(limit: 80)
                checksPerformed.append("orchestration")
                orchestrationOpportunitySummary = await detectOrchestrationOpportunity(
                    manager: externalToolManager,
                    preferredRepositoryRoot: roots.first?.path
                )

                if await shouldRefreshSessionHistoryIndex(manager: externalToolManager) {
                    checksPerformed.append("sessionHistoryIndex")
                    _ = await externalToolManager.rebuildSessionHistoryIndex(limit: 400)
                    lastSessionHistoryIndexRefreshAt = Date()
                    sessionHistoryIndexRefreshed = true
                    Log.app.info("Heartbeat refreshed session history index")
                }
            }

            // 6. Interest expiration check (K-3)
            interestDiscoveryService?.checkExpirations()

            // 7. Resource auto-task pipeline (J-5)
            if settings.resourceAutoTaskEnabled, let resourceOptimizer {
                let enabledTypes = Array(Set(settings.resourceAutoTaskTypes.compactMap(AutoTaskType.init(rawValue:))))
                if !enabledTypes.isEmpty {
                    checksPerformed.append("resourceAutoTask")
                    let queuedCount = await resourceOptimizer.evaluateAndQueueAutoTasks(
                        enabledTypes: enabledTypes,
                        onlyWasteRisk: settings.resourceAutoTaskOnlyWasteRisk,
                        gitInsights: gitInsights.isEmpty ? nil : gitInsights
                    )
                    if queuedCount > 0 {
                        Log.app.info("Heartbeat queued \(queuedCount) resource auto task(s)")
                    }
                }
            }

            detectedChanges = detectChangeEvents(
                gitInsights: gitInsights,
                codingSessions: unifiedCodingSessions,
                timestamp: Date()
            )
            if !detectedChanges.isEmpty {
                changeJournalService?.append(events: detectedChanges)
                Log.app.info("HeartbeatService detected \(detectedChanges.count) change event(s)")
                enqueueDetectedChangesToWorkQueue(detectedChanges)

                let channel = NotificationChannel(rawValue: settings.heartbeatNotificationChannel) ?? .appOnly
                if channel != .off {
                    let alerts = Array(
                        selectChangeAlertsToSend(
                            from: detectedChanges,
                            now: Date()
                        ).prefix(Self.maxChangeAlertsPerTick)
                    )
                    if !alerts.isEmpty {
                        await sendHeartbeatChangeAlerts(alerts, channel: channel)
                    }
                }
            }

            consecutiveErrors = 0
        } catch is CancellationError {
            return
        } catch {
            consecutiveErrors += 1
            errorMessage = error.localizedDescription
            Log.app.error("HeartbeatService tick error: \(error.localizedDescription)")
        }

        let opportunities = mapTaskOpportunities(
            calendarContext: calendarContext,
            kanbanContext: kanbanContext,
            reminderContext: reminderContext,
            memoryWarning: memoryWarning
        )

        let notificationSent: Bool
        let itemsFound = contextParts.count

        if !contextParts.isEmpty {
            if let gitContextSummary, !gitContextSummary.isEmpty {
                contextParts.append("🧭 Git 컨텍스트:\n\(gitContextSummary)")
            }

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
            if let gitContextSummary, !gitContextSummary.isEmpty {
                Log.app.debug("HeartbeatService: git context collected, but no actionable signal")
            } else {
                Log.app.debug("HeartbeatService: no actionable context found")
            }
        }

        // Record result
        let result = HeartbeatTickResult(
            timestamp: Date(),
            checksPerformed: checksPerformed,
            itemsFound: itemsFound,
            notificationSent: notificationSent,
            error: errorMessage,
            opportunities: opportunities,
            gitContextSummary: gitContextSummary,
            detectedChanges: detectedChanges,
            orchestrationOpportunitySummary: orchestrationOpportunitySummary,
            sessionHistoryIndexRefreshed: sessionHistoryIndexRefreshed
        )
        lastTickDate = result.timestamp
        lastTickResult = result
        tickHistory.append(result)
        if tickHistory.count > Self.maxHistoryCount {
            tickHistory.removeFirst(tickHistory.count - Self.maxHistoryCount)
        }
    }

    // MARK: - Change Detection

    func detectChangeEvents(
        gitInsights: [GitRepositoryInsight],
        codingSessions: [UnifiedCodingSession],
        timestamp: Date = Date()
    ) -> [HeartbeatChangeEvent] {
        let currentGitSnapshot = Self.gitSnapshotIndex(from: gitInsights)
        let currentSessionSnapshot = Self.codingSessionSnapshotIndex(from: codingSessions)

        let gitEvents = settings.heartbeatTrackGitChanges
            ? Self.diffGitSnapshot(
                previous: previousGitInsightSnapshot,
                current: currentGitSnapshot,
                timestamp: timestamp
            )
            : []
        let sessionEvents = settings.heartbeatTrackCodingSessionChanges
            ? Self.diffCodingSessionSnapshot(
                previous: previousCodingSessionSnapshot,
                current: currentSessionSnapshot,
                timestamp: timestamp
            )
            : []

        previousGitInsightSnapshot = currentGitSnapshot
        previousCodingSessionSnapshot = currentSessionSnapshot

        return (gitEvents + sessionEvents).sorted { lhs, rhs in
            if lhs.source.rawValue != rhs.source.rawValue {
                return lhs.source.rawValue < rhs.source.rawValue
            }
            if lhs.targetId != rhs.targetId {
                return lhs.targetId < rhs.targetId
            }
            return lhs.eventType.rawValue < rhs.eventType.rawValue
        }
    }

    static func gitSnapshotIndex(from insights: [GitRepositoryInsight]) -> [String: GitRepositoryInsight] {
        var index: [String: GitRepositoryInsight] = [:]
        for insight in insights {
            let key = URL(fileURLWithPath: insight.path).standardizedFileURL.path
            index[key] = insight
        }
        return index
    }

    static func codingSessionSnapshotIndex(from sessions: [UnifiedCodingSession]) -> [String: UnifiedCodingSession] {
        var index: [String: UnifiedCodingSession] = [:]
        for session in sessions {
            index[codingSessionIdentityKey(for: session)] = session
        }
        return index
    }

    static func diffGitSnapshot(
        previous: [String: GitRepositoryInsight],
        current: [String: GitRepositoryInsight],
        timestamp: Date
    ) -> [HeartbeatChangeEvent] {
        guard !previous.isEmpty else { return [] }

        var events: [HeartbeatChangeEvent] = []

        let addedPaths = Set(current.keys).subtracting(previous.keys).sorted()
        for path in addedPaths {
            guard let currentInsight = current[path] else { continue }
            events.append(
                HeartbeatChangeEvent(
                    source: .git,
                    eventType: .gitRepositoryAdded,
                    severity: .info,
                    targetId: path,
                    title: "Git 저장소 감지",
                    detail: "\(currentInsight.name) 저장소가 하트비트 추적에 추가되었습니다.",
                    metadata: [
                        "repository": currentInsight.name,
                        "branch": currentInsight.branch,
                        "path": path,
                    ],
                    timestamp: timestamp
                )
            )
        }

        let removedPaths = Set(previous.keys).subtracting(current.keys).sorted()
        for path in removedPaths {
            guard let previousInsight = previous[path] else { continue }
            events.append(
                HeartbeatChangeEvent(
                    source: .git,
                    eventType: .gitRepositoryRemoved,
                    severity: .info,
                    targetId: path,
                    title: "Git 저장소 추적 해제",
                    detail: "\(previousInsight.name) 저장소가 현재 스캔 범위에서 사라졌습니다.",
                    metadata: [
                        "repository": previousInsight.name,
                        "path": path,
                    ],
                    timestamp: timestamp
                )
            )
        }

        let sharedPaths = Set(previous.keys).intersection(current.keys).sorted()
        for path in sharedPaths {
            guard let old = previous[path], let new = current[path] else { continue }

            if old.branch != new.branch {
                events.append(
                    HeartbeatChangeEvent(
                        source: .git,
                        eventType: .gitBranchChanged,
                        severity: .info,
                        targetId: path,
                        title: "브랜치 변경",
                        detail: "\(new.name) 브랜치가 \(old.branch) → \(new.branch) 로 변경되었습니다.",
                        metadata: [
                            "repository": new.name,
                            "oldBranch": old.branch,
                            "newBranch": new.branch,
                            "path": path,
                        ],
                        timestamp: timestamp
                    )
                )
            }

            let previousDirtyCount = max(0, old.changedFileCount) + max(0, old.untrackedFileCount)
            let currentDirtyCount = max(0, new.changedFileCount) + max(0, new.untrackedFileCount)

            if (previousDirtyCount == 0 && currentDirtyCount > 0)
                || (previousDirtyCount > 0 && currentDirtyCount == 0) {
                let becameDirty = currentDirtyCount > previousDirtyCount
                events.append(
                    HeartbeatChangeEvent(
                        source: .git,
                        eventType: .gitDirtyStateChanged,
                        severity: becameDirty ? .warning : .info,
                        targetId: path,
                        title: becameDirty ? "작업 트리 변경 감지" : "작업 트리 정리 완료",
                        detail: "\(new.name) 변경 파일 상태가 \(previousDirtyCount) → \(currentDirtyCount) 로 바뀌었습니다.",
                        metadata: [
                            "repository": new.name,
                            "previousDirty": "\(previousDirtyCount)",
                            "currentDirty": "\(currentDirtyCount)",
                            "path": path,
                        ],
                        timestamp: timestamp
                    )
                )
            }

            let dirtyDelta = currentDirtyCount - previousDirtyCount
            if dirtyDelta >= 8 {
                events.append(
                    HeartbeatChangeEvent(
                        source: .git,
                        eventType: .gitDirtySpike,
                        severity: .warning,
                        targetId: path,
                        title: "작업 변경량 급증",
                        detail: "\(new.name) 변경량이 +\(dirtyDelta) 증가했습니다.",
                        metadata: [
                            "repository": new.name,
                            "delta": "\(dirtyDelta)",
                            "currentDirty": "\(currentDirtyCount)",
                            "path": path,
                        ],
                        timestamp: timestamp
                    )
                )
            }

            let oldAhead = old.aheadCount ?? 0
            let oldBehind = old.behindCount ?? 0
            let newAhead = new.aheadCount ?? 0
            let newBehind = new.behindCount ?? 0
            if oldAhead != newAhead || oldBehind != newBehind {
                events.append(
                    HeartbeatChangeEvent(
                        source: .git,
                        eventType: .gitAheadBehindChanged,
                        severity: .info,
                        targetId: path,
                        title: "원격 동기화 상태 변경",
                        detail: "\(new.name) ahead/behind \(oldAhead)/\(oldBehind) → \(newAhead)/\(newBehind)",
                        metadata: [
                            "repository": new.name,
                            "oldAhead": "\(oldAhead)",
                            "oldBehind": "\(oldBehind)",
                            "newAhead": "\(newAhead)",
                            "newBehind": "\(newBehind)",
                            "path": path,
                        ],
                        timestamp: timestamp
                    )
                )
            }
        }

        return events
    }

    static func diffCodingSessionSnapshot(
        previous: [String: UnifiedCodingSession],
        current: [String: UnifiedCodingSession],
        timestamp: Date
    ) -> [HeartbeatChangeEvent] {
        guard !previous.isEmpty else { return [] }

        var events: [HeartbeatChangeEvent] = []

        let addedKeys = Set(current.keys).subtracting(previous.keys).sorted()
        for key in addedKeys {
            guard let session = current[key] else { continue }
            events.append(
                HeartbeatChangeEvent(
                    source: .codingSession,
                    eventType: .codingSessionStarted,
                    severity: .info,
                    targetId: key,
                    title: "코딩 세션 시작",
                    detail: "\(session.provider) 세션 \(session.nativeSessionId) 이 시작되었습니다.",
                    metadata: [
                        "provider": session.provider,
                        "sessionId": session.nativeSessionId,
                        "activityState": session.activityState.rawValue,
                        "repositoryRoot": session.repositoryRoot ?? "",
                    ],
                    timestamp: timestamp
                )
            )
        }

        let removedKeys = Set(previous.keys).subtracting(current.keys).sorted()
        for key in removedKeys {
            guard let session = previous[key] else { continue }
            let severity: HeartbeatChangeSeverity = session.activityState == .active ? .warning : .info
            events.append(
                HeartbeatChangeEvent(
                    source: .codingSession,
                    eventType: .codingSessionEnded,
                    severity: severity,
                    targetId: key,
                    title: "코딩 세션 종료",
                    detail: "\(session.provider) 세션 \(session.nativeSessionId) 이 종료되었습니다.",
                    metadata: [
                        "provider": session.provider,
                        "sessionId": session.nativeSessionId,
                        "lastActivityState": session.activityState.rawValue,
                        "repositoryRoot": session.repositoryRoot ?? "",
                    ],
                    timestamp: timestamp
                )
            )
        }

        let sharedKeys = Set(previous.keys).intersection(current.keys).sorted()
        for key in sharedKeys {
            guard let old = previous[key], let new = current[key] else { continue }

            if old.activityState != new.activityState {
                let severity: HeartbeatChangeSeverity = (new.activityState == .stale || new.activityState == .dead)
                    ? .warning
                    : .info
                events.append(
                    HeartbeatChangeEvent(
                        source: .codingSession,
                        eventType: .codingSessionActivityChanged,
                        severity: severity,
                        targetId: key,
                        title: "코딩 세션 상태 전이",
                        detail: "\(new.provider) 세션 \(new.nativeSessionId) 상태가 \(old.activityState.rawValue) → \(new.activityState.rawValue) 로 바뀌었습니다.",
                        metadata: [
                            "provider": new.provider,
                            "sessionId": new.nativeSessionId,
                            "oldActivityState": old.activityState.rawValue,
                            "newActivityState": new.activityState.rawValue,
                        ],
                        timestamp: timestamp
                    )
                )
            }

            if old.repositoryRoot != new.repositoryRoot {
                events.append(
                    HeartbeatChangeEvent(
                        source: .codingSession,
                        eventType: .codingSessionRepositoryChanged,
                        severity: .info,
                        targetId: key,
                        title: "코딩 세션 저장소 바인딩 변경",
                        detail: "세션 \(new.nativeSessionId) 저장소가 \(old.repositoryRoot ?? "없음") → \(new.repositoryRoot ?? "없음") 로 변경되었습니다.",
                        metadata: [
                            "provider": new.provider,
                            "sessionId": new.nativeSessionId,
                            "oldRepositoryRoot": old.repositoryRoot ?? "",
                            "newRepositoryRoot": new.repositoryRoot ?? "",
                        ],
                        timestamp: timestamp
                    )
                )
            }
        }

        return events
    }

    static func codingSessionIdentityKey(for session: UnifiedCodingSession) -> String {
        let runtimeId = session.runtimeSessionId ?? "-"
        return "\(session.provider.lowercased())|\(session.nativeSessionId)|\(runtimeId)|\(session.path)"
    }

    func selectChangeAlertsToSend(
        from events: [HeartbeatChangeEvent],
        now: Date = Date()
    ) -> [HeartbeatChangeEvent] {
        guard settings.heartbeatChangeAlertEnabled else { return [] }

        let cooldownMinutes = max(1, settings.heartbeatChangeAlertCooldownMinutes)
        let cooldownInterval = TimeInterval(cooldownMinutes * 60)
        var selected: [HeartbeatChangeEvent] = []

        for event in events where shouldSendChangeAlert(for: event) {
            if let lastSent = changeAlertLastSentAt[event.dedupeKey],
               now.timeIntervalSince(lastSent) < cooldownInterval {
                continue
            }
            changeAlertLastSentAt[event.dedupeKey] = now
            selected.append(event)
        }

        trimChangeAlertDedupeState()
        return selected.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return severityScore(lhs.severity) > severityScore(rhs.severity)
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    func shouldSendChangeAlert(for event: HeartbeatChangeEvent) -> Bool {
        switch event.eventType {
        case .codingSessionEnded, .gitDirtySpike:
            return true
        case .codingSessionActivityChanged:
            let nextState = event.metadata["newActivityState"]?.lowercased() ?? ""
            return nextState == CodingSessionActivityState.stale.rawValue
                || nextState == CodingSessionActivityState.dead.rawValue
        case .gitAheadBehindChanged:
            let oldAhead = numericMetadataValue(event.metadata["oldAhead"])
            let oldBehind = numericMetadataValue(event.metadata["oldBehind"])
            let newAhead = numericMetadataValue(event.metadata["newAhead"])
            let newBehind = numericMetadataValue(event.metadata["newBehind"])
            let totalDelta = abs(newAhead - oldAhead) + abs(newBehind - oldBehind)
            return totalDelta >= 4 || newAhead >= 5 || newBehind >= 5
        default:
            return false
        }
    }

    private func sendHeartbeatChangeAlerts(
        _ events: [HeartbeatChangeEvent],
        channel: NotificationChannel
    ) async {
        guard !events.isEmpty else { return }

        for event in events {
            if channel.deliversToApp {
                notificationManager?.sendHeartbeatChangeNotification(event: event)
            }
            if channel.deliversToTelegram {
                await telegramRelay?.sendHeartbeatChangeAlert(event)
            }
        }
        Log.app.info("HeartbeatService sent \(events.count) change alert(s)")
    }

    private func enqueueDetectedChangesToWorkQueue(_ events: [HeartbeatChangeEvent]) {
        guard let workQueueService else { return }

        var queuedCount = 0
        for event in events {
            let draft = WorkItemDraft(
                source: .heartbeat,
                title: event.title,
                detail: event.detail,
                repositoryRoot: workItemRepositoryRoot(for: event),
                severity: workItemSeverity(for: event.severity),
                suggestedAction: workItemSuggestedAction(for: event),
                dedupeKey: "heartbeat_change|\(event.dedupeKey)",
                dueAt: nil,
                ttl: workItemTTL(for: event.severity)
            )
            if workQueueService.enqueue(draft, now: event.timestamp) != nil {
                queuedCount += 1
            }
        }

        if queuedCount > 0 {
            Log.app.info("HeartbeatService queued \(queuedCount) work item(s)")
        }
    }

    private func workItemRepositoryRoot(for event: HeartbeatChangeEvent) -> String? {
        let candidates = [
            event.metadata["repositoryRoot"],
            event.metadata["newRepositoryRoot"],
            event.metadata["oldRepositoryRoot"],
            event.metadata["path"],
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func workItemSeverity(for severity: HeartbeatChangeSeverity) -> WorkItemSeverity {
        switch severity {
        case .info:
            return .info
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }

    private func workItemSuggestedAction(for event: HeartbeatChangeEvent) -> String {
        switch event.eventType {
        case .codingSessionStarted:
            return "bridge.orchestrator.select_session"
        default:
            return "bridge.orchestrator.status"
        }
    }

    private func workItemTTL(for severity: HeartbeatChangeSeverity) -> TimeInterval {
        switch severity {
        case .critical:
            return 48 * 60 * 60
        case .warning:
            return 24 * 60 * 60
        case .info:
            return 12 * 60 * 60
        }
    }

    private func trimChangeAlertDedupeState() {
        let overflow = changeAlertLastSentAt.count - Self.maxChangeAlertDedupeEntries
        guard overflow > 0 else { return }

        let keysToDrop = changeAlertLastSentAt
            .sorted { $0.value < $1.value }
            .prefix(overflow)
            .map(\.key)
        for key in keysToDrop {
            changeAlertLastSentAt.removeValue(forKey: key)
        }
    }

    private func severityScore(_ severity: HeartbeatChangeSeverity) -> Int {
        switch severity {
        case .critical:
            return 3
        case .warning:
            return 2
        case .info:
            return 1
        }
    }

    private func numericMetadataValue(_ raw: String?) -> Int {
        guard let raw, let value = Int(raw) else { return 0 }
        return value
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

    // MARK: - Task Opportunity Mapping (D1)

    func mapTaskOpportunities(
        calendarContext: String,
        kanbanContext: String,
        reminderContext: String,
        memoryWarning: String?
    ) -> [TaskOpportunity] {
        var opportunities: [TaskOpportunity] = []

        let calendarLines = normalizedLines(from: calendarContext)
        for line in calendarLines.prefix(2) {
            opportunities.append(
                TaskOpportunity(
                    source: .calendar,
                    title: "다가오는 일정 준비",
                    detail: line,
                    actionKind: .createReminder,
                    suggestedTitle: "일정 준비: \(line)",
                    suggestedNotes: "Heartbeat 일정 점검에서 제안된 작업입니다."
                )
            )
        }

        let kanbanLines = normalizedLines(from: kanbanContext)
        for line in kanbanLines.prefix(2) {
            let parsed = parseKanbanContextLine(line)
            opportunities.append(
                TaskOpportunity(
                    source: .kanban,
                    title: "칸반 후속 리마인더",
                    detail: line,
                    actionKind: .createReminder,
                    suggestedTitle: "\(parsed.cardTitle) 확인",
                    suggestedNotes: parsed.boardName.map { "보드: \($0)" }
                )
            )
        }

        let reminderLines = normalizedLines(from: reminderContext)
        for line in reminderLines.prefix(2) {
            let reminderTitle = parseReminderTitle(line)
            opportunities.append(
                TaskOpportunity(
                    source: .reminder,
                    title: "미리알림을 칸반으로 등록",
                    detail: line,
                    actionKind: .createKanbanCard,
                    suggestedTitle: reminderTitle,
                    suggestedNotes: "원본 미리알림: \(line)",
                    boardName: defaultBoardName()
                )
            )
        }

        if let memoryWarning, !memoryWarning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            opportunities.append(
                TaskOpportunity(
                    source: .memory,
                    title: "메모리 정리 작업 등록",
                    detail: memoryWarning,
                    actionKind: .createKanbanCard,
                    suggestedTitle: "메모리 정리 점검",
                    suggestedNotes: memoryWarning,
                    boardName: defaultBoardName()
                )
            )
        }

        return Array(opportunities.prefix(4))
    }

    private func normalizedLines(from context: String) -> [String] {
        context
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseReminderTitle(_ line: String) -> String {
        if let range = line.range(of: " (마감:") {
            return String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line
    }

    private func summarizeGitContext(_ roots: [GitRepositoryInsight]) -> String? {
        guard !roots.isEmpty else { return nil }
        let lines = roots.prefix(3).map { root in
            let remoteLabel: String
            if let owner = root.remoteOwner, let repo = root.remoteRepository {
                remoteLabel = "\(owner)/\(repo)"
            } else {
                remoteLabel = "origin:unknown"
            }
            return "- [\(root.workDomain)] \(root.name) (\(root.branch)) local:\(root.lastCommitRelative) origin:\(root.upstreamLastCommitRelative) dirty:\(root.changedFileCount)+\(root.untrackedFileCount) \(remoteLabel)"
        }
        return lines.joined(separator: "\n")
    }

    private func detectOrchestrationOpportunity(
        manager: ExternalToolSessionManagerProtocol,
        preferredRepositoryRoot: String?
    ) async -> String? {
        let selection = await manager.previewSessionForOrchestration(repositoryRoot: preferredRepositoryRoot)
        switch selection.action {
        case .reuseT0Active, .attachT1:
            if let selected = selection.selectedSession {
                return "action=\(selection.action.rawValue) provider=\(selected.provider) session=\(selected.nativeSessionId)"
            }
            return "action=\(selection.action.rawValue)"
        case .createT0:
            return "action=create_t0 repository=\(selection.repositoryRoot ?? "(none)")"
        case .analyzeOnly:
            return "action=analyze_only"
        case .none:
            return nil
        }
    }

    private func shouldRefreshSessionHistoryIndex(
        manager: ExternalToolSessionManagerProtocol,
        now: Date = Date()
    ) async -> Bool {
        if let last = lastSessionHistoryIndexRefreshAt,
           now.timeIntervalSince(last) < Self.sessionHistoryRefreshInterval {
            return false
        }

        let status = manager.sessionHistoryIndexStatus()
        guard status.chunkCount == 0 || status.lastIndexedAt == nil else {
            guard let indexedAt = status.lastIndexedAt else { return true }
            return now.timeIntervalSince(indexedAt) >= Self.sessionHistoryRefreshInterval
        }
        return true
    }

    private func parseKanbanContextLine(_ line: String) -> (cardTitle: String, boardName: String?) {
        var working = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if working.hasPrefix("- ") {
            working.removeFirst(2)
        }

        var boardName: String?
        if let open = working.lastIndex(of: "["), let close = working.lastIndex(of: "]"), open < close {
            boardName = String(working[working.index(after: open)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
            working = String(working[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tokens = working.split(separator: " ").map(String.init)
        if let first = tokens.first, first.rangeOfCharacter(from: .alphanumerics) == nil {
            working = tokens.dropFirst().joined(separator: " ")
        }

        let cardTitle = working.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cardTitle.isEmpty ? line : cardTitle, boardName)
    }

    private func defaultBoardName() -> String? {
        KanbanManager.shared.listBoards().first?.name
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
