import XCTest
@testable import Dochi

@MainActor
final class HeartbeatServiceTests: XCTestCase {
    private final class MockHeartbeatChangeJournal: HeartbeatChangeJournalProtocol {
        private(set) var entries: [ChangeJournalEntry] = []
        private(set) var appendCallCount = 0

        func append(events: [HeartbeatChangeEvent]) {
            appendCallCount += 1
            entries.append(contentsOf: events.map { ChangeJournalEntry(event: $0) })
        }

        func recentEntries(limit: Int, source: HeartbeatChangeSource?) -> [ChangeJournalEntry] {
            let filtered = source.map { source in
                entries.filter { $0.event.source == source }
            } ?? entries
            return Array(filtered.suffix(max(0, limit)).reversed())
        }
    }

    private func makeViewModelForOpportunityTests() -> DochiViewModel {
        let contextService = MockContextService()
        let settings = AppSettings()
        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"

        return DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: contextService,
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: SessionContext(workspaceId: UUID())
        )
    }

    private func makeGitInsight(
        path: String,
        name: String = "work",
        branch: String = "main",
        changedFileCount: Int = 0,
        untrackedFileCount: Int = 0,
        aheadCount: Int = 0,
        behindCount: Int = 0
    ) -> GitRepositoryInsight {
        GitRepositoryInsight(
            workDomain: "company",
            workDomainConfidence: 0.8,
            workDomainReason: "test",
            path: path,
            name: name,
            branch: branch,
            originURL: "ssh://git@example.com/team/\(name).git",
            remoteHost: "example.com",
            remoteOwner: "team",
            remoteRepository: name,
            lastCommitEpoch: 1_700_000_000,
            lastCommitISO8601: "2023-11-14T22:13:20.000Z",
            lastCommitRelative: "1d ago",
            upstreamLastCommitEpoch: 1_700_000_000,
            upstreamLastCommitISO8601: "2023-11-14T22:13:20.000Z",
            upstreamLastCommitRelative: "1d ago",
            daysSinceLastCommit: 1,
            recentCommitCount30d: 8,
            changedFileCount: changedFileCount,
            untrackedFileCount: untrackedFileCount,
            aheadCount: aheadCount,
            behindCount: behindCount,
            score: 60
        )
    }

    private func makeUnifiedSession(
        provider: String = "codex",
        nativeSessionId: String,
        runtimeSessionId: String? = nil,
        path: String,
        repositoryRoot: String? = nil,
        activityState: CodingSessionActivityState = .active
    ) -> UnifiedCodingSession {
        UnifiedCodingSession(
            source: "mock",
            runtimeType: .process,
            controllabilityTier: .t2Observe,
            provider: provider,
            nativeSessionId: nativeSessionId,
            runtimeSessionId: runtimeSessionId,
            workingDirectory: repositoryRoot,
            repositoryRoot: repositoryRoot,
            path: path,
            updatedAt: Date(),
            isActive: activityState == .active || activityState == .idle,
            activityScore: activityState == .active ? 80 : 20,
            activityState: activityState,
            activitySignals: CodingSessionActivitySignals(
                runtimeAliveScore: 1,
                recentOutputScore: 1,
                recentCommandScore: 1,
                fileFreshnessScore: 1,
                errorPenaltyScore: 0
            )
        )
    }

    // MARK: - HeartbeatTickResult

    func testTickResultStoresAllFields() {
        let result = HeartbeatTickResult(
            timestamp: Date(),
            checksPerformed: ["calendar", "kanban"],
            itemsFound: 3,
            notificationSent: true,
            error: nil
        )
        XCTAssertEqual(result.checksPerformed.count, 2)
        XCTAssertEqual(result.itemsFound, 3)
        XCTAssertTrue(result.notificationSent)
        XCTAssertNil(result.error)
    }

    func testTickResultWithError() {
        let result = HeartbeatTickResult(
            timestamp: Date(),
            checksPerformed: [],
            itemsFound: 0,
            notificationSent: false,
            error: "Test error"
        )
        XCTAssertEqual(result.error, "Test error")
        XCTAssertFalse(result.notificationSent)
    }

    // MARK: - HeartbeatService Init

    func testServiceInitialization() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)
        XCTAssertNil(service.lastTickDate)
        XCTAssertNil(service.lastTickResult)
        XCTAssertTrue(service.tickHistory.isEmpty)
        XCTAssertEqual(service.consecutiveErrors, 0)
    }

    func testMaxHistoryCount() {
        XCTAssertEqual(HeartbeatService.maxHistoryCount, 20)
    }

    func testDetectChangeEventsUsesBaselineWithoutEmitting() {
        let settings = AppSettings()
        settings.heartbeatTrackGitChanges = true
        settings.heartbeatTrackCodingSessionChanges = true
        let service = HeartbeatService(settings: settings)

        let baselineEvents = service.detectChangeEvents(
            gitInsights: [makeGitInsight(path: "/tmp/repo-a")],
            codingSessions: [makeUnifiedSession(
                nativeSessionId: "session-1",
                path: "tmux://session-1",
                repositoryRoot: "/tmp/repo-a"
            )],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(baselineEvents.isEmpty)
    }

    func testDetectChangeEventsReportsGitAndCodingSessionTransitions() {
        let settings = AppSettings()
        settings.heartbeatTrackGitChanges = true
        settings.heartbeatTrackCodingSessionChanges = true
        let service = HeartbeatService(settings: settings)

        _ = service.detectChangeEvents(
            gitInsights: [makeGitInsight(path: "/tmp/repo-a", branch: "main", changedFileCount: 0, untrackedFileCount: 0)],
            codingSessions: [makeUnifiedSession(
                nativeSessionId: "session-1",
                path: "tmux://session-1",
                repositoryRoot: "/tmp/repo-a",
                activityState: .active
            )],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let changedEvents = service.detectChangeEvents(
            gitInsights: [makeGitInsight(
                path: "/tmp/repo-a",
                branch: "feature/heartbeat",
                changedFileCount: 10,
                untrackedFileCount: 1,
                aheadCount: 2,
                behindCount: 1
            )],
            codingSessions: [makeUnifiedSession(
                nativeSessionId: "session-1",
                path: "tmux://session-1",
                repositoryRoot: "/tmp/repo-b",
                activityState: .stale
            )],
            timestamp: Date(timeIntervalSince1970: 1_700_000_060)
        )

        let eventTypes = Set(changedEvents.map(\.eventType))
        XCTAssertTrue(eventTypes.contains(.gitBranchChanged))
        XCTAssertTrue(eventTypes.contains(.gitDirtySpike))
        XCTAssertTrue(eventTypes.contains(.gitAheadBehindChanged))
        XCTAssertTrue(eventTypes.contains(.codingSessionActivityChanged))
        XCTAssertTrue(eventTypes.contains(.codingSessionRepositoryChanged))
    }

    func testDetectChangeEventsHonorsSourceTrackingSettings() {
        func runChanges(service: HeartbeatService) -> [HeartbeatChangeEvent] {
            _ = service.detectChangeEvents(
                gitInsights: [makeGitInsight(path: "/tmp/repo-a", branch: "main", changedFileCount: 0, untrackedFileCount: 0)],
                codingSessions: [makeUnifiedSession(
                    nativeSessionId: "session-1",
                    path: "tmux://session-1",
                    repositoryRoot: "/tmp/repo-a",
                    activityState: .active
                )],
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )

            return service.detectChangeEvents(
                gitInsights: [makeGitInsight(
                    path: "/tmp/repo-a",
                    branch: "feature/heartbeat",
                    changedFileCount: 10,
                    untrackedFileCount: 1,
                    aheadCount: 2,
                    behindCount: 1
                )],
                codingSessions: [makeUnifiedSession(
                    nativeSessionId: "session-1",
                    path: "tmux://session-1",
                    repositoryRoot: "/tmp/repo-b",
                    activityState: .stale
                )],
                timestamp: Date(timeIntervalSince1970: 1_700_000_060)
            )
        }

        let gitDisabledSettings = AppSettings()
        gitDisabledSettings.heartbeatTrackGitChanges = false
        gitDisabledSettings.heartbeatTrackCodingSessionChanges = true
        let gitDisabledEvents = runChanges(service: HeartbeatService(settings: gitDisabledSettings))
        XCTAssertTrue(gitDisabledEvents.allSatisfy { $0.source == .codingSession })

        let sessionDisabledSettings = AppSettings()
        sessionDisabledSettings.heartbeatTrackGitChanges = true
        sessionDisabledSettings.heartbeatTrackCodingSessionChanges = false
        let sessionDisabledEvents = runChanges(service: HeartbeatService(settings: sessionDisabledSettings))
        XCTAssertTrue(sessionDisabledEvents.allSatisfy { $0.source == .git })

        let allDisabledSettings = AppSettings()
        allDisabledSettings.heartbeatTrackGitChanges = false
        allDisabledSettings.heartbeatTrackCodingSessionChanges = false
        let allDisabledEvents = runChanges(service: HeartbeatService(settings: allDisabledSettings))
        XCTAssertTrue(allDisabledEvents.isEmpty)
    }

    func testSelectChangeAlertsToSendAppliesRuleAndCooldown() {
        let settings = AppSettings()
        settings.heartbeatChangeAlertEnabled = true
        settings.heartbeatChangeAlertCooldownMinutes = 10
        let service = HeartbeatService(settings: settings)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dirtySpike = HeartbeatChangeEvent(
            source: .git,
            eventType: .gitDirtySpike,
            severity: .warning,
            targetId: "/tmp/repo-a",
            title: "dirty",
            detail: "dirty spike",
            timestamp: now
        )
        let branchChanged = HeartbeatChangeEvent(
            source: .git,
            eventType: .gitBranchChanged,
            severity: .info,
            targetId: "/tmp/repo-a",
            title: "branch",
            detail: "branch changed",
            timestamp: now
        )
        let staleTransition = HeartbeatChangeEvent(
            source: .codingSession,
            eventType: .codingSessionActivityChanged,
            severity: .warning,
            targetId: "codex|sess-1|-|/tmp/repo-a",
            title: "state",
            detail: "active -> stale",
            metadata: ["newActivityState": "stale"],
            timestamp: now
        )

        let first = service.selectChangeAlertsToSend(
            from: [dirtySpike, branchChanged, staleTransition],
            now: now
        )
        XCTAssertEqual(Set(first.map(\.eventType)), Set([.gitDirtySpike, .codingSessionActivityChanged]))

        let withinCooldown = service.selectChangeAlertsToSend(
            from: [dirtySpike, staleTransition],
            now: now.addingTimeInterval(60)
        )
        XCTAssertTrue(withinCooldown.isEmpty)

        let afterCooldown = service.selectChangeAlertsToSend(
            from: [dirtySpike, staleTransition],
            now: now.addingTimeInterval(601)
        )
        XCTAssertEqual(Set(afterCooldown.map(\.eventType)), Set([.gitDirtySpike, .codingSessionActivityChanged]))
    }

    func testMapTaskOpportunitiesBuildsStructuredActions() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)

        let opportunities = service.mapTaskOpportunities(
            calendarContext: "오전 9:00 팀 스탠드업",
            kanbanContext: "- 🔥 배포 체크 [제품 운영]",
            reminderContext: "계약서 확인 (마감: 오후 3:00)",
            memoryWarning: nil
        )

        XCTAssertGreaterThanOrEqual(opportunities.count, 3)
        XCTAssertTrue(opportunities.contains { $0.actionKind == .createReminder })
        XCTAssertTrue(opportunities.contains { $0.actionKind == .createKanbanCard })
        XCTAssertTrue(opportunities.allSatisfy { !$0.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testMapTaskOpportunitiesCapsResultSize() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)

        let opportunities = service.mapTaskOpportunities(
            calendarContext: "a\nb\nc",
            kanbanContext: "- x [A]\n- y [B]\n- z [C]",
            reminderContext: "r1 (마감: 10:00)\nr2 (마감: 11:00)\nr3 (마감: 12:00)",
            memoryWarning: "메모리 경고"
        )

        XCTAssertEqual(opportunities.count, 4)
    }

    // MARK: - Start/Stop

    func testStartWithDisabledSettingsDoesNothing() {
        let settings = AppSettings()
        settings.heartbeatEnabled = false
        let service = HeartbeatService(settings: settings)
        service.start()
        // Should not crash, no tick should happen
        XCTAssertNil(service.lastTickDate)
    }

    func testStopIsIdempotent() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)
        service.stop()
        service.stop() // Should not crash
        XCTAssertNil(service.lastTickDate)
    }

    func testRestartCyclesCleanly() {
        let settings = AppSettings()
        settings.heartbeatEnabled = false
        let service = HeartbeatService(settings: settings)
        service.restart()
        service.restart()
        XCTAssertNil(service.lastTickDate)
    }

    // MARK: - Configure

    func testConfigureAcceptsDependencies() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)
        let contextService = MockContextService()
        let sessionContext = SessionContext(workspaceId: UUID())
        service.configure(contextService: contextService, sessionContext: sessionContext)
        // Should not crash
    }

    func testTickDoesNotTriggerExternalToolHealthCheck() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.externalToolEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        service.setExternalToolManager(externalToolManager)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertEqual(
            externalToolManager.checkAllHealthCallCount,
            0,
            "External tool health checks should be driven by ExternalToolSessionManager monitor, not HeartbeatService tick."
        )
    }

    func testTickCollectsGitContextWithoutSendingNotificationAlone() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        externalToolManager.mockGitRepositoryInsights = [
            GitRepositoryInsight(
                workDomain: "company",
                workDomainConfidence: 0.82,
                workDomainReason: "self-hosted git remote",
                path: "/Users/me/repo/work",
                name: "work",
                branch: "main",
                originURL: "ssh://git@git.company.local/team/work.git",
                remoteHost: "git.company.local",
                remoteOwner: "team",
                remoteRepository: "work",
                lastCommitEpoch: 1_700_000_000,
                lastCommitISO8601: "2023-11-14T22:13:20.000Z",
                lastCommitRelative: "1d ago",
                upstreamLastCommitEpoch: 1_700_000_000,
                upstreamLastCommitISO8601: "2023-11-14T22:13:20.000Z",
                upstreamLastCommitRelative: "1d ago",
                daysSinceLastCommit: 1,
                recentCommitCount30d: 8,
                changedFileCount: 2,
                untrackedFileCount: 1,
                aheadCount: 0,
                behindCount: 0,
                score: 60
            ),
        ]
        service.setExternalToolManager(externalToolManager)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertEqual(service.lastTickResult?.notificationSent, false)
        XCTAssertTrue(service.lastTickResult?.gitContextSummary?.contains("[company] work") == true)
    }

    func testTickIncludesDetectedSessionChangesInHistory() async {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatTrackGitChanges = true
        settings.heartbeatTrackCodingSessionChanges = true
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        externalToolManager.mockGitRepositoryInsights = [makeGitInsight(path: "/tmp/repo-a")]
        externalToolManager.mockUnifiedCodingSessions = [
            makeUnifiedSession(
                nativeSessionId: "session-1",
                path: "tmux://session-1",
                repositoryRoot: "/tmp/repo-a",
                activityState: .active
            ),
        ]
        service.setExternalToolManager(externalToolManager)
        await service.runTickForTesting()

        externalToolManager.mockUnifiedCodingSessions = [
            makeUnifiedSession(
                nativeSessionId: "session-1",
                path: "tmux://session-1",
                repositoryRoot: "/tmp/repo-a",
                activityState: .idle
            ),
            makeUnifiedSession(
                nativeSessionId: "session-2",
                path: "tmux://session-2",
                repositoryRoot: "/tmp/repo-a",
                activityState: .active
            ),
        ]
        await service.runTickForTesting()

        let hasSessionEvent = service.tickHistory.contains { tick in
            tick.detectedChanges.contains { event in
                event.eventType == .codingSessionStarted || event.eventType == .codingSessionActivityChanged
            }
        }

        XCTAssertTrue(hasSessionEvent)
        XCTAssertGreaterThan(externalToolManager.listUnifiedCodingSessionsCallCount, 0)
    }

    func testTickPersistsDetectedChangesIntoJournalService() async {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatTrackGitChanges = true
        settings.heartbeatTrackCodingSessionChanges = true
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        let journal = MockHeartbeatChangeJournal()
        service.setChangeJournalService(journal)

        externalToolManager.mockGitRepositoryInsights = [makeGitInsight(path: "/tmp/repo-a")]
        externalToolManager.mockUnifiedCodingSessions = [
            makeUnifiedSession(
                nativeSessionId: "session-1",
                path: "tmux://session-1",
                repositoryRoot: "/tmp/repo-a",
                activityState: .active
            ),
        ]
        service.setExternalToolManager(externalToolManager)

        await service.runTickForTesting() // baseline

        externalToolManager.mockUnifiedCodingSessions = []
        await service.runTickForTesting() // session end event

        XCTAssertGreaterThan(journal.appendCallCount, 0)
        XCTAssertTrue(journal.entries.contains { $0.event.eventType == .codingSessionEnded })
    }

    func testTickSendsChangeAlertToTelegramWhenEnabled() async {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatTrackGitChanges = true
        settings.heartbeatTrackCodingSessionChanges = true
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0
        settings.heartbeatNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.heartbeatChangeAlertEnabled = true

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        let relay = MockTelegramProactiveRelay()
        service.setExternalToolManager(externalToolManager)
        service.setTelegramRelay(relay)

        externalToolManager.mockGitRepositoryInsights = [makeGitInsight(path: "/tmp/repo-a")]
        externalToolManager.mockUnifiedCodingSessions = [
            makeUnifiedSession(
                nativeSessionId: "session-1",
                path: "tmux://session-1",
                repositoryRoot: "/tmp/repo-a",
                activityState: .active
            ),
        ]
        await service.runTickForTesting() // baseline

        externalToolManager.mockUnifiedCodingSessions = []
        await service.runTickForTesting() // session ended -> alert candidate

        XCTAssertEqual(relay.sendHeartbeatChangeAlertCallCount, 1)
        XCTAssertEqual(relay.lastHeartbeatChangeEvent?.eventType, .codingSessionEnded)
    }

    func testTickKeepsJournalWhenChangeAlertDisabled() async {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatTrackGitChanges = true
        settings.heartbeatTrackCodingSessionChanges = true
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0
        settings.heartbeatNotificationChannel = NotificationChannel.telegramOnly.rawValue
        settings.heartbeatChangeAlertEnabled = false

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        let relay = MockTelegramProactiveRelay()
        let journal = MockHeartbeatChangeJournal()
        service.setExternalToolManager(externalToolManager)
        service.setTelegramRelay(relay)
        service.setChangeJournalService(journal)

        externalToolManager.mockGitRepositoryInsights = [makeGitInsight(path: "/tmp/repo-a")]
        externalToolManager.mockUnifiedCodingSessions = [
            makeUnifiedSession(
                nativeSessionId: "session-1",
                path: "tmux://session-1",
                repositoryRoot: "/tmp/repo-a",
                activityState: .active
            ),
        ]
        await service.runTickForTesting() // baseline

        externalToolManager.mockUnifiedCodingSessions = []
        await service.runTickForTesting() // session ended

        XCTAssertGreaterThan(journal.appendCallCount, 0)
        XCTAssertTrue(journal.entries.contains { $0.event.eventType == .codingSessionEnded })
        XCTAssertEqual(relay.sendHeartbeatChangeAlertCallCount, 0)
    }

    func testTickRefreshesSessionHistoryIndexWhenStale() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        externalToolManager.mockSessionHistoryIndexStatus = SessionHistoryIndexStatus(
            chunkCount: 0,
            lastIndexedAt: nil,
            latestChunkEndAt: nil
        )
        service.setExternalToolManager(externalToolManager)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertGreaterThanOrEqual(externalToolManager.rebuildSessionHistoryIndexCallCount, 1)
    }

    func testTickDetectsOrchestrationOpportunityUsingObservabilityListing() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0

        let service = HeartbeatService(settings: settings)
        let externalToolManager = MockExternalToolSessionManager()
        externalToolManager.mockGitRepositoryInsights = [
            GitRepositoryInsight(
                workDomain: "company",
                workDomainConfidence: 0.9,
                workDomainReason: "test",
                path: "/tmp/repo-opportunity",
                name: "repo-opportunity",
                branch: "main",
                originURL: nil,
                remoteHost: nil,
                remoteOwner: nil,
                remoteRepository: nil,
                lastCommitEpoch: nil,
                lastCommitISO8601: nil,
                lastCommitRelative: "-",
                upstreamLastCommitEpoch: nil,
                upstreamLastCommitISO8601: nil,
                upstreamLastCommitRelative: "-",
                daysSinceLastCommit: nil,
                recentCommitCount30d: 0,
                changedFileCount: 0,
                untrackedFileCount: 0,
                aheadCount: nil,
                behindCount: nil,
                score: 50
            ),
        ]
        externalToolManager.mockUnifiedCodingSessions = [
            UnifiedCodingSession(
                source: "test",
                runtimeType: .tmux,
                controllabilityTier: .t0Full,
                provider: "codex",
                nativeSessionId: "sess-1",
                runtimeSessionId: UUID().uuidString,
                workingDirectory: "/tmp/repo-opportunity",
                repositoryRoot: "/tmp/repo-opportunity",
                path: "/tmp/repo-opportunity/.codex/sessions/a.jsonl",
                updatedAt: Date(),
                isActive: true,
                activityScore: 92,
                activityState: .active
            ),
        ]
        service.setExternalToolManager(externalToolManager)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertGreaterThanOrEqual(externalToolManager.listUnifiedCodingSessionsForObservabilityCallCount, 1)
        XCTAssertEqual(externalToolManager.selectSessionForOrchestrationCallCount, 0)
        XCTAssertTrue(service.lastTickResult?.orchestrationOpportunitySummary?.contains("reuse_t0_active") == true)
    }

    func testTickTriggersResourceAutoTaskPipelineWhenEnabled() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0
        settings.resourceAutoTaskEnabled = true
        settings.resourceAutoTaskOnlyWasteRisk = true
        settings.resourceAutoTaskTypes = [AutoTaskType.research.rawValue]

        let service = HeartbeatService(settings: settings)
        let optimizer = MockResourceOptimizer()
        service.setResourceOptimizer(optimizer)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertGreaterThanOrEqual(optimizer.evaluateAndQueueAutoTasksCallCount, 1)
        XCTAssertEqual(optimizer.lastOnlyWasteRisk, true)
        XCTAssertEqual(Set(optimizer.lastEvaluatedTypes), Set([.research]))
    }

    func testTickResourceAutoTaskUsesSubscriptionSourceAxis() async throws {
        let settings = AppSettings()
        settings.heartbeatEnabled = true
        settings.heartbeatIntervalMinutes = 0
        settings.heartbeatCheckCalendar = false
        settings.heartbeatCheckKanban = false
        settings.heartbeatCheckReminders = false
        settings.heartbeatQuietHoursStart = 0
        settings.heartbeatQuietHoursEnd = 0
        settings.resourceAutoTaskEnabled = true
        settings.resourceAutoTaskOnlyWasteRisk = false
        settings.resourceAutoTaskTypes = [AutoTaskType.research.rawValue]

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeartbeatResourceOptimizer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let optimizer = ResourceOptimizerService(
            baseURL: tempRoot.appendingPathComponent("optimizer"),
            usageStore: nil,
            claudeProjectsRoots: [tempRoot.appendingPathComponent("claude-empty")],
            codexSessionsRoots: [tempRoot.appendingPathComponent("codex-empty")]
        )
        let meteredPlan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Metered",
            usageSource: .dochiUsageStore,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        let subscriptionPlan = SubscriptionPlan(
            providerName: "ChatGPT Pro",
            planName: "Plus",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        await optimizer.addSubscription(meteredPlan)
        await optimizer.addSubscription(subscriptionPlan)

        let service = HeartbeatService(settings: settings)
        service.setResourceOptimizer(optimizer)

        service.start()
        defer { service.stop() }

        let timeout = Date().addingTimeInterval(0.5)
        while service.lastTickDate == nil && Date() < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(service.lastTickDate)
        XCTAssertEqual(optimizer.autoTaskRecords.count, 1)
        XCTAssertEqual(optimizer.autoTaskRecords.first?.subscriptionId, subscriptionPlan.id)
    }

    // MARK: - Proactive Handler

    func testProactiveHandlerIsCalled() {
        let settings = AppSettings()
        let service = HeartbeatService(settings: settings)

        var receivedMessage: String?
        service.setProactiveHandler { message in
            receivedMessage = message
        }

        // Directly verify handler is set by replacing it
        service.setProactiveHandler { message in
            receivedMessage = message
        }
        XCTAssertNil(receivedMessage) // Not called yet
    }

    // MARK: - ViewModel integration

    func testInjectProactiveMessageAddsToConversation() {
        let contextService = MockContextService()
        let settings = AppSettings()
        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"
        let sessionContext = SessionContext(workspaceId: UUID())

        let viewModel = DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: contextService,
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: sessionContext
        )

        // Create a conversation manually (newConversation() sets it to nil)
        viewModel.currentConversation = Conversation(title: "테스트")
        XCTAssertNotNil(viewModel.currentConversation)

        let messageBefore = viewModel.currentConversation?.messages.count ?? 0
        viewModel.injectProactiveMessage("테스트 알림")
        let messageAfter = viewModel.currentConversation?.messages.count ?? 0

        XCTAssertEqual(messageAfter, messageBefore + 1)
        XCTAssertEqual(viewModel.currentConversation?.messages.last?.content, "테스트 알림")
        XCTAssertEqual(viewModel.currentConversation?.messages.last?.role, .assistant)
    }

    func testInjectProactiveMessageWithNoConversationDoesNothing() {
        let settings = AppSettings()
        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"

        let viewModel = DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: settings,
            sessionContext: SessionContext(workspaceId: UUID())
        )

        // Don't create a conversation
        viewModel.injectProactiveMessage("no conversation")
        // Should not crash
        XCTAssertNil(viewModel.currentConversation)
    }

    func testExecuteTaskOpportunityTriggersKanbanActionAndShowsSuccessFeedback() async {
        let viewModel = makeViewModelForOpportunityTests()
        let opportunity = TaskOpportunity(
            source: .reminder,
            title: "칸반 등록",
            detail: "테스트",
            actionKind: .createKanbanCard,
            suggestedTitle: "테스트 작업"
        )

        let called = expectation(description: "kanban action called")
        viewModel.kanbanOpportunityExecutor = { _ in
            called.fulfill()
            return true
        }

        viewModel.executeTaskOpportunity(opportunity)
        await fulfillment(of: [called], timeout: 1.0)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.taskOpportunityActionFeedback?.opportunityId, opportunity.id)
        XCTAssertEqual(viewModel.taskOpportunityActionFeedback?.isSuccess, true)
        XCTAssertTrue(viewModel.completedTaskOpportunityIDs.contains(opportunity.id))
    }

    func testExecuteTaskOpportunityFailureShowsErrorFeedback() async {
        let viewModel = makeViewModelForOpportunityTests()
        let opportunity = TaskOpportunity(
            source: .calendar,
            title: "미리알림 등록",
            detail: "테스트",
            actionKind: .createReminder,
            suggestedTitle: "테스트 리마인더"
        )

        let called = expectation(description: "reminder action called")
        viewModel.reminderOpportunityExecutor = { _ in
            called.fulfill()
            return ToolResult(toolCallId: "", content: "미리알림 생성 실패", isError: true)
        }

        viewModel.executeTaskOpportunity(opportunity)
        await fulfillment(of: [called], timeout: 1.0)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.taskOpportunityActionFeedback?.opportunityId, opportunity.id)
        XCTAssertEqual(viewModel.taskOpportunityActionFeedback?.isSuccess, false)
        XCTAssertEqual(viewModel.errorMessage, "미리알림 생성 실패")
        XCTAssertFalse(viewModel.completedTaskOpportunityIDs.contains(opportunity.id))
    }
}
