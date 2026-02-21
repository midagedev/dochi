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
        XCTAssertEqual(t2.policyCode, .t2DenyExecution)
        XCTAssertEqual(t2.commandClass, .nonDestructive)
        XCTAssertEqual(t3.kind, .denied)
        XCTAssertEqual(t3.policyCode, .t3DenyExecution)
        XCTAssertEqual(t3.commandClass, .nonDestructive)
    }

    func testExecutionGuardRequiresConfirmationForDestructiveT1Command() {
        let decision = ExternalToolSessionManager.evaluateOrchestrationExecutionGuard(
            tier: .t1Attach,
            command: "git reset --hard HEAD~1"
        )

        XCTAssertEqual(decision.kind, .confirmationRequired)
        XCTAssertEqual(decision.policyCode, .t1ConfirmDestructive)
        XCTAssertEqual(decision.commandClass, .destructive)
        XCTAssertTrue(decision.isDestructiveCommand)
    }

    func testExecutionGuardAllowsNonDestructiveT1Command() {
        let decision = ExternalToolSessionManager.evaluateOrchestrationExecutionGuard(
            tier: .t1Attach,
            command: "git status"
        )

        XCTAssertEqual(decision.kind, .allowed)
        XCTAssertEqual(decision.policyCode, .t1AllowNonDestructive)
        XCTAssertEqual(decision.commandClass, .nonDestructive)
        XCTAssertFalse(decision.isDestructiveCommand)
    }

    func testOrchestrationPolicyMatrixCoversAllTierAndCommandClasses() {
        let matrix = ExternalToolSessionManager.orchestrationGuardPolicyMatrix()
        let tiers: [CodingSessionControllabilityTier] = [.t0Full, .t1Attach, .t2Observe, .t3Unknown]
        let commandClasses: [OrchestrationCommandClass] = [.nonDestructive, .destructive]

        XCTAssertEqual(matrix.count, tiers.count * commandClasses.count)
        for tier in tiers {
            for commandClass in commandClasses {
                XCTAssertTrue(matrix.contains(where: { rule in
                    rule.tier == tier && rule.commandClass == commandClass
                }))
            }
        }
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

@MainActor
final class DochiAppOrchestratorBridgeFlowTests: XCTestCase {

    func testHandleBridgeOrchestratorExecuteReturnsSelectionAndGuardPayload() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(
            name: "Codex",
            command: "codex",
            workingDirectory: "/tmp/repo"
        )
        manager.saveProfile(profile)

        let runtimeSessionId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        manager.sessions = [
            ExternalToolSession(
                id: runtimeSessionId,
                profileId: profile.id,
                tmuxSessionName: "mock-session",
                status: .idle,
                startedAt: Date()
            ),
        ]

        manager.mockOrchestrationSelection = OrchestrationSessionSelection(
            action: .attachT1,
            reason: "attach path",
            repositoryRoot: "/tmp/repo",
            selectedSession: makeUnifiedSession(
                provider: "codex",
                nativeSessionId: "sess-a",
                runtimeSessionId: runtimeSessionId.uuidString,
                tier: .t1Attach,
                state: .active,
                repositoryRoot: "/tmp/repo"
            )
        )
        manager.mockOrchestrationDecision = OrchestrationExecutionDecision(
            kind: .allowed,
            policyCode: .t1AllowNonDestructive,
            commandClass: .nonDestructive,
            reason: "allowed",
            isDestructiveCommand: false
        )

        let result = await DochiApp.handleBridgeOrchestratorExecute(
            params: [
                "repository_root": "/tmp/repo",
                "command": "git status",
                "confirmed": true,
            ],
            externalToolManager: manager,
            orchestrationApprovalStore: OrchestrationExecutionApprovalStore()
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.result["status"] as? String, "sent")
        XCTAssertEqual(manager.sendCommandCallCount, 1)
        XCTAssertEqual(manager.lastSentCommand, "git status")

        let selection = try XCTUnwrap(result.result["selection"] as? [String: Any])
        XCTAssertEqual(selection["action"] as? String, "attach_t1")

        let guardPayload = try XCTUnwrap(result.result["guard"] as? [String: Any])
        XCTAssertEqual(guardPayload["decision"] as? String, "allowed")
        XCTAssertEqual(guardPayload["policy_code"] as? String, "policy_t1_allow_non_destructive")
    }

    func testHandleBridgeOrchestratorExecuteRequiresApprovalWithoutConfirmed() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(
            name: "Codex",
            command: "codex",
            workingDirectory: "/tmp/repo"
        )
        manager.saveProfile(profile)

        let runtimeSessionId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        manager.sessions = [
            ExternalToolSession(
                id: runtimeSessionId,
                profileId: profile.id,
                tmuxSessionName: "mock-session",
                status: .idle,
                startedAt: Date()
            ),
        ]

        manager.mockOrchestrationSelection = OrchestrationSessionSelection(
            action: .attachT1,
            reason: "attach path",
            repositoryRoot: "/tmp/repo",
            selectedSession: makeUnifiedSession(
                provider: "codex",
                nativeSessionId: "sess-approval-required",
                runtimeSessionId: runtimeSessionId.uuidString,
                tier: .t1Attach,
                state: .active,
                repositoryRoot: "/tmp/repo"
            )
        )
        manager.mockOrchestrationDecision = OrchestrationExecutionDecision(
            kind: .allowed,
            policyCode: .t1AllowNonDestructive,
            commandClass: .nonDestructive,
            reason: "allowed",
            isDestructiveCommand: false
        )

        let result = await DochiApp.handleBridgeOrchestratorExecute(
            params: [
                "repository_root": "/tmp/repo",
                "command": "git status",
            ],
            externalToolManager: manager,
            orchestrationApprovalStore: OrchestrationExecutionApprovalStore()
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorCode, "approval_required")
        XCTAssertEqual(manager.sendCommandCallCount, 0)
    }

    func testHandleBridgeOrchestratorExecuteConsumesChallengeApproval() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(
            name: "Codex",
            command: "codex",
            workingDirectory: "/tmp/repo"
        )
        manager.saveProfile(profile)

        let runtimeSessionId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        manager.sessions = [
            ExternalToolSession(
                id: runtimeSessionId,
                profileId: profile.id,
                tmuxSessionName: "mock-session",
                status: .idle,
                startedAt: Date()
            ),
        ]

        manager.mockOrchestrationSelection = OrchestrationSessionSelection(
            action: .attachT1,
            reason: "attach path",
            repositoryRoot: "/tmp/repo",
            selectedSession: makeUnifiedSession(
                provider: "codex",
                nativeSessionId: "sess-challenge",
                runtimeSessionId: runtimeSessionId.uuidString,
                tier: .t1Attach,
                state: .active,
                repositoryRoot: "/tmp/repo"
            )
        )
        manager.mockOrchestrationDecision = OrchestrationExecutionDecision(
            kind: .allowed,
            policyCode: .t1AllowNonDestructive,
            commandClass: .nonDestructive,
            reason: "allowed",
            isDestructiveCommand: false
        )

        let approvalStore = OrchestrationExecutionApprovalStore()
        let challenge = await approvalStore.create(
            command: "git status",
            repositoryRoot: "/tmp/repo",
            ttlSeconds: 120
        )
        _ = await approvalStore.approve(
            approvalId: challenge.snapshot.approvalId,
            challengeCode: challenge.snapshot.challengeCode
        )

        let firstResult = await DochiApp.handleBridgeOrchestratorExecute(
            params: [
                "repository_root": "/tmp/repo",
                "command": "git status",
                "approval_id": challenge.snapshot.approvalId,
            ],
            externalToolManager: manager,
            orchestrationApprovalStore: approvalStore
        )

        XCTAssertTrue(firstResult.success)
        XCTAssertEqual(manager.sendCommandCallCount, 1)
        let approval = try XCTUnwrap(firstResult.result["approval"] as? [String: Any])
        XCTAssertEqual(approval["mode"] as? String, "challenge")
        XCTAssertEqual(approval["status"] as? String, "consumed")

        let secondResult = await DochiApp.handleBridgeOrchestratorExecute(
            params: [
                "repository_root": "/tmp/repo",
                "command": "git status",
                "approval_id": challenge.snapshot.approvalId,
            ],
            externalToolManager: manager,
            orchestrationApprovalStore: approvalStore
        )

        XCTAssertFalse(secondResult.success)
        XCTAssertEqual(secondResult.errorCode, "approval_already_consumed")
        XCTAssertEqual(manager.sendCommandCallCount, 1)
    }

    func testHandleBridgeOrchestratorStatusBuildsSummaryContract() async throws {
        let manager = MockExternalToolSessionManager()
        let profile = ExternalToolProfile(
            name: "Codex",
            command: "codex",
            workingDirectory: "/tmp/repo"
        )
        manager.saveProfile(profile)

        let runtimeSessionId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        manager.sessions = [
            ExternalToolSession(
                id: runtimeSessionId,
                profileId: profile.id,
                tmuxSessionName: "mock-session",
                status: .busy,
                startedAt: Date()
            ),
        ]

        manager.mockOrchestrationSelection = OrchestrationSessionSelection(
            action: .reuseT0Active,
            reason: "reuse active",
            repositoryRoot: "/tmp/repo",
            selectedSession: makeUnifiedSession(
                provider: "codex",
                nativeSessionId: "sess-b",
                runtimeSessionId: runtimeSessionId.uuidString,
                tier: .t0Full,
                state: .active,
                repositoryRoot: "/tmp/repo"
            )
        )
        manager.mockOutputLines = [
            "Compiling modules...",
            "Build failed: 2 errors",
            "error: test failed",
        ]

        let result = await DochiApp.handleBridgeOrchestratorStatus(
            params: [
                "repository_root": "/tmp/repo",
                "lines": 80,
            ],
            externalToolManager: manager,
            orchestrationSummaryService: OrchestrationSummaryService()
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.result["result_kind"] as? String, "failed")
        XCTAssertEqual(result.result["line_count"] as? Int, 3)

        let summary = result.result["summary"] as? String
        XCTAssertTrue(summary?.contains("실패") == true)

        let highlights = result.result["highlights"] as? [String]
        XCTAssertFalse((highlights ?? []).isEmpty)

        let sessionPayload = try XCTUnwrap(result.result["session"] as? [String: Any])
        XCTAssertEqual(sessionPayload["session_id"] as? String, runtimeSessionId.uuidString)
    }

    func testHandleBridgeSessionMetricsIncludesRequiredKPIFields() async throws {
        let manager = MockExternalToolSessionManager()
        manager.mockSessionManagementKPIReport = SessionManagementKPIReport(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            repositoryAssignmentSuccessRate: 0.75,
            dedupCorrectionRate: 0.2,
            activityClassificationAccuracy: 0.5,
            sessionSelectionFailureRate: 0.25,
            historySearchHitRate: 0.6,
            clientKindUnknownRate: 0.25,
            counters: SessionManagementKPICounters(
                repositoryAssignedCount: 3,
                repositoryTotalCount: 4,
                dedupCandidateCount: 10,
                dedupCorrectionCount: 2,
                selectionAttemptCount: 8,
                selectionFailureCount: 2,
                historySearchQueryCount: 5,
                historySearchHitCount: 3,
                activityFeedbackSampleCount: 4,
                activityFeedbackMatchedCount: 2,
                activityStateDistribution: ["active": 2],
                clientKindSampleCount: 4,
                clientKindUnknownCount: 1,
                clientKindDistribution: ["desktop": 1, "cli": 2, "unknown": 1]
            )
        )

        let result = await DochiApp.handleBridgeSessionMetrics(params: [:], externalToolManager: manager)

        XCTAssertTrue(result.success)
        let metrics = try XCTUnwrap(result.result["metrics"] as? [String: Any])
        XCTAssertEqual(metrics["repository_assignment_success_rate"] as? Double, 0.75)
        XCTAssertEqual(metrics["session_selection_failure_rate"] as? Double, 0.25)
        XCTAssertEqual(metrics["history_search_hit_rate"] as? Double, 0.6)
        XCTAssertEqual(metrics["client_kind_unknown_rate"] as? Double, 0.25)

        let summary = result.result["summary"] as? String
        XCTAssertTrue(summary?.contains("selection_failure_rate") == true)
        XCTAssertTrue(summary?.contains("history_search_hit_rate") == true)
    }

    private func makeUnifiedSession(
        provider: String,
        nativeSessionId: String,
        runtimeSessionId: String?,
        tier: CodingSessionControllabilityTier,
        state: CodingSessionActivityState,
        repositoryRoot: String?
    ) -> UnifiedCodingSession {
        UnifiedCodingSession(
            source: "test",
            runtimeType: runtimeSessionId == nil ? .file : .tmux,
            controllabilityTier: tier,
            provider: provider,
            nativeSessionId: nativeSessionId,
            runtimeSessionId: runtimeSessionId,
            workingDirectory: repositoryRoot,
            repositoryRoot: repositoryRoot,
            path: "/tmp/\(nativeSessionId).jsonl",
            updatedAt: Date(),
            isActive: state == .active || state == .idle,
            activityScore: 90,
            activityState: state
        )
    }
}
