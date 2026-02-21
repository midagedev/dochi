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
}
