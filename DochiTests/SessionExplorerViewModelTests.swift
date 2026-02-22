import XCTest
@testable import Dochi

final class SessionExplorerViewModelTests: XCTestCase {

    func testRepositorySummariesAggregateCounts() {
        let now = Date()
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "a",
                repo: "/tmp/repo-a",
                state: .active,
                score: 90,
                updatedAt: now
            ),
            makeSession(
                provider: "codex",
                nativeId: "b",
                repo: "/tmp/repo-a",
                state: .idle,
                score: 70,
                updatedAt: now.addingTimeInterval(-30),
                errorPenalty: 20
            ),
            makeSession(
                provider: "claude",
                nativeId: "c",
                repo: nil,
                state: .stale,
                score: 22,
                updatedAt: now.addingTimeInterval(-60)
            ),
        ]

        let summaries = SessionExplorerViewStateBuilder.repositorySummaries(from: sessions)
        let repoA = summaries.first(where: { $0.repositoryRoot == "/tmp/repo-a" })
        let unassigned = summaries.first(where: { $0.repositoryRoot == nil })

        XCTAssertEqual(repoA?.sessionCount, 2)
        XCTAssertEqual(repoA?.activeSessionCount, 2)
        XCTAssertEqual(repoA?.errorSessionCount, 1)
        XCTAssertEqual(unassigned?.sessionCount, 1)
        XCTAssertEqual(unassigned?.displayName, "Unassigned")
    }

    func testFilteredSessionsApplyTierAndActivityFilters() {
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "t0-active",
                repo: "/tmp/repo-a",
                tier: .t0Full,
                state: .active,
                score: 88
            ),
            makeSession(
                provider: "codex",
                nativeId: "t2-stale",
                repo: nil,
                tier: .t2Observe,
                state: .stale,
                score: 18
            ),
        ]

        let filtered = SessionExplorerViewStateBuilder.filteredSessions(
            sessions: sessions,
            filter: SessionExplorerFilter(
                repositoryRoot: nil,
                provider: "codex",
                tier: .t0Full,
                activeOnly: true,
                unassignedOnly: false
            ),
            sort: .activity
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.nativeSessionId, "t0-active")
    }

    func testRepositoryGroupsExcludeUnassignedAndNormalizePath() {
        let now = Date()
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "repo-a-1",
                repo: "/tmp/repo-a",
                tier: .t1Attach,
                state: .active,
                score: 81,
                updatedAt: now
            ),
            makeSession(
                provider: "claude",
                nativeId: "repo-a-2",
                repo: "/tmp/repo-a/../repo-a",
                tier: .t2Observe,
                state: .stale,
                score: 30,
                updatedAt: now.addingTimeInterval(-60)
            ),
            makeSession(
                provider: "codex",
                nativeId: "repo-b-1",
                repo: "/tmp/repo-b",
                tier: .t0Full,
                state: .idle,
                score: 71,
                updatedAt: now.addingTimeInterval(-20)
            ),
            makeSession(
                provider: "aider",
                nativeId: "unassigned",
                repo: nil,
                tier: .t3Unknown,
                state: .dead,
                score: 0,
                updatedAt: now.addingTimeInterval(-30)
            ),
        ]

        let groups = SessionExplorerViewStateBuilder.repositoryGroups(
            sessions: sessions,
            sort: .activity
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.repositoryRoot, "/tmp/repo-a")
        XCTAssertEqual(groups.first?.sessionCount, 2)
        XCTAssertEqual(groups.first?.activeSessionCount, 1)
        XCTAssertEqual(groups.first?.errorSessionCount, 0)
        XCTAssertFalse(groups.contains(where: { $0.repositoryRoot == "unassigned" }))
    }

    func testRepositoryGroupsSortSessionsWithProviderOption() {
        let sessions = [
            makeSession(
                provider: "zai",
                nativeId: "z",
                repo: "/tmp/repo-z",
                tier: .t0Full,
                state: .active,
                score: 77
            ),
            makeSession(
                provider: "anthropic",
                nativeId: "a",
                repo: "/tmp/repo-z",
                tier: .t1Attach,
                state: .active,
                score: 68
            ),
        ]

        let groups = SessionExplorerViewStateBuilder.repositoryGroups(
            sessions: sessions,
            sort: .provider
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].sessions.map(\.provider), ["anthropic", "zai"])
    }

    func testOrchestrationWorkboardLaneClassifiesSessionStates() {
        let blocked = makeSession(
            provider: "codex",
            nativeId: "blocked",
            repo: "/tmp/repo-a",
            tier: .t1Attach,
            state: .idle,
            score: 82,
            errorPenalty: 12
        )
        let running = makeSession(
            provider: "codex",
            nativeId: "running",
            repo: "/tmp/repo-a",
            tier: .t0Full,
            state: .active,
            score: 85
        )
        let done = makeSession(
            provider: "claude",
            nativeId: "done",
            repo: "/tmp/repo-b",
            tier: .t2Observe,
            state: .idle,
            score: 72
        )
        let review = makeSession(
            provider: "claude",
            nativeId: "review",
            repo: "/tmp/repo-c",
            tier: .t2Observe,
            state: .stale,
            score: 35
        )
        let queued = makeSession(
            provider: "aider",
            nativeId: "queued",
            repo: nil,
            tier: .t3Unknown,
            state: .idle,
            score: 51
        )

        XCTAssertEqual(
            SessionExplorerViewStateBuilder.orchestrationWorkboardLane(for: blocked),
            .blocked
        )
        XCTAssertEqual(
            SessionExplorerViewStateBuilder.orchestrationWorkboardLane(for: running),
            .running
        )
        XCTAssertEqual(
            SessionExplorerViewStateBuilder.orchestrationWorkboardLane(for: done),
            .done
        )
        XCTAssertEqual(
            SessionExplorerViewStateBuilder.orchestrationWorkboardLane(for: review),
            .review
        )
        XCTAssertEqual(
            SessionExplorerViewStateBuilder.orchestrationWorkboardLane(for: queued),
            .queued
        )
    }

    func testOrchestrationWorkboardGroupsPrioritizeBlockedThenRunning() {
        let now = Date()
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "review",
                repo: "/tmp/repo-r",
                tier: .t2Observe,
                state: .stale,
                score: 33,
                updatedAt: now.addingTimeInterval(-90)
            ),
            makeSession(
                provider: "codex",
                nativeId: "done",
                repo: "/tmp/repo-d",
                tier: .t0Full,
                state: .idle,
                score: 75,
                updatedAt: now.addingTimeInterval(-40)
            ),
            makeSession(
                provider: "codex",
                nativeId: "running",
                repo: "/tmp/repo-a",
                tier: .t0Full,
                state: .active,
                score: 90,
                updatedAt: now
            ),
            makeSession(
                provider: "codex",
                nativeId: "blocked",
                repo: "/tmp/repo-b",
                tier: .t1Attach,
                state: .idle,
                score: 60,
                updatedAt: now.addingTimeInterval(-20),
                errorPenalty: 8
            ),
        ]

        let groups = SessionExplorerViewStateBuilder.orchestrationWorkboardGroups(
            sessions: sessions
        )

        XCTAssertEqual(groups.map(\.lane), [.blocked, .running, .review, .done])
        XCTAssertEqual(groups.first?.sessions.first?.nativeSessionId, "blocked")
        XCTAssertEqual(groups[1].sessions.first?.nativeSessionId, "running")
    }

    func testPreferredSessionChoosesMostActionableForRepository() {
        let now = Date()
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "stale-old",
                repo: "/tmp/repo-a",
                tier: .t1Attach,
                state: .stale,
                score: 25,
                updatedAt: now.addingTimeInterval(-500)
            ),
            makeSession(
                provider: "codex",
                nativeId: "active-fresh",
                repo: "/tmp/repo-a/../repo-a",
                tier: .t0Full,
                state: .active,
                score: 91,
                updatedAt: now.addingTimeInterval(-10)
            ),
            makeSession(
                provider: "claude",
                nativeId: "idle-other",
                repo: "/tmp/repo-b",
                tier: .t2Observe,
                state: .idle,
                score: 70,
                updatedAt: now
            ),
        ]

        let preferred = SessionExplorerViewStateBuilder.preferredSession(
            in: "/tmp/repo-a",
            sessions: sessions
        )

        XCTAssertEqual(preferred?.nativeSessionId, "active-fresh")
    }

    func testPreferredSessionSupportsUnassignedQueue() {
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "assigned",
                repo: "/tmp/repo-a",
                tier: .t0Full,
                state: .active,
                score: 80
            ),
            makeSession(
                provider: "claude",
                nativeId: "unassigned-idle",
                repo: nil,
                tier: .t2Observe,
                state: .idle,
                score: 48
            ),
            makeSession(
                provider: "aider",
                nativeId: "unassigned-stale",
                repo: nil,
                tier: .t2Observe,
                state: .stale,
                score: 18
            ),
        ]

        let preferred = SessionExplorerViewStateBuilder.preferredSession(
            in: nil,
            sessions: sessions
        )

        XCTAssertEqual(preferred?.nativeSessionId, "unassigned-idle")
    }

    func testSelectionFilterForRepositoryNormalizesRootAndClearsScopedFilters() {
        let filter = SessionExplorerViewStateBuilder.selectionFilter(for: "/tmp/repo-a/../repo-a")

        XCTAssertEqual(filter.repositoryRoot, "/tmp/repo-a")
        XCTAssertNil(filter.provider)
        XCTAssertNil(filter.tier)
        XCTAssertFalse(filter.activeOnly)
        XCTAssertFalse(filter.unassignedOnly)
    }

    func testSelectionFilterForUnassignedEnablesUnassignedOnly() {
        let filter = SessionExplorerViewStateBuilder.selectionFilter(for: nil)

        XCTAssertNil(filter.repositoryRoot)
        XCTAssertNil(filter.provider)
        XCTAssertNil(filter.tier)
        XCTAssertFalse(filter.activeOnly)
        XCTAssertTrue(filter.unassignedOnly)
    }

    func testSelectedSessionPrefersStableKeyMatch() {
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "repo-a",
                repo: "/tmp/repo-a",
                tier: .t0Full,
                state: .active,
                score: 90
            ),
            makeSession(
                provider: "claude",
                nativeId: "repo-b",
                repo: "/tmp/repo-b",
                tier: .t1Attach,
                state: .idle,
                score: 61
            ),
        ]
        let selectedKey = ExternalToolSessionManager.sessionStableKey(sessions[1])

        let selected = SessionExplorerViewStateBuilder.selectedSession(
            sessions: sessions,
            selectedSessionKey: selectedKey,
            selectedSessionId: nil
        )

        XCTAssertEqual(selected?.nativeSessionId, "repo-b")
    }

    func testSelectedSessionFallsBackToRuntimeSessionId() {
        let runtimeUUID = UUID()
        let target = UnifiedCodingSession(
            source: "runtime",
            runtimeType: .process,
            controllabilityTier: .t1Attach,
            provider: "codex",
            nativeSessionId: "pid-999",
            runtimeSessionId: runtimeUUID.uuidString,
            workingDirectory: "/tmp/repo-a",
            repositoryRoot: "/tmp/repo-a",
            path: "/tmp/pid-999",
            updatedAt: Date(),
            isActive: true,
            activityScore: 58,
            activityState: .idle
        )
        let sessions = [
            makeSession(
                provider: "claude",
                nativeId: "other",
                repo: "/tmp/repo-b",
                tier: .t2Observe,
                state: .stale,
                score: 20
            ),
            target,
        ]

        let selected = SessionExplorerViewStateBuilder.selectedSession(
            sessions: sessions,
            selectedSessionKey: nil,
            selectedSessionId: runtimeUUID
        )

        XCTAssertEqual(selected?.nativeSessionId, "pid-999")
    }

    func testSelectedRepositorySummaryMatchesNormalizedFocusedKey() {
        let summaries = SessionExplorerViewStateBuilder.repositorySummaries(from: [
            makeSession(
                provider: "codex",
                nativeId: "repo-a",
                repo: "/tmp/repo-a",
                tier: .t0Full,
                state: .active,
                score: 88
            ),
            makeSession(
                provider: "claude",
                nativeId: "unassigned",
                repo: nil,
                tier: .t2Observe,
                state: .idle,
                score: 52
            ),
        ])

        let selectedRepo = SessionExplorerViewStateBuilder.selectedRepositorySummary(
            summaries: summaries,
            focusedRepositoryKey: "/tmp/repo-a/../repo-a"
        )
        let selectedUnassigned = SessionExplorerViewStateBuilder.selectedRepositorySummary(
            summaries: summaries,
            focusedRepositoryKey: "unassigned"
        )

        XCTAssertEqual(selectedRepo?.repositoryRoot, "/tmp/repo-a")
        XCTAssertNil(selectedUnassigned?.repositoryRoot)
    }

    func testFilteredSessionsNormalizesRepositoryRootComparison() {
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "normalized",
                repo: "/tmp/repo-a/../repo-a",
                tier: .t0Full,
                state: .active,
                score: 40
            ),
        ]

        let filtered = SessionExplorerViewStateBuilder.filteredSessions(
            sessions: sessions,
            filter: SessionExplorerFilter(
                repositoryRoot: "/tmp/repo-a",
                provider: nil,
                tier: nil,
                activeOnly: false,
                unassignedOnly: false
            ),
            sort: .activity
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.nativeSessionId, "normalized")
    }

    func testRepositoryContainsWorkingDirectoryMatchesNestedPath() {
        let matches = SessionExplorerViewStateBuilder.repositoryContainsWorkingDirectory(
            repositoryRoot: "/tmp/repo-a",
            workingDirectory: "/tmp/repo-a/subdir"
        )

        XCTAssertTrue(matches)
    }

    func testRepositoryContainsWorkingDirectoryRejectsDifferentRepo() {
        let matches = SessionExplorerViewStateBuilder.repositoryContainsWorkingDirectory(
            repositoryRoot: "/tmp/repo-a",
            workingDirectory: "/tmp/repo-b/subdir"
        )

        XCTAssertFalse(matches)
    }

    func testApplyManualRepositoryBindingsOverridesUnassignedSession() {
        let session = makeSession(
            provider: "claude",
            nativeId: "sess-1",
            repo: nil,
            tier: .t2Observe,
            state: .active,
            score: 52
        )
        let key = ExternalToolSessionManager.sessionBindingKey(
            provider: session.provider,
            nativeSessionId: session.nativeSessionId,
            path: session.path
        )
        let mapped = ExternalToolSessionManager.applyManualRepositoryBindings(
            [session],
            manualBindings: [key: "/tmp/repo-mapped"]
        )

        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped.first?.repositoryRoot, "/tmp/repo-mapped")
        XCTAssertFalse(mapped.first?.isUnassigned ?? true)
    }

    func testApplyManualRepositoryBindingsLearnsFromPathPrefixForUnassignedSession() {
        let session = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "claude",
            nativeSessionId: "sess-new",
            runtimeSessionId: nil,
            workingDirectory: nil,
            repositoryRoot: nil,
            path: "/tmp/.claude/projects/-Users-hckim-repo-dochi/sess-new.jsonl",
            updatedAt: Date(),
            isActive: true
        )
        let learnedKey = ExternalToolSessionManager.sessionBindingKey(
            provider: "claude",
            nativeSessionId: "sess-old",
            path: "/tmp/.claude/projects/-Users-hckim-repo-dochi/sess-old.jsonl"
        )

        let mapped = ExternalToolSessionManager.applyManualRepositoryBindings(
            [session],
            manualBindings: [learnedKey: "/tmp/repo-dochi"]
        )

        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped.first?.repositoryRoot, "/tmp/repo-dochi")
    }

    func testApplyManualRepositoryBindingsUsesDeterministicTieBreakerForConflicts() {
        let session = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "codex",
            nativeSessionId: "sess-c",
            runtimeSessionId: nil,
            workingDirectory: nil,
            repositoryRoot: nil,
            path: "/tmp/.codex/sessions/2026/02/19/c.jsonl",
            updatedAt: Date(),
            isActive: true
        )
        let keyA = ExternalToolSessionManager.sessionBindingKey(
            provider: "codex",
            nativeSessionId: "sess-a",
            path: "/tmp/.codex/sessions/2026/02/19/a.jsonl"
        )
        let keyB = ExternalToolSessionManager.sessionBindingKey(
            provider: "codex",
            nativeSessionId: "sess-b",
            path: "/tmp/.codex/sessions/2026/02/19/b.jsonl"
        )

        let mapped = ExternalToolSessionManager.applyManualRepositoryBindings(
            [session],
            manualBindings: [
                keyA: "/tmp/repo-z",
                keyB: "/tmp/repo-a",
            ]
        )

        XCTAssertEqual(mapped.first?.repositoryRoot, "/tmp/repo-a")
    }

    func testApplyManualRepositoryBindingsPrefersExactMatchOverHeuristic() {
        let session = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "codex",
            nativeSessionId: "sess-exact",
            runtimeSessionId: nil,
            workingDirectory: nil,
            repositoryRoot: nil,
            path: "/tmp/.codex/sessions/2026/02/19/exact.jsonl",
            updatedAt: Date(),
            isActive: true
        )
        let exactKey = ExternalToolSessionManager.sessionBindingKey(
            provider: "codex",
            nativeSessionId: "sess-exact",
            path: "/tmp/.codex/sessions/2026/02/19/exact.jsonl"
        )
        let heuristicKey = ExternalToolSessionManager.sessionBindingKey(
            provider: "codex",
            nativeSessionId: "sess-template",
            path: "/tmp/.codex/sessions/2026/02/19/template.jsonl"
        )

        let mapped = ExternalToolSessionManager.applyManualRepositoryBindings(
            [session],
            manualBindings: [
                heuristicKey: "/tmp/repo-heuristic",
                exactKey: "/tmp/repo-exact",
            ]
        )

        XCTAssertEqual(mapped.first?.repositoryRoot, "/tmp/repo-exact")
    }

    func testApplyManualRepositoryBindingsDoesNotOverrideAssignedRepoWithoutExactMatch() {
        let session = UnifiedCodingSession(
            source: "file",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "codex",
            nativeSessionId: "sess-assigned",
            runtimeSessionId: nil,
            workingDirectory: "/tmp/repo-existing",
            repositoryRoot: "/tmp/repo-existing",
            path: "/tmp/.codex/sessions/2026/02/19/assigned.jsonl",
            updatedAt: Date(),
            isActive: true
        )
        let learnedKey = ExternalToolSessionManager.sessionBindingKey(
            provider: "codex",
            nativeSessionId: "sess-template",
            path: "/tmp/.codex/sessions/2026/02/19/template.jsonl"
        )

        let mapped = ExternalToolSessionManager.applyManualRepositoryBindings(
            [session],
            manualBindings: [learnedKey: "/tmp/repo-other"]
        )

        XCTAssertEqual(mapped.first?.repositoryRoot, "/tmp/repo-existing")
    }

    func testDisplaySessionTitleRecoversFromOpaqueUUIDTitle() {
        let session = UnifiedCodingSession(
            source: "test",
            runtimeType: .file,
            controllabilityTier: .t2Observe,
            provider: "codex",
            nativeSessionId: "019c83ec-61b9-7f12-91e1-e35a58631234",
            runtimeSessionId: nil,
            workingDirectory: "/tmp/repo-a",
            repositoryRoot: "/tmp/repo-a",
            path: "/tmp/repo-a/session.jsonl",
            updatedAt: Date(),
            isActive: true,
            title: "019c83ec-61b9-7f12-91e1-e35a58631234",
            summary: nil,
            clientKind: "desktop",
            activityScore: 78,
            activityState: .active
        )

        let displayTitle = SessionExplorerViewStateBuilder.displaySessionTitle(for: session)

        XCTAssertFalse(displayTitle.contains("019c83ec-61b9-7f12-91e1-e35a58631234"))
        XCTAssertTrue(displayTitle.contains("repo-a"))
    }

    func testSessionChangeLinePrefersWorkingTreePreview() {
        let session = makeSession(
            provider: "codex",
            nativeId: "sess-a",
            repo: "/tmp/repo-a",
            tier: .t0Full,
            state: .active,
            score: 88
        )
        let insight = makeInsight(
            path: "/tmp/repo-a",
            changedFileCount: 3,
            untrackedFileCount: 1,
            changedPathPreview: ["Sources/App.swift", "README.md", "Tests/AppTests.swift"]
        )

        let line = SessionExplorerViewStateBuilder.sessionChangeLine(session: session, insight: insight)

        XCTAssertTrue(line.contains("Sources/App.swift"))
        XCTAssertTrue(line.contains("외 1개"))
    }

    func testRepositoryCommitFeedLinesUseRecentCommitPreviews() {
        let insight = makeInsight(
            path: "/tmp/repo-a",
            changedFileCount: 0,
            untrackedFileCount: 0,
            recentCommitPreviews: [
                GitCommitPreview(shortHash: "abc1234", subject: "feat: add dashboard feed", relative: "2m ago"),
                GitCommitPreview(shortHash: "def5678", subject: "fix: session title fallback", relative: "9m ago"),
            ]
        )

        let lines = SessionExplorerViewStateBuilder.repositoryCommitFeedLines(for: insight, limit: 5)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "abc1234 feat: add dashboard feed · 2m ago")
        XCTAssertEqual(lines[1], "def5678 fix: session title fallback · 9m ago")
    }

    private func makeSession(
        provider: String,
        nativeId: String,
        repo: String?,
        tier: CodingSessionControllabilityTier = .t0Full,
        state: CodingSessionActivityState,
        score: Int,
        updatedAt: Date = Date(),
        errorPenalty: Int = 0
    ) -> UnifiedCodingSession {
        UnifiedCodingSession(
            source: "test",
            runtimeType: repo == nil ? .file : .tmux,
            controllabilityTier: tier,
            provider: provider,
            nativeSessionId: nativeId,
            runtimeSessionId: repo == nil ? nil : UUID().uuidString,
            workingDirectory: repo,
            repositoryRoot: repo,
            path: "/tmp/\(nativeId).jsonl",
            updatedAt: updatedAt,
            isActive: state == .active || state == .idle,
            activityScore: score,
            activityState: state,
            activitySignals: CodingSessionActivitySignals(
                runtimeAliveScore: 0,
                recentOutputScore: 0,
                recentCommandScore: 0,
                fileFreshnessScore: 0,
                errorPenaltyScore: errorPenalty
            )
        )
    }

    private func makeInsight(
        path: String,
        changedFileCount: Int,
        untrackedFileCount: Int,
        changedPathPreview: [String]? = nil,
        recentCommitPreviews: [GitCommitPreview]? = nil
    ) -> GitRepositoryInsight {
        GitRepositoryInsight(
            workDomain: "personal",
            workDomainConfidence: 0.9,
            workDomainReason: "test",
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            branch: "main",
            originURL: nil,
            remoteHost: nil,
            remoteOwner: nil,
            remoteRepository: nil,
            lastCommitEpoch: nil,
            lastCommitISO8601: nil,
            lastCommitRelative: "-",
            lastCommitShortHash: nil,
            lastCommitSubject: nil,
            upstreamLastCommitEpoch: nil,
            upstreamLastCommitISO8601: nil,
            upstreamLastCommitRelative: "-",
            daysSinceLastCommit: nil,
            recentCommitCount30d: 0,
            changedFileCount: changedFileCount,
            untrackedFileCount: untrackedFileCount,
            changedPathPreview: changedPathPreview,
            recentCommitPreviews: recentCommitPreviews,
            aheadCount: nil,
            behindCount: nil,
            score: 0
        )
    }
}
