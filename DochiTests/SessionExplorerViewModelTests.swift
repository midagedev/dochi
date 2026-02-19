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

