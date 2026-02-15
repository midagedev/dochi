import XCTest
@testable import Dochi

@MainActor
final class DelegationTests: XCTestCase {

    // MARK: - DelegationPolicy Tests

    func testDefaultDelegationPolicy() {
        let policy = DelegationPolicy.default
        XCTAssertTrue(policy.canDelegate)
        XCTAssertTrue(policy.canReceiveDelegation)
        XCTAssertNil(policy.allowedTargets)
        XCTAssertNil(policy.blockedTargets)
        XCTAssertEqual(policy.maxChainDepth, 3)
    }

    func testDelegationPolicyAllowsDelegationByDefault() {
        let policy = DelegationPolicy.default
        XCTAssertTrue(policy.allowsDelegationTo("anyAgent"))
    }

    func testDelegationPolicyBlocksWhenCanDelegateIsFalse() {
        let policy = DelegationPolicy(canDelegate: false)
        XCTAssertFalse(policy.allowsDelegationTo("anyAgent"))
    }

    func testDelegationPolicyAllowedTargets() {
        let policy = DelegationPolicy(allowedTargets: ["Alice", "Bob"])
        XCTAssertTrue(policy.allowsDelegationTo("Alice"))
        XCTAssertTrue(policy.allowsDelegationTo("Bob"))
        XCTAssertFalse(policy.allowsDelegationTo("Charlie"))
    }

    func testDelegationPolicyAllowedTargetsCaseInsensitive() {
        let policy = DelegationPolicy(allowedTargets: ["Alice"])
        XCTAssertTrue(policy.allowsDelegationTo("alice"))
        XCTAssertTrue(policy.allowsDelegationTo("ALICE"))
    }

    func testDelegationPolicyBlockedTargets() {
        let policy = DelegationPolicy(blockedTargets: ["Blocked"])
        XCTAssertFalse(policy.allowsDelegationTo("Blocked"))
        XCTAssertTrue(policy.allowsDelegationTo("NotBlocked"))
    }

    func testDelegationPolicyBlockedTargetsCaseInsensitive() {
        let policy = DelegationPolicy(blockedTargets: ["blocked"])
        XCTAssertFalse(policy.allowsDelegationTo("Blocked"))
        XCTAssertFalse(policy.allowsDelegationTo("BLOCKED"))
    }

    func testDelegationPolicyBlockedOverridesAllowed() {
        // If both are set, blocked should take precedence
        let policy = DelegationPolicy(allowedTargets: ["Alice"], blockedTargets: ["Alice"])
        XCTAssertFalse(policy.allowsDelegationTo("Alice"))
    }

    func testDelegationPolicyCodable() throws {
        let policy = DelegationPolicy(
            canDelegate: true,
            canReceiveDelegation: false,
            allowedTargets: ["A"],
            blockedTargets: ["B"],
            maxChainDepth: 5
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(policy)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DelegationPolicy.self, from: data)
        XCTAssertEqual(policy, decoded)
    }

    // MARK: - DelegationTask Tests

    func testDelegationTaskInitDefaults() {
        let task = DelegationTask(
            originAgentName: "A",
            targetAgentName: "B",
            task: "Do something"
        )
        XCTAssertEqual(task.status, .pending)
        XCTAssertNil(task.startedAt)
        XCTAssertNil(task.completedAt)
        XCTAssertNil(task.result)
        XCTAssertNil(task.errorMessage)
        XCTAssertEqual(task.chainDepth, 0)
        XCTAssertNil(task.durationSeconds)
    }

    func testDelegationTaskDuration() throws {
        let start = Date()
        let end = start.addingTimeInterval(5.0)
        let task = DelegationTask(
            originAgentName: "A",
            targetAgentName: "B",
            task: "Test",
            status: .completed,
            startedAt: start,
            completedAt: end
        )
        let duration = try XCTUnwrap(task.durationSeconds)
        XCTAssertEqual(duration, 5.0, accuracy: 0.01)
    }

    func testDelegationTaskDurationNilWhenNotComplete() {
        let task = DelegationTask(
            originAgentName: "A",
            targetAgentName: "B",
            task: "Test",
            status: .running,
            startedAt: Date()
        )
        XCTAssertNil(task.durationSeconds)
    }

    func testDelegationTaskCodable() throws {
        let task = DelegationTask(
            originAgentName: "A",
            targetAgentName: "B",
            task: "Do something",
            context: "extra info",
            status: .completed,
            result: "Done"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(task)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DelegationTask.self, from: data)
        XCTAssertEqual(decoded.originAgentName, "A")
        XCTAssertEqual(decoded.targetAgentName, "B")
        XCTAssertEqual(decoded.task, "Do something")
        XCTAssertEqual(decoded.context, "extra info")
        XCTAssertEqual(decoded.status, .completed)
    }

