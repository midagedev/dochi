import XCTest
@testable import Dochi

final class OrchestratorSessionSelectorTests: XCTestCase {

    func testSelectorPrefersT0ActiveWithinRepository() {
        let repo = "/tmp/repo-a"
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "t1",
                runtimeId: "11111111-1111-1111-1111-111111111111",
                tier: .t1Attach,
                state: .active,
                repo: repo,
                score: 84
            ),
            makeSession(
                provider: "codex",
                nativeId: "t0",
                runtimeId: "22222222-2222-2222-2222-222222222222",
                tier: .t0Full,
                state: .active,
                repo: repo,
                score: 78
            ),
        ]

        let selected = ExternalToolSessionManager.selectSessionForOrchestration(
            sessions: sessions,
            repositoryRoot: repo
        )

        XCTAssertEqual(selected.action, .reuseT0Active)
        XCTAssertEqual(selected.selectedSession?.nativeSessionId, "t0")
    }

    func testSelectorFallsBackToT1WhenNoT0Active() {
        let repo = "/tmp/repo-a"
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "t0-idle",
                runtimeId: "33333333-3333-3333-3333-333333333333",
                tier: .t0Full,
                state: .idle,
                repo: repo,
                score: 60
            ),
            makeSession(
                provider: "codex",
                nativeId: "t1-active",
                runtimeId: "44444444-4444-4444-4444-444444444444",
                tier: .t1Attach,
                state: .active,
                repo: repo,
                score: 55
            ),
        ]

        let selected = ExternalToolSessionManager.selectSessionForOrchestration(
            sessions: sessions,
            repositoryRoot: repo
        )

        XCTAssertEqual(selected.action, .attachT1)
        XCTAssertEqual(selected.selectedSession?.nativeSessionId, "t1-active")
    }

    func testSelectorReturnsCreateT0WhenNoRunnableSessionInRepo() {
        let repo = "/tmp/repo-a"
        let sessions = [
            makeSession(
                provider: "codex",
                nativeId: "observe-only",
                runtimeId: nil,
                tier: .t2Observe,
                state: .active,
                repo: repo,
                score: 45
            ),
        ]

        let selected = ExternalToolSessionManager.selectSessionForOrchestration(
            sessions: sessions,
            repositoryRoot: repo
        )

        XCTAssertEqual(selected.action, .createT0)
        XCTAssertNil(selected.selectedSession)
    }

    func testSelectorFallsBackToAnalyzeOnlyWithoutRepoContext() {
        let sessions = [
            makeSession(
                provider: "claude",
                nativeId: "observe-1",
                runtimeId: nil,
                tier: .t2Observe,
                state: .active,
                repo: nil,
                score: 39
            ),
        ]

        let selected = ExternalToolSessionManager.selectSessionForOrchestration(
            sessions: sessions,
            repositoryRoot: nil
        )

        XCTAssertEqual(selected.action, .analyzeOnly)
        XCTAssertEqual(selected.selectedSession?.nativeSessionId, "observe-1")
    }

    func testExecutionGuardDeniesT2AndT3() {
        let t2 = ExternalToolSessionManager.evaluateOrchestrationExecutionGuard(
            tier: .t2Observe,
            command: "git status"
        )
        let t3 = ExternalToolSessionManager.evaluateOrchestrationExecutionGuard(
            tier: .t3Unknown,
            command: "make build"
        )

        XCTAssertEqual(t2.kind, .denied)
        XCTAssertEqual(t3.kind, .denied)
    }

    func testExecutionGuardRequiresConfirmationForDestructiveT1Command() {
        let decision = ExternalToolSessionManager.evaluateOrchestrationExecutionGuard(
            tier: .t1Attach,
            command: "git reset --hard HEAD~1"
        )

        XCTAssertEqual(decision.kind, .confirmationRequired)
        XCTAssertTrue(decision.isDestructiveCommand)
    }

    func testExecutionGuardAllowsNonDestructiveT1Command() {
        let decision = ExternalToolSessionManager.evaluateOrchestrationExecutionGuard(
            tier: .t1Attach,
            command: "git status"
        )

        XCTAssertEqual(decision.kind, .allowed)
        XCTAssertFalse(decision.isDestructiveCommand)
    }

    private func makeSession(
        provider: String,
        nativeId: String,
        runtimeId: String?,
        tier: CodingSessionControllabilityTier,
        state: CodingSessionActivityState,
        repo: String?,
        score: Int
    ) -> UnifiedCodingSession {
        UnifiedCodingSession(
            source: "test",
            runtimeType: runtimeId == nil ? .file : .tmux,
            controllabilityTier: tier,
            provider: provider,
            nativeSessionId: nativeId,
            runtimeSessionId: runtimeId,
            workingDirectory: repo,
            repositoryRoot: repo,
            path: "/tmp/\(nativeId).jsonl",
            updatedAt: Date(),
            isActive: state == .active || state == .idle,
            activityScore: score,
            activityState: state
        )
    }
}