    // MARK: - DelegationChain Tests

    func testEmptyChainIsComplete() {
        let chain = DelegationChain()
        XCTAssertTrue(chain.isComplete)
        XCTAssertFalse(chain.hasError)
        XCTAssertEqual(chain.currentDepth, 0)
        XCTAssertTrue(chain.involvedAgents.isEmpty)
    }

    func testChainCurrentDepth() {
        let tasks = [
            DelegationTask(originAgentName: "A", targetAgentName: "B", task: "t1", chainDepth: 1),
            DelegationTask(originAgentName: "B", targetAgentName: "C", task: "t2", chainDepth: 2),
        ]
        let chain = DelegationChain(tasks: tasks)
        XCTAssertEqual(chain.currentDepth, 2)
    }

    func testChainIsNotCompleteWithRunningTasks() {
        let tasks = [
            DelegationTask(originAgentName: "A", targetAgentName: "B", task: "t1", status: .completed, chainDepth: 1),
            DelegationTask(originAgentName: "B", targetAgentName: "C", task: "t2", status: .running, chainDepth: 2),
        ]
        let chain = DelegationChain(tasks: tasks)
        XCTAssertFalse(chain.isComplete)
    }

    func testChainIsCompleteWhenAllDone() {
        let tasks = [
            DelegationTask(originAgentName: "A", targetAgentName: "B", task: "t1", status: .completed, chainDepth: 1),
            DelegationTask(originAgentName: "B", targetAgentName: "C", task: "t2", status: .failed, chainDepth: 2),
        ]
        let chain = DelegationChain(tasks: tasks)
        XCTAssertTrue(chain.isComplete)
        XCTAssertTrue(chain.hasError)
    }

    func testChainInvolvedAgents() {
        let tasks = [
            DelegationTask(originAgentName: "A", targetAgentName: "B", task: "t1", chainDepth: 1),
            DelegationTask(originAgentName: "B", targetAgentName: "C", task: "t2", chainDepth: 2),
        ]
        let chain = DelegationChain(tasks: tasks)
        XCTAssertEqual(chain.involvedAgents, ["A", "B", "C"])
    }

    func testChainWouldCreateCycleDetected() {
        let tasks = [
            DelegationTask(originAgentName: "A", targetAgentName: "B", task: "t1", chainDepth: 1),
            DelegationTask(originAgentName: "B", targetAgentName: "C", task: "t2", chainDepth: 2),
        ]
        let chain = DelegationChain(tasks: tasks)
        // Trying to delegate back to A (who is an origin) would create a cycle
        XCTAssertTrue(chain.wouldCreateCycle(targetAgent: "A"))
    }

    func testChainWouldNotCreateCycleForNewAgent() {
        let tasks = [
            DelegationTask(originAgentName: "A", targetAgentName: "B", task: "t1", chainDepth: 1),
        ]
        let chain = DelegationChain(tasks: tasks)
        // D is not in the chain, no cycle
        XCTAssertFalse(chain.wouldCreateCycle(targetAgent: "D"))
    }

    // MARK: - DelegationManager Tests

    func testDelegationManagerStartDelegation() {
        let manager = DelegationManager()
        let task = DelegationTask(originAgentName: "A", targetAgentName: "B", task: "test")
        manager.startDelegation(task)

        XCTAssertEqual(manager.activeDelegations.count, 1)
        XCTAssertEqual(manager.activeDelegations.first?.status, .running)
        XCTAssertNotNil(manager.activeDelegations.first?.startedAt)
        XCTAssertNotNil(manager.currentChain)
    }

    func testDelegationManagerCompleteDelegation() {
        let manager = DelegationManager()
        let task = DelegationTask(originAgentName: "A", targetAgentName: "B", task: "test")
        manager.startDelegation(task)

        manager.completeDelegation(id: task.id, result: "Done")

        XCTAssertEqual(manager.activeDelegations.count, 0)
        XCTAssertEqual(manager.recentDelegations.count, 1)
        XCTAssertEqual(manager.recentDelegations.first?.status, .completed)
        XCTAssertEqual(manager.recentDelegations.first?.result, "Done")
    }

    func testDelegationManagerFailDelegation() {
        let manager = DelegationManager()
        let task = DelegationTask(originAgentName: "A", targetAgentName: "B", task: "test")
        manager.startDelegation(task)

        manager.failDelegation(id: task.id, error: "Something went wrong")

        XCTAssertEqual(manager.activeDelegations.count, 0)
        XCTAssertEqual(manager.recentDelegations.count, 1)
        XCTAssertEqual(manager.recentDelegations.first?.status, .failed)
        XCTAssertEqual(manager.recentDelegations.first?.errorMessage, "Something went wrong")
    }

    func testDelegationManagerCancelDelegation() {
        let manager = DelegationManager()
        let task = DelegationTask(originAgentName: "A", targetAgentName: "B", task: "test")
        manager.startDelegation(task)

        manager.cancelDelegation(id: task.id)

        XCTAssertEqual(manager.activeDelegations.count, 0)
        XCTAssertEqual(manager.recentDelegations.count, 1)
        XCTAssertEqual(manager.recentDelegations.first?.status, .cancelled)
    }

    func testDelegationManagerChainClearedOnComplete() {
        let manager = DelegationManager()
        let task = DelegationTask(originAgentName: "A", targetAgentName: "B", task: "test")
        manager.startDelegation(task)

        XCTAssertNotNil(manager.currentChain)

        manager.completeDelegation(id: task.id, result: "Done")

        XCTAssertNil(manager.currentChain)
    }

    func testDelegationManagerStatusSummaryEmpty() {
        let manager = DelegationManager()
        let summary = manager.statusSummary()
        XCTAssertTrue(summary.contains("진행 중인 위임이 없습니다"))
    }

    func testDelegationManagerStatusSummaryWithActive() {
        let manager = DelegationManager()
        let task = DelegationTask(originAgentName: "A", targetAgentName: "B", task: "analyze data")
        manager.startDelegation(task)

        let summary = manager.statusSummary()
        XCTAssertTrue(summary.contains("진행 중"))
        XCTAssertTrue(summary.contains("A"))
        XCTAssertTrue(summary.contains("B"))
    }

    func testDelegationManagerStatusSummaryForSpecificId() {
        let manager = DelegationManager()
        let task = DelegationTask(originAgentName: "A", targetAgentName: "B", task: "test task")
        manager.startDelegation(task)
        manager.completeDelegation(id: task.id, result: "result text")

        let summary = manager.statusSummary(delegationId: task.id)
        XCTAssertTrue(summary.contains("completed"))
        XCTAssertTrue(summary.contains("test task"))
    }

    func testDelegationManagerStatusSummaryForUnknownId() {
        let manager = DelegationManager()
        let unknownId = UUID()
        let summary = manager.statusSummary(delegationId: unknownId)
        XCTAssertTrue(summary.contains("찾을 수 없습니다"))
    }

    // MARK: - AgentConfig Delegation Policy Tests

    func testAgentConfigEffectiveDelegationPolicyDefault() {
        let config = AgentConfig(name: "test")
        let policy = config.effectiveDelegationPolicy
        XCTAssertTrue(policy.canDelegate)
        XCTAssertTrue(policy.canReceiveDelegation)
        XCTAssertEqual(policy.maxChainDepth, 3)
    }

    func testAgentConfigDelegationPolicyCodable() throws {
        let config = AgentConfig(
            name: "test",
            delegationPolicy: DelegationPolicy(
                canDelegate: false,
                canReceiveDelegation: true,
                maxChainDepth: 5
            )
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentConfig.self, from: data)
        XCTAssertEqual(decoded.effectiveDelegationPolicy.canDelegate, false)
        XCTAssertEqual(decoded.effectiveDelegationPolicy.canReceiveDelegation, true)
        XCTAssertEqual(decoded.effectiveDelegationPolicy.maxChainDepth, 5)
    }

    func testAgentConfigBackwardCompatibleDecoding() throws {
        // JSON without delegationPolicy field should decode successfully
        let json = """
        {
            "name": "legacy-agent",
            "wakeWord": "hello",
            "permissions": ["safe", "sensitive"]
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(AgentConfig.self, from: data)
        XCTAssertEqual(config.name, "legacy-agent")
        XCTAssertNil(config.delegationPolicy)
        XCTAssertTrue(config.effectiveDelegationPolicy.canDelegate)
    }

    // MARK: - DelegationStatus Tests

    func testDelegationStatusRawValues() {
        XCTAssertEqual(DelegationStatus.pending.rawValue, "pending")
        XCTAssertEqual(DelegationStatus.running.rawValue, "running")
        XCTAssertEqual(DelegationStatus.completed.rawValue, "completed")
        XCTAssertEqual(DelegationStatus.failed.rawValue, "failed")
        XCTAssertEqual(DelegationStatus.cancelled.rawValue, "cancelled")
    }

    // MARK: - DelegationError Tests

    func testDelegationErrorDescriptions() {
        XCTAssertNotNil(DelegationError.timeout(seconds: 30).errorDescription)
        XCTAssertNotNil(DelegationError.notEnabled.errorDescription)
        XCTAssertNotNil(DelegationError.agentNotFound("X").errorDescription)
        XCTAssertNotNil(DelegationError.policyDenied("reason").errorDescription)
        XCTAssertNotNil(DelegationError.cyclicDelegation("A").errorDescription)
        XCTAssertNotNil(DelegationError.maxDepthExceeded(3).errorDescription)
    }

    // MARK: - AppSettings Delegation Tests

    func testAppSettingsDelegationCanBeSetAndRead() {
        let settings = AppSettings()
        settings.delegationEnabled = true
        XCTAssertTrue(settings.delegationEnabled)
        settings.delegationEnabled = false
        XCTAssertFalse(settings.delegationEnabled)

        settings.delegationMaxChainDepth = 5
        XCTAssertEqual(settings.delegationMaxChainDepth, 5)

        settings.delegationDefaultTimeoutSeconds = 60
        XCTAssertEqual(settings.delegationDefaultTimeoutSeconds, 60)

        // Restore defaults
        settings.delegationEnabled = true
        settings.delegationMaxChainDepth = 3
        settings.delegationDefaultTimeoutSeconds = 120
    }

    // MARK: - AgentDelegateTaskTool Validation Tests

    func testDelegateTaskToolRejectsEmptyAgentName() async {
        let tool = createDelegateTool()
        let result = await tool.execute(arguments: ["agent_name": "", "task": "do something"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("agent_name"))
    }

    func testDelegateTaskToolRejectsEmptyTask() async {
        let tool = createDelegateTool()
        let result = await tool.execute(arguments: ["agent_name": "TestAgent", "task": ""])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("task"))
    }

    func testDelegateTaskToolRejectsWhenDisabled() async {
        let settings = AppSettings()
        settings.delegationEnabled = false
        let tool = createDelegateTool(settings: settings)
        let result = await tool.execute(arguments: ["agent_name": "TestAgent", "task": "do something"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("비활성화"))
    }

    func testDelegateTaskToolRejectsUnknownAgent() async {
        let contextService = MockContextService()
        let settings = AppSettings()
        settings.delegationEnabled = true
        let tool = createDelegateTool(contextService: contextService, settings: settings)
        let result = await tool.execute(arguments: ["agent_name": "Unknown", "task": "do something"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("찾을 수 없습니다"))
    }

    // MARK: - AgentDelegationStatusTool Tests

    func testDelegationStatusToolEmptyManager() async {
        let manager = DelegationManager()
        let tool = AgentDelegationStatusTool(delegationManager: manager)
        let result = await tool.execute(arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("진행 중인 위임이 없습니다"))
    }

    func testDelegationStatusToolWithActiveDelegation() async {
        let manager = DelegationManager()
        let task = DelegationTask(originAgentName: "A", targetAgentName: "B", task: "test")
        manager.startDelegation(task)

        let tool = AgentDelegationStatusTool(delegationManager: manager)
        let result = await tool.execute(arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("진행 중"))
    }

    func testDelegationStatusToolNilManager() async {
        let tool = AgentDelegationStatusTool(delegationManager: nil)
        let result = await tool.execute(arguments: [:])
        XCTAssertTrue(result.isError)
    }

    // MARK: - DelegationResult Tests

    func testDelegationResultProperties() {
        let result = DelegationResult(
            delegationId: UUID(),
            targetAgentName: "B",
            success: true,
            response: "Done",
            tokensUsed: 100,
            duration: 2.5,
            subDelegations: nil
        )
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.response, "Done")
        XCTAssertEqual(result.tokensUsed, 100)
        XCTAssertEqual(result.duration, 2.5, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func createDelegateTool(
        contextService: MockContextService? = nil,
        settings: AppSettings? = nil
    ) -> AgentDelegateTaskTool {
        let ctx = contextService ?? MockContextService()
        let wsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let sessionContext = SessionContext(workspaceId: wsId)
        let appSettings = settings ?? AppSettings()
        return AgentDelegateTaskTool(
            contextService: ctx,
            sessionContext: sessionContext,
            settings: appSettings
        )
    }
}
