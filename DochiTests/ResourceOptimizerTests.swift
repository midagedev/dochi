import XCTest
@testable import Dochi

@MainActor
final class ResourceOptimizerTests: XCTestCase {

    private var tempDir: URL!
    private var service: ResourceOptimizerService!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let emptyClaude = tempDir.appendingPathComponent("empty-claude")
        let emptyCodex = tempDir.appendingPathComponent("empty-codex")
        try FileManager.default.createDirectory(at: emptyClaude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyCodex, withIntermediateDirectories: true)
        service = ResourceOptimizerService(
            baseURL: tempDir,
            usageStore: nil,
            claudeProjectsRoots: [emptyClaude],
            codexSessionsRoots: [emptyCodex]
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Subscription CRUD

    func testAddSubscription() async {
        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 15,
            monthlyCostUSD: 20.0
        )

        await service.addSubscription(plan)
        XCTAssertEqual(service.subscriptions.count, 1)
        XCTAssertEqual(service.subscriptions.first?.providerName, "OpenAI")
        XCTAssertEqual(service.subscriptions.first?.planName, "Pro")
        XCTAssertEqual(service.subscriptions.first?.monthlyTokenLimit, 1_000_000)
        XCTAssertEqual(service.subscriptions.first?.resetDayOfMonth, 15)
        XCTAssertEqual(service.subscriptions.first?.monthlyCostUSD, 20.0)
    }

    func testUpdateSubscription() async {
        var plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            monthlyTokenLimit: 1_000_000
        )
        await service.addSubscription(plan)

        plan.planName = "Enterprise"
        plan.monthlyTokenLimit = 5_000_000
        await service.updateSubscription(plan)

        XCTAssertEqual(service.subscriptions.count, 1)
        XCTAssertEqual(service.subscriptions.first?.planName, "Enterprise")
        XCTAssertEqual(service.subscriptions.first?.monthlyTokenLimit, 5_000_000)
    }

    func testDeleteSubscription() async {
        let plan = SubscriptionPlan(providerName: "OpenAI", planName: "Pro")
        await service.addSubscription(plan)
        XCTAssertEqual(service.subscriptions.count, 1)

        await service.deleteSubscription(id: plan.id)
        XCTAssertEqual(service.subscriptions.count, 0)
    }

    func testDeleteSubscriptionAlsoRemovesAutoTaskRecords() async {
        let plan = SubscriptionPlan(providerName: "OpenAI", planName: "Pro")
        await service.addSubscription(plan)
        await service.queueAutoTask(type: .research, subscriptionId: plan.id)
        XCTAssertEqual(service.autoTaskRecords.count, 1)

        await service.deleteSubscription(id: plan.id)
        XCTAssertEqual(service.autoTaskRecords.count, 0)
    }

    // MARK: - Persistence

    func testPersistenceRoundtrip() async {
        let plan = SubscriptionPlan(
            providerName: "Anthropic",
            planName: "Team",
            monthlyTokenLimit: 2_000_000,
            resetDayOfMonth: 1,
            monthlyCostUSD: 30.0
        )
        await service.addSubscription(plan)
        await service.queueAutoTask(type: .memoryCleanup, subscriptionId: plan.id)

        // Create new service from same directory
        let service2 = ResourceOptimizerService(baseURL: tempDir, usageStore: nil)
        XCTAssertEqual(service2.subscriptions.count, 1)
        XCTAssertEqual(service2.subscriptions.first?.providerName, "Anthropic")
        XCTAssertEqual(service2.subscriptions.first?.planName, "Team")
        XCTAssertEqual(service2.subscriptions.first?.monthlyTokenLimit, 2_000_000)
        XCTAssertEqual(service2.autoTaskRecords.count, 1)
        XCTAssertEqual(service2.autoTaskRecords.first?.taskType, .memoryCleanup)
    }

    func testLoadFromEmptyDirectory() async {
        // Service should start with empty arrays when no file exists
        let emptyDir = tempDir.appendingPathComponent("empty")
        try? FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        let svc = ResourceOptimizerService(baseURL: emptyDir, usageStore: nil)
        XCTAssertTrue(svc.subscriptions.isEmpty)
        XCTAssertTrue(svc.autoTaskRecords.isEmpty)
    }

    // MARK: - Risk Level Calculation

    func testRiskLevelComfortable() async {
        let level = service.calculateRiskLevel(usageRatio: 0.3, remainingRatio: 0.6)
        XCTAssertEqual(level, .comfortable)
    }

    func testRiskLevelCaution() async {
        let level = service.calculateRiskLevel(usageRatio: 0.2, remainingRatio: 0.2)
        XCTAssertEqual(level, .caution)
    }

    func testRiskLevelWasteRisk() async {
        let level = service.calculateRiskLevel(usageRatio: 0.1, remainingRatio: 0.1)
        XCTAssertEqual(level, .wasteRisk)
    }

    func testRiskLevelNormal() async {
        let level = service.calculateRiskLevel(usageRatio: 0.7, remainingRatio: 0.3)
        XCTAssertEqual(level, .normal)
    }

    func testRiskLevelWasteRiskPriority() async {
        // wasteRisk should take priority: usageRatio < 0.5 && remainingRatio < 0.15
        let level = service.calculateRiskLevel(usageRatio: 0.2, remainingRatio: 0.1)
        XCTAssertEqual(level, .wasteRisk)
    }

    func testRiskLevelUsesProjectedSignal() async {
        let level = service.calculateRiskLevel(
            usageRatio: 0.45,
            remainingRatio: 0.2,
            projectedUsageRatio: 0.55,
            reserveBufferRatio: 0.08
        )
        XCTAssertEqual(level, .caution)
    }

    func testRiskLevelProjectedSignalRespectsReserveBuffer() async {
        let level = service.calculateRiskLevel(
            usageRatio: 0.45,
            remainingRatio: 0.2,
            projectedUsageRatio: 0.55,
            reserveBufferRatio: 0.5
        )
        XCTAssertEqual(level, .normal)
    }

    // MARK: - Auto Task Queue

    func testQueueAutoTask() async {
        let plan = SubscriptionPlan(providerName: "OpenAI", planName: "Pro")
        await service.addSubscription(plan)

        await service.queueAutoTask(type: .research, subscriptionId: plan.id)
        XCTAssertEqual(service.autoTaskRecords.count, 1)
        XCTAssertEqual(service.autoTaskRecords.first?.taskType, .research)
        XCTAssertEqual(service.autoTaskRecords.first?.subscriptionId, plan.id)
    }

    func testAutoTaskQueueFIFO() async {
        let plan = SubscriptionPlan(providerName: "OpenAI", planName: "Pro")
        await service.addSubscription(plan)

        // Add more than 100 records
        for _ in 0..<105 {
            await service.queueAutoTask(type: .research, subscriptionId: plan.id)
        }
        XCTAssertEqual(service.autoTaskRecords.count, 100)
    }

    func testEvaluateAndQueueAutoTasksQueuesEnabledTypes() async {
        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        await service.addSubscription(plan)

        let queued = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.research, .kanbanCleanup],
            onlyWasteRisk: false
        )

        XCTAssertEqual(queued, 2)
        XCTAssertEqual(service.autoTaskRecords.count, 2)
        XCTAssertEqual(service.autoTaskRecords.map(\.taskType), [.research, .kanbanCleanup])
    }

    func testEvaluateAndQueueAutoTasksRespectsOnlyWasteRisk() async {
        let calendar = Calendar.current
        let todayDay = calendar.component(.day, from: Date())
        let normalResetDay = min(max(todayDay, 1), 28)
        let wasteRiskResetDay = todayDay < 28 ? todayDay + 1 : 1

        let normalPlan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Normal",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: normalResetDay
        )
        let wasteRiskPlan = SubscriptionPlan(
            providerName: "Anthropic",
            planName: "Near reset",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: wasteRiskResetDay
        )

        await service.addSubscription(normalPlan)
        await service.addSubscription(wasteRiskPlan)

        let queued = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.research],
            onlyWasteRisk: true
        )

        XCTAssertEqual(queued, 1)
        XCTAssertEqual(service.autoTaskRecords.count, 1)
        XCTAssertEqual(service.autoTaskRecords.first?.subscriptionId, wasteRiskPlan.id)
    }

    func testEvaluateAndQueueAutoTasksAvoidsSameDayDuplicates() async {
        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        await service.addSubscription(plan)

        let firstRun = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.research],
            onlyWasteRisk: false
        )
        let secondRun = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.research],
            onlyWasteRisk: false
        )

        XCTAssertEqual(firstRun, 1)
        XCTAssertEqual(secondRun, 0)
        XCTAssertEqual(service.autoTaskRecords.count, 1)
    }

    func testEvaluateAndQueueAutoTasksQueuesGitScanReviewWhenDiffExists() async throws {
        let repoURL = try makeGitRepository(name: "git-scan-repo")
        let changed = repoURL.appendingPathComponent("notes.md")
        try "hello\nworld\n".write(to: changed, atomically: true, encoding: .utf8)

        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        await service.addSubscription(plan)

        let queued = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.gitScanReview],
            onlyWasteRisk: false,
            gitInsights: [sampleInsight(path: repoURL.path)]
        )

        XCTAssertEqual(queued, 1)
        XCTAssertEqual(service.autoTaskRecords.count, 1)
        XCTAssertEqual(service.autoTaskRecords.first?.taskType, .gitScanReview)
        XCTAssertNotNil(service.autoTaskRecords.first?.dedupeKey)
        XCTAssertTrue(service.autoTaskRecords.first?.summary.contains("git-scan-repo") == true)
    }

    func testEvaluateAndQueueAutoTasksDedupesGitScanReviewByChangeSet() async throws {
        let repoURL = try makeGitRepository(name: "git-scan-dedupe")
        let changed = repoURL.appendingPathComponent("README.md")
        try "first change\n".write(to: changed, atomically: true, encoding: .utf8)

        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        await service.addSubscription(plan)

        let first = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.gitScanReview],
            onlyWasteRisk: false,
            gitInsights: [sampleInsight(path: repoURL.path)]
        )
        let second = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.gitScanReview],
            onlyWasteRisk: false,
            gitInsights: [sampleInsight(path: repoURL.path)]
        )

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(service.autoTaskRecords.count, 1)
    }

    func testEvaluateAndQueueAutoTasksSkipsGitScanReviewForHugeDiff() async throws {
        let repoURL = try makeGitRepository(name: "git-scan-large")
        let changed = repoURL.appendingPathComponent("big.txt")
        let lines = Array(repeating: "line", count: 5000).joined(separator: "\n")
        try lines.write(to: changed, atomically: true, encoding: .utf8)

        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        await service.addSubscription(plan)

        let queued = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.gitScanReview],
            onlyWasteRisk: false,
            gitInsights: [sampleInsight(path: repoURL.path)]
        )

        XCTAssertEqual(queued, 0)
        XCTAssertTrue(service.autoTaskRecords.isEmpty)
    }

    func testEvaluateAndQueueAutoTasksSkipsDochiUsageStoreSource() async {
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
        await service.addSubscription(meteredPlan)
        await service.addSubscription(subscriptionPlan)

        let queued = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.research],
            onlyWasteRisk: false
        )

        XCTAssertEqual(queued, 1)
        XCTAssertEqual(service.autoTaskRecords.count, 1)
        XCTAssertEqual(service.autoTaskRecords.first?.subscriptionId, subscriptionPlan.id)
    }

    func testEvaluateAndQueueAutoTasksOnlyWasteRiskWithMixedSourcesUsesSubscriptionAxis() async {
        let calendar = Calendar.current
        let todayDay = calendar.component(.day, from: Date())
        let wasteRiskResetDay = todayDay < 28 ? todayDay + 1 : 1

        let meteredWasteRiskPlan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Metered",
            usageSource: .dochiUsageStore,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: wasteRiskResetDay
        )
        let subscriptionWasteRiskPlan = SubscriptionPlan(
            providerName: "Claude Max",
            planName: "Max",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: wasteRiskResetDay
        )
        await service.addSubscription(meteredWasteRiskPlan)
        await service.addSubscription(subscriptionWasteRiskPlan)

        let queued = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.research],
            onlyWasteRisk: true
        )

        XCTAssertEqual(queued, 1)
        XCTAssertEqual(service.autoTaskRecords.count, 1)
        XCTAssertEqual(service.autoTaskRecords.first?.subscriptionId, subscriptionWasteRiskPlan.id)
    }

    func testEvaluateAndQueueAutoTasksMaintainsSameDayDedupeWithMixedSources() async {
        let meteredPlan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Metered",
            usageSource: .dochiUsageStore,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        let subscriptionPlan = SubscriptionPlan(
            providerName: "Claude Max",
            planName: "Max",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        await service.addSubscription(meteredPlan)
        await service.addSubscription(subscriptionPlan)

        let first = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.research],
            onlyWasteRisk: false
        )
        let second = await service.evaluateAndQueueAutoTasks(
            enabledTypes: [.research],
            onlyWasteRisk: false
        )

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(service.autoTaskRecords.count, 1)
        XCTAssertEqual(service.autoTaskRecords.first?.subscriptionId, subscriptionPlan.id)
    }

    // MARK: - Utilization

    func testUtilizationWithNoUsageStore() async {
        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        await service.addSubscription(plan)

        let util = await service.utilization(for: plan)
        XCTAssertEqual(util.usedTokens, 0)  // No usage store
        XCTAssertEqual(util.subscription.id, plan.id)
        XCTAssertGreaterThan(util.daysInPeriod, 0)
    }

    func testUtilizationUnlimitedPlan() async {
        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Unlimited",
            monthlyTokenLimit: nil
        )
        await service.addSubscription(plan)

        let util = await service.utilization(for: plan)
        XCTAssertEqual(util.usageRatio, 0)
        XCTAssertEqual(util.currentUnusedPercent, 0)
    }

    func testAllUtilizations() async {
        let plan1 = SubscriptionPlan(providerName: "OpenAI", planName: "Pro")
        let plan2 = SubscriptionPlan(providerName: "Anthropic", planName: "Team")
        await service.addSubscription(plan1)
        await service.addSubscription(plan2)

        let utils = await service.allUtilizations()
        XCTAssertEqual(utils.count, 2)
    }

    // MARK: - Model Codable

    func testSubscriptionPlanCodable() throws {
        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 15,
            monthlyCostUSD: 20.0
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(plan)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SubscriptionPlan.self, from: data)

        XCTAssertEqual(decoded.id, plan.id)
        XCTAssertEqual(decoded.providerName, "OpenAI")
        XCTAssertEqual(decoded.planName, "Pro")
        XCTAssertEqual(decoded.usageSource, .externalToolLogs)
        XCTAssertEqual(decoded.monthlyTokenLimit, 1_000_000)
        XCTAssertEqual(decoded.resetDayOfMonth, 15)
        XCTAssertEqual(decoded.monthlyCostUSD, 20.0)
    }

    func testSubscriptionPlanBackwardCompatibility() throws {
        // Test decoding without optional fields
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "providerName": "OpenAI",
            "planName": "Pro"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SubscriptionPlan.self, from: json)

        XCTAssertEqual(decoded.providerName, "OpenAI")
        XCTAssertEqual(decoded.planName, "Pro")
        XCTAssertEqual(decoded.usageSource, .dochiUsageStore)
        XCTAssertNil(decoded.monthlyTokenLimit)
        XCTAssertEqual(decoded.resetDayOfMonth, 1)
        XCTAssertEqual(decoded.monthlyCostUSD, 0)
    }

    func testSubscriptionEditSheetMakePlanUsesSelectedUsageSourceAndValues() {
        let plan = SubscriptionEditSheet.makePlan(
            subscription: nil,
            providerName: "OpenAI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            isUnlimited: false,
            monthlyTokenLimit: "1200000",
            resetDay: 7,
            monthlyCost: "20.50"
        )

        XCTAssertEqual(plan.providerName, "OpenAI")
        XCTAssertEqual(plan.planName, "Pro")
        XCTAssertEqual(plan.usageSource, .externalToolLogs)
        XCTAssertEqual(plan.monthlyTokenLimit, 1_200_000)
        XCTAssertEqual(plan.resetDayOfMonth, 7)
        XCTAssertEqual(plan.monthlyCostUSD, 20.5, accuracy: 0.0001)
    }

    func testSubscriptionEditSheetMakePlanPreservesIdentityWhenEditing() {
        let originalCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = SubscriptionPlan(
            id: UUID(),
            providerName: "Anthropic",
            planName: "Max",
            usageSource: .dochiUsageStore,
            monthlyTokenLimit: nil,
            resetDayOfMonth: 1,
            monthlyCostUSD: 30,
            createdAt: originalCreatedAt
        )

        let edited = SubscriptionEditSheet.makePlan(
            subscription: original,
            providerName: "Anthropic",
            planName: "Max Plus",
            usageSource: .externalToolLogs,
            isUnlimited: true,
            monthlyTokenLimit: "999999",
            resetDay: 1,
            monthlyCost: "40"
        )

        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.createdAt, originalCreatedAt)
        XCTAssertEqual(edited.usageSource, .externalToolLogs)
        XCTAssertEqual(edited.planName, "Max Plus")
        XCTAssertNil(edited.monthlyTokenLimit)
    }

    func testSubscriptionEditSheetMakePlanUnlimitedDropsTokenLimitAndHandlesInvalidCost() {
        let plan = SubscriptionEditSheet.makePlan(
            subscription: nil,
            providerName: "OpenAI",
            planName: "Unlimited",
            usageSource: .dochiUsageStore,
            isUnlimited: true,
            monthlyTokenLimit: "not-a-number",
            resetDay: 12,
            monthlyCost: "abc"
        )

        XCTAssertNil(plan.monthlyTokenLimit)
        XCTAssertEqual(plan.monthlyCostUSD, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.usageSource, .dochiUsageStore)
    }

    func testAutoTaskRecordCodable() throws {
        let subId = UUID()
        let record = AutoTaskRecord(
            taskType: .research,
            subscriptionId: subId,
            tokensUsed: 5000,
            summary: "Test summary"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AutoTaskRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.taskType, .research)
        XCTAssertEqual(decoded.subscriptionId, subId)
        XCTAssertEqual(decoded.tokensUsed, 5000)
        XCTAssertEqual(decoded.summary, "Test summary")
    }

    // MARK: - ResourceUtilization

    func testResourceUtilizationComputedProperties() {
        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            monthlyTokenLimit: 1_000_000
        )

        let util = ResourceUtilization(
            subscription: plan,
            usedTokens: 300_000,
            daysInPeriod: 30,
            daysRemaining: 10,
            riskLevel: .normal
        )

        XCTAssertEqual(util.usageRatio, 0.3, accuracy: 0.001)
        XCTAssertEqual(util.periodRatio, 20.0 / 30.0, accuracy: 0.001)
        XCTAssertEqual(util.remainingRatio, 10.0 / 30.0, accuracy: 0.001)
        XCTAssertEqual(util.currentUnusedPercent, 70, accuracy: 0.1)
    }

    func testResourceUtilizationUnlimited() {
        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Unlimited",
            monthlyTokenLimit: nil
        )

        let util = ResourceUtilization(
            subscription: plan,
            usedTokens: 500_000,
            daysInPeriod: 30,
            daysRemaining: 15,
            riskLevel: .normal
        )

        XCTAssertEqual(util.usageRatio, 0)
        XCTAssertEqual(util.currentUnusedPercent, 0)
    }

    func testUtilizationUsesDochiUsageStoreWhenSourceIsDochiUsageStore() async {
        let usageDir = tempDir.appendingPathComponent("usage-source-store")
        try? FileManager.default.createDirectory(at: usageDir, withIntermediateDirectories: true)
        let store = UsageStore(baseURL: usageDir)
        let now = Date()

        await store.record(ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 120,
            outputTokens: 80,
            totalTokens: 200,
            firstByteLatency: 0.1,
            totalLatency: 0.3,
            timestamp: now,
            wasFallback: false,
            agentName: "도치"
        ))
        await store.flushToDisk()

        let sourceService = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-store-source"),
            usageStore: store,
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")]
        )
        let plan = SubscriptionPlan(
            providerName: "openai",
            planName: "Metered",
            usageSource: .dochiUsageStore,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )

        let util = await sourceService.utilization(for: plan)
        XCTAssertEqual(util.usedTokens, 200)
    }

    func testMonitoringSnapshotUsesDochiUsageStoreLatestCollection() async {
        let usageDir = tempDir.appendingPathComponent("usage-monitoring-store")
        try? FileManager.default.createDirectory(at: usageDir, withIntermediateDirectories: true)
        let store = UsageStore(baseURL: usageDir)
        let now = Date()

        await store.record(ExchangeMetrics(
            provider: "openai",
            model: "gpt-4.1",
            inputTokens: 60,
            outputTokens: 40,
            totalTokens: 100,
            firstByteLatency: 0.12,
            totalLatency: 0.4,
            timestamp: now,
            wasFallback: false,
            agentName: "도치"
        ))
        await store.flushToDisk()

        let sourceService = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-monitoring-store"),
            usageStore: store,
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")]
        )
        let plan = SubscriptionPlan(
            providerName: "openai",
            planName: "Metered",
            usageSource: .dochiUsageStore,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )

        let snapshot = await sourceService.monitoringSnapshot(for: plan)
        XCTAssertEqual(snapshot.statusCode, "ok_store")
        XCTAssertNotNil(snapshot.lastCollectedAt)
    }

    func testMonitoringSnapshotUsesUsageStoreLatestRecordDayIndexAPI() async {
        let mockStore = MockUsageStore()
        mockStore.latestDayByProvider["openai"] = Date()

        let sourceService = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-monitoring-store-index"),
            usageStore: mockStore,
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")]
        )
        let plan = SubscriptionPlan(
            providerName: "openai",
            planName: "Metered",
            usageSource: .dochiUsageStore,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )

        let snapshot = await sourceService.monitoringSnapshot(for: plan)
        XCTAssertEqual(snapshot.statusCode, "ok_store")
        XCTAssertEqual(mockStore.latestRecordDayCallCount, 1)
        XCTAssertEqual(mockStore.allMonthsCallCount, 0)
        XCTAssertEqual(mockStore.dailyRecordsCallCount, 0)
    }

    func testMonitoringSnapshotGeminiUnsupportedAuthType() async throws {
        let geminiRoot = tempDir.appendingPathComponent("gemini-monitoring-unsupported")
        try FileManager.default.createDirectory(at: geminiRoot, withIntermediateDirectories: true)
        let settings = #"{"security":{"auth":{"selectedType":"api-key"}}}"#
        try settings.write(
            to: geminiRoot.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let sourceService = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-gemini-monitoring-unsupported"),
            usageStore: nil,
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")],
            geminiConfigRoots: [geminiRoot]
        )
        let plan = SubscriptionPlan(
            providerName: "Gemini CLI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1000,
            resetDayOfMonth: 1
        )

        let snapshot = await sourceService.monitoringSnapshot(for: plan)
        XCTAssertEqual(snapshot.statusCode, "unsupported_auth_type")
        XCTAssertNotNil(snapshot.statusPresentation.detail)
    }

    func testUtilizationUsesExternalToolLogsWhenSourceIsExternalToolLogs() async throws {
        let claudeRoot = tempDir.appendingPathComponent("claude-projects")
        let codexRoot = tempDir.appendingPathComponent("codex-sessions")
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)

        let activeTime = Date()
        let inactiveTime = activeTime.addingTimeInterval(-40 * 24 * 60 * 60)
        let iso = ISO8601DateFormatter()

        let sessionURL = codexRoot.appendingPathComponent("session-1.jsonl")
        let lines = [
            "{\"type\":\"session_meta\",\"payload\":{\"session_id\":\"sess-1\"}}",
            "{\"type\":\"event_msg\",\"timestamp\":\"\(iso.string(from: inactiveTime))\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":1000,\"cached_input_tokens\":100,\"output_tokens\":1000}}}}",
            "{\"type\":\"event_msg\",\"timestamp\":\"\(iso.string(from: activeTime))\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":1300,\"cached_input_tokens\":140,\"output_tokens\":1120}}}}",
        ].joined(separator: "\n")
        try lines.write(to: sessionURL, atomically: true, encoding: .utf8)

        let sourceService = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-external-source"),
            usageStore: nil,
            claudeProjectsRoots: [claudeRoot],
            codexSessionsRoots: [codexRoot]
        )

        let plan = SubscriptionPlan(
            providerName: "ChatGPT Pro",
            planName: "Plus",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )

        let util = await sourceService.utilization(for: plan)
        XCTAssertEqual(util.usedTokens, 420)
    }

    func testExternalToolLogsCodexUsesDeltaFromTotalTokenUsage() async throws {
        let codexRoot = tempDir.appendingPathComponent("codex-delta")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        let now = Date()
        let iso = ISO8601DateFormatter()

        let sessionURL = codexRoot.appendingPathComponent("session-delta.jsonl")
        let lines = [
            "{\"type\":\"session_meta\",\"payload\":{\"session_id\":\"sess-delta\"}}",
            "{\"type\":\"event_msg\",\"timestamp\":\"\(iso.string(from: now.addingTimeInterval(-20)))\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":10,\"output_tokens\":20}}}}",
            "{\"type\":\"event_msg\",\"timestamp\":\"\(iso.string(from: now.addingTimeInterval(-10)))\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":160,\"cached_input_tokens\":30,\"output_tokens\":26}}}}",
        ].joined(separator: "\n")
        try lines.write(to: sessionURL, atomically: true, encoding: .utf8)

        let sourceService = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-codex-delta"),
            usageStore: nil,
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            codexSessionsRoots: [codexRoot]
        )

        let plan = SubscriptionPlan(
            providerName: "ChatGPT Pro",
            planName: "Plus",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )

        let util = await sourceService.utilization(for: plan)
        XCTAssertEqual(util.usedTokens, 186) // (100+20) + (60+6)
    }

    func testExternalToolLogsCodexDedupesArchivedSessionBySessionID() async throws {
        let codexHome = tempDir.appendingPathComponent("codex-home")
        let sessionsRoot = codexHome.appendingPathComponent("sessions")
        let archivedRoot = codexHome.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)

        let now = Date()
        let iso = ISO8601DateFormatter()
        let payload = [
            "{\"type\":\"session_meta\",\"payload\":{\"session_id\":\"sess-shared\"}}",
            "{\"type\":\"event_msg\",\"timestamp\":\"\(iso.string(from: now))\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":300,\"cached_input_tokens\":20,\"output_tokens\":120}}}}",
        ].joined(separator: "\n")

        try payload.write(to: sessionsRoot.appendingPathComponent("shared.jsonl"), atomically: true, encoding: .utf8)
        try payload.write(to: archivedRoot.appendingPathComponent("shared-archived.jsonl"), atomically: true, encoding: .utf8)

        let sourceService = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-codex-archived"),
            usageStore: nil,
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            codexSessionsRoots: [sessionsRoot]
        )

        let plan = SubscriptionPlan(
            providerName: "OpenAI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )

        let util = await sourceService.utilization(for: plan)
        XCTAssertEqual(util.usedTokens, 420)
    }

    func testExternalToolLogsClaudeDedupesStreamingChunks() async throws {
        let claudeRoot = tempDir.appendingPathComponent("claude-stream")
        let projectDir = claudeRoot.appendingPathComponent("project-a")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let now = Date()
        let iso = ISO8601DateFormatter()

        let chunkA = "{\"type\":\"assistant\",\"timestamp\":\"\(iso.string(from: now.addingTimeInterval(-20)))\",\"requestId\":\"req-1\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":100,\"cache_creation_input_tokens\":50,\"cache_read_input_tokens\":25,\"output_tokens\":10}}}"
        let chunkB = "{\"type\":\"assistant\",\"timestamp\":\"\(iso.string(from: now.addingTimeInterval(-10)))\",\"requestId\":\"req-1\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":100,\"cache_creation_input_tokens\":50,\"cache_read_input_tokens\":25,\"output_tokens\":10}}}"
        let distinct = "{\"type\":\"assistant\",\"timestamp\":\"\(iso.string(from: now))\",\"requestId\":\"req-2\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":20,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0,\"output_tokens\":5}}}"
        let content = [chunkA, chunkB, distinct].joined(separator: "\n")
        try content.write(to: projectDir.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let sourceService = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-claude-stream"),
            usageStore: nil,
            claudeProjectsRoots: [claudeRoot],
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")]
        )

        let plan = SubscriptionPlan(
            providerName: "Claude Max",
            planName: "Max",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )

        let util = await sourceService.utilization(for: plan)
        XCTAssertEqual(util.usedTokens, 210) // 185 + 25
    }

    func testExternalUsageMonitorCreatesCacheOnFirstSave() async throws {
        let codexRoot = tempDir.appendingPathComponent("codex-cache-first-save")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        let cacheURL = tempDir.appendingPathComponent("external-cache-first-save.json")
        let now = Date()
        let iso = ISO8601DateFormatter()

        let content = [
            "{\"type\":\"session_meta\",\"payload\":{\"session_id\":\"sess-cache\"}}",
            "{\"type\":\"event_msg\",\"timestamp\":\"\(iso.string(from: now))\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":80,\"cached_input_tokens\":10,\"output_tokens\":20}}}}",
        ].joined(separator: "\n")
        try content.write(to: codexRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let monitor = ExternalUsageMonitor(
            codexSessionsRoots: [codexRoot],
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            cacheURL: cacheURL,
            refreshMinIntervalSeconds: 0
        )

        let used = await monitor.tokensUsed(provider: .codex, since: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(used, 100)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testExternalUsageMonitorClaudeAvoidsDuplicateAcrossScanBoundary() async throws {
        let claudeRoot = tempDir.appendingPathComponent("claude-boundary")
        let projectDir = claudeRoot.appendingPathComponent("project-a")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let cacheURL = tempDir.appendingPathComponent("external-cache-claude-boundary.json")
        let now = Date()
        let iso = ISO8601DateFormatter()
        let fileURL = projectDir.appendingPathComponent("session.jsonl")

        let first = "{\"type\":\"assistant\",\"timestamp\":\"\(iso.string(from: now.addingTimeInterval(-20)))\",\"requestId\":\"req-1\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":100,\"cache_creation_input_tokens\":50,\"cache_read_input_tokens\":25,\"output_tokens\":10}}}"
        try first.write(to: fileURL, atomically: true, encoding: .utf8)

        let monitor = ExternalUsageMonitor(
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")],
            claudeProjectsRoots: [claudeRoot],
            cacheURL: cacheURL,
            refreshMinIntervalSeconds: 0
        )
        let since = now.addingTimeInterval(-3600)

        let firstUsed = await monitor.tokensUsed(provider: .claude, since: since, now: now)
        XCTAssertEqual(firstUsed, 185)

        let duplicate = "{\"type\":\"assistant\",\"timestamp\":\"\(iso.string(from: now.addingTimeInterval(-10)))\",\"requestId\":\"req-1\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":100,\"cache_creation_input_tokens\":50,\"cache_read_input_tokens\":25,\"output_tokens\":10}}}"
        let distinct = "{\"type\":\"assistant\",\"timestamp\":\"\(iso.string(from: now))\",\"requestId\":\"req-2\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-sonnet-4-20250514\",\"usage\":{\"input_tokens\":20,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0,\"output_tokens\":5}}}"
        try [first, duplicate, distinct].joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let secondUsed = await monitor.tokensUsed(provider: .claude, since: since, now: now.addingTimeInterval(1))
        XCTAssertEqual(secondUsed, 210)
    }

    func testExternalUsageMonitorGeminiRejectsUnsupportedAuthType() async throws {
        let geminiRoot = tempDir.appendingPathComponent("gemini-unsupported")
        try FileManager.default.createDirectory(at: geminiRoot, withIntermediateDirectories: true)
        let settings = #"{"security":{"auth":{"selectedType":"api-key"}}}"#
        try settings.write(
            to: geminiRoot.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let monitor = ExternalUsageMonitor(
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")],
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            geminiConfigRoots: [geminiRoot],
            cacheURL: tempDir.appendingPathComponent("gemini-unsupported-cache.json"),
            refreshMinIntervalSeconds: 0
        )
        let now = Date()

        let used = await monitor.tokensUsed(
            provider: .gemini,
            since: now.addingTimeInterval(-3600),
            tokenLimit: 1000,
            now: now
        )

        XCTAssertEqual(used, 0)
        let status = await monitor.status(provider: .gemini)
        XCTAssertEqual(status?.code, "unsupported_auth_type")
    }

    func testExternalUsageMonitorGeminiFallsBackToCLIStats() async throws {
        let geminiRoot = tempDir.appendingPathComponent("gemini-cli-fallback")
        try FileManager.default.createDirectory(at: geminiRoot, withIntermediateDirectories: true)
        let settings = #"{"security":{"auth":{"selectedType":"oauth-personal"}}}"#
        try settings.write(
            to: geminiRoot.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let fakeCLI = tempDir.appendingPathComponent("fake-gemini-cli")
        try "#!/bin/sh\necho test\n".write(to: fakeCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)

        let previousGeminiCLIPath = ProcessInfo.processInfo.environment["GEMINI_CLI_PATH"]
        setenv("GEMINI_CLI_PATH", fakeCLI.path, 1)
        defer {
            if let previousGeminiCLIPath {
                setenv("GEMINI_CLI_PATH", previousGeminiCLIPath, 1)
            } else {
                unsetenv("GEMINI_CLI_PATH")
            }
        }

        let statsOutput = """
        │  Model Usage                            Reqs                  Usage left  │
        │  gemini-2.5-flash                          -       75.0% (Resets in 12h)  │
        │  gemini-2.5-pro                            -       82.0% (Resets in 12h)  │
        """

        let monitor = ExternalUsageMonitor(
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")],
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            geminiConfigRoots: [geminiRoot],
            cacheURL: tempDir.appendingPathComponent("gemini-cli-fallback-cache.json"),
            refreshMinIntervalSeconds: 0,
            geminiDataLoader: { _ in
                throw URLError(.cannotConnectToHost)
            },
            geminiCommandRunner: { _, _, _ in
                (statsOutput, 0)
            }
        )
        let now = Date()

        let used = await monitor.tokensUsed(
            provider: .gemini,
            since: now.addingTimeInterval(-3600),
            tokenLimit: 1000,
            now: now
        )
        XCTAssertEqual(used, 250)
        let status = await monitor.status(provider: .gemini)
        XCTAssertEqual(status?.code, "ok_cli")
    }

    func testExternalUsageMonitorGeminiNotLoggedInStatus() async throws {
        let geminiRoot = tempDir.appendingPathComponent("gemini-not-logged-in")
        try FileManager.default.createDirectory(at: geminiRoot, withIntermediateDirectories: true)
        let settings = #"{"security":{"auth":{"selectedType":"oauth-personal"}}}"#
        try settings.write(
            to: geminiRoot.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let fakeCLI = tempDir.appendingPathComponent("fake-gemini-not-logged")
        try "#!/bin/sh\necho auth\n".write(to: fakeCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)

        let previousGeminiCLIPath = ProcessInfo.processInfo.environment["GEMINI_CLI_PATH"]
        setenv("GEMINI_CLI_PATH", fakeCLI.path, 1)
        defer {
            if let previousGeminiCLIPath {
                setenv("GEMINI_CLI_PATH", previousGeminiCLIPath, 1)
            } else {
                unsetenv("GEMINI_CLI_PATH")
            }
        }

        let monitor = ExternalUsageMonitor(
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")],
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            geminiConfigRoots: [geminiRoot],
            cacheURL: tempDir.appendingPathComponent("gemini-not-logged-cache.json"),
            refreshMinIntervalSeconds: 0,
            geminiDataLoader: { _ in
                throw URLError(.cannotConnectToHost)
            },
            geminiCommandRunner: { _, _, _ in
                ("Waiting for auth... (Press ESC or CTRL+C to cancel)", 0)
            }
        )
        let now = Date()

        let used = await monitor.tokensUsed(
            provider: .gemini,
            since: now.addingTimeInterval(-3600),
            tokenLimit: 1000,
            now: now
        )
        XCTAssertEqual(used, 0)
        let status = await monitor.status(provider: .gemini)
        XCTAssertEqual(status?.code, "not_logged_in")
    }

    func testExternalUsageMonitorGeminiRefreshesExpiredOAuthToken() async throws {
        let geminiRoot = tempDir.appendingPathComponent("gemini-refresh")
        try FileManager.default.createDirectory(at: geminiRoot, withIntermediateDirectories: true)

        let settings = #"{"security":{"auth":{"selectedType":"oauth-personal"}}}"#
        try settings.write(
            to: geminiRoot.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let expiredMs = (Date().addingTimeInterval(-600).timeIntervalSince1970 * 1000).rounded()
        let creds = """
        {
          "access_token": "expired-token",
          "refresh_token": "refresh-token",
          "id_token": "dummy.id.token",
          "expiry_date": \(Int(expiredMs))
        }
        """
        try creds.write(
            to: geminiRoot.appendingPathComponent("oauth_creds.json"),
            atomically: true,
            encoding: .utf8
        )

        let cliRoot = tempDir.appendingPathComponent("gemini-cli-root")
        let cliBinDir = cliRoot.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: cliBinDir, withIntermediateDirectories: true)
        let cliBinary = cliBinDir.appendingPathComponent("gemini")
        try "#!/bin/sh\necho gemini\n".write(to: cliBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliBinary.path)

        let oauthJS = cliRoot
            .appendingPathComponent("libexec/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js")
        try FileManager.default.createDirectory(at: oauthJS.deletingLastPathComponent(), withIntermediateDirectories: true)
        let oauthSource = """
        const OAUTH_CLIENT_ID = 'client-id-123.apps.googleusercontent.com';
        const OAUTH_CLIENT_SECRET = 'secret-xyz';
        """
        try oauthSource.write(to: oauthJS, atomically: true, encoding: .utf8)

        let previousGeminiCLIPath = ProcessInfo.processInfo.environment["GEMINI_CLI_PATH"]
        setenv("GEMINI_CLI_PATH", cliBinary.path, 1)
        defer {
            if let previousGeminiCLIPath {
                setenv("GEMINI_CLI_PATH", previousGeminiCLIPath, 1)
            } else {
                unsetenv("GEMINI_CLI_PATH")
            }
        }

        let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            switch (url.host ?? "", url.path) {
            case ("oauth2.googleapis.com", "/token"):
                let body = #"{"access_token":"fresh-token","expires_in":3600}"#.data(using: .utf8)!
                return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            case ("cloudcode-pa.googleapis.com", "/v1internal:loadCodeAssist"):
                let body = #"{"cloudaicompanionProject":"project-123"}"#.data(using: .utf8)!
                return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            case ("cloudcode-pa.googleapis.com", "/v1internal:retrieveUserQuota"):
                let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
                if auth == "Bearer fresh-token" {
                    let body = #"{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":0.4}]}"#
                        .data(using: .utf8)!
                    return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
                return (Data(), HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            default:
                return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
        }

        let monitor = ExternalUsageMonitor(
            codexSessionsRoots: [tempDir.appendingPathComponent("empty-codex")],
            claudeProjectsRoots: [tempDir.appendingPathComponent("empty-claude")],
            geminiConfigRoots: [geminiRoot],
            cacheURL: tempDir.appendingPathComponent("gemini-refresh-cache.json"),
            refreshMinIntervalSeconds: 0,
            geminiDataLoader: dataLoader,
            geminiCommandRunner: { _, _, _ in nil }
        )

        let now = Date()
        let used = await monitor.tokensUsed(
            provider: .gemini,
            since: now.addingTimeInterval(-3600),
            tokenLimit: 1000,
            now: now
        )

        XCTAssertEqual(used, 600)
        let status = await monitor.status(provider: .gemini)
        XCTAssertEqual(status?.code, "ok_api")

        let updatedCredsData = try Data(contentsOf: geminiRoot.appendingPathComponent("oauth_creds.json"))
        let updatedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: updatedCredsData) as? [String: Any]
        )
        XCTAssertEqual(updatedObject["access_token"] as? String, "fresh-token")
    }

    func testExternalToolLogsMixedProvidersIncludesGeminiCLIFallback() async throws {
        let claudeRoot = tempDir.appendingPathComponent("mixed-claude")
        let codexRoot = tempDir.appendingPathComponent("mixed-codex")
        let geminiRoot = tempDir.appendingPathComponent("mixed-gemini")
        let claudeProject = claudeRoot.appendingPathComponent("project-a")
        try FileManager.default.createDirectory(at: claudeProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: geminiRoot, withIntermediateDirectories: true)

        let now = Date()
        let iso = ISO8601DateFormatter()
        let codexLines = [
            "{\"type\":\"session_meta\",\"payload\":{\"session_id\":\"mixed-codex\"}}",
            "{\"type\":\"event_msg\",\"timestamp\":\"\(iso.string(from: now))\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":20,\"output_tokens\":20}}}}",
        ].joined(separator: "\n")
        try codexLines.write(to: codexRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let claudeLine = "{\"type\":\"assistant\",\"timestamp\":\"\(iso.string(from: now))\",\"requestId\":\"mixed-req\",\"message\":{\"id\":\"mixed-msg\",\"usage\":{\"input_tokens\":40,\"cache_creation_input_tokens\":20,\"cache_read_input_tokens\":10,\"output_tokens\":30}}}"
        try claudeLine.write(
            to: claudeProject.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let geminiSettings = #"{"security":{"auth":{"selectedType":"oauth-personal"}}}"#
        try geminiSettings.write(to: geminiRoot.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let fakeCLI = tempDir.appendingPathComponent("mixed-fake-gemini")
        let fakeScript = """
        #!/bin/sh
        cat <<'EOF'
        │  Model Usage                            Reqs                  Usage left  │
        │  gemini-2.5-flash                          -       75.0% (Resets in 12h)  │
        │  gemini-2.5-pro                            -       90.0% (Resets in 12h)  │
        EOF
        """
        try fakeScript.write(to: fakeCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)

        let previousGeminiCLIPath = ProcessInfo.processInfo.environment["GEMINI_CLI_PATH"]
        setenv("GEMINI_CLI_PATH", fakeCLI.path, 1)
        defer {
            if let previousGeminiCLIPath {
                setenv("GEMINI_CLI_PATH", previousGeminiCLIPath, 1)
            } else {
                unsetenv("GEMINI_CLI_PATH")
            }
        }

        let service = ResourceOptimizerService(
            baseURL: tempDir.appendingPathComponent("resource-mixed-providers"),
            usageStore: nil,
            claudeProjectsRoots: [claudeRoot],
            codexSessionsRoots: [codexRoot],
            geminiConfigRoots: [geminiRoot]
        )

        let codexPlan = SubscriptionPlan(
            providerName: "ChatGPT Pro",
            planName: "Plus",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        let claudePlan = SubscriptionPlan(
            providerName: "Claude Max",
            planName: "Max",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1_000_000,
            resetDayOfMonth: 1
        )
        let geminiPlan = SubscriptionPlan(
            providerName: "Gemini CLI",
            planName: "Pro",
            usageSource: .externalToolLogs,
            monthlyTokenLimit: 1000,
            resetDayOfMonth: 1
        )

        let codexUtil = await service.utilization(for: codexPlan)
        let claudeUtil = await service.utilization(for: claudePlan)
        let geminiUtil = await service.utilization(for: geminiPlan)

        XCTAssertEqual(codexUtil.usedTokens, 120)
        XCTAssertEqual(claudeUtil.usedTokens, 100)
        XCTAssertEqual(geminiUtil.usedTokens, 250)
    }

    // MARK: - Mock Tests

    func testMockResourceOptimizer() async {
        let mock = MockResourceOptimizer()
        let plan = SubscriptionPlan(providerName: "Test", planName: "Free")

        await mock.addSubscription(plan)
        XCTAssertEqual(mock.addSubscriptionCallCount, 1)
        XCTAssertEqual(mock.subscriptions.count, 1)

        await mock.queueAutoTask(type: .kanbanCleanup, subscriptionId: plan.id)
        XCTAssertEqual(mock.queueAutoTaskCallCount, 1)
        XCTAssertEqual(mock.autoTaskRecords.count, 1)

        let queued = await mock.evaluateAndQueueAutoTasks(
            enabledTypes: [.research],
            onlyWasteRisk: true
        )
        XCTAssertEqual(mock.evaluateAndQueueAutoTasksCallCount, 1)
        XCTAssertEqual(mock.lastEvaluatedTypes, [.research])
        XCTAssertEqual(mock.lastOnlyWasteRisk, true)
        XCTAssertEqual(queued, 0)

        await mock.deleteSubscription(id: plan.id)
        XCTAssertEqual(mock.deleteSubscriptionCallCount, 1)
        XCTAssertEqual(mock.subscriptions.count, 0)
    }

    // MARK: - ViewModel DI

    func testViewModelAcceptsMockResourceOptimizer() async {
        let keychainService = MockKeychainService()
        keychainService.store["openai_api_key"] = "sk-test"
        let wsId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

        let viewModel = DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: keychainService,
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: AppSettings(),
            sessionContext: SessionContext(workspaceId: wsId)
        )

        let mock = MockResourceOptimizer()
        viewModel.configureResourceOptimizer(mock)

        XCTAssertNotNil(viewModel.resourceOptimizer)

        // Verify the mock works through the protocol interface
        let plan = SubscriptionPlan(providerName: "TestProvider", planName: "Pro")
        await viewModel.resourceOptimizer?.addSubscription(plan)
        XCTAssertEqual(mock.addSubscriptionCallCount, 1)
        XCTAssertEqual(mock.subscriptions.count, 1)
    }

    // MARK: - WasteRiskLevel

    func testWasteRiskLevelDisplayName() {
        XCTAssertEqual(WasteRiskLevel.comfortable.displayName, "여유")
        XCTAssertEqual(WasteRiskLevel.caution.displayName, "주의")
        XCTAssertEqual(WasteRiskLevel.wasteRisk.displayName, "낭비 위험")
        XCTAssertEqual(WasteRiskLevel.normal.displayName, "정상")
    }

    func testSubscriptionMonitoringSnapshotPresentationNotLoggedIn() {
        let snapshot = SubscriptionMonitoringSnapshot(
            subscriptionID: UUID(),
            source: .externalToolLogs,
            provider: "Gemini CLI",
            statusCode: "not_logged_in",
            statusMessage: nil,
            lastCollectedAt: nil
        )
        let presentation = snapshot.statusPresentation
        XCTAssertEqual(presentation.label, "로그인 필요")
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertNotNil(presentation.detail)
    }

    // MARK: - AutoTaskType

    func testAutoTaskTypeProperties() {
        XCTAssertEqual(AutoTaskType.research.displayName, "자료 조사")
        XCTAssertEqual(AutoTaskType.memoryCleanup.displayName, "메모리 정리")
        XCTAssertEqual(AutoTaskType.documentSummary.displayName, "문서 요약")
        XCTAssertEqual(AutoTaskType.kanbanCleanup.displayName, "칸반 정리")
        XCTAssertEqual(AutoTaskType.gitScanReview.displayName, "Git 스캔 리뷰")

        XCTAssertFalse(AutoTaskType.research.icon.isEmpty)
        XCTAssertFalse(AutoTaskType.memoryCleanup.icon.isEmpty)
        XCTAssertFalse(AutoTaskType.documentSummary.icon.isEmpty)
        XCTAssertFalse(AutoTaskType.kanbanCleanup.icon.isEmpty)
        XCTAssertFalse(AutoTaskType.gitScanReview.icon.isEmpty)
    }

    // MARK: - Git Helpers

    private func makeGitRepository(name: String) throws -> URL {
        let repoURL = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try runGit(["init"], at: repoURL)
        try runGit(["checkout", "-b", "main"], at: repoURL)

        let readme = repoURL.appendingPathComponent("README.md")
        try "# \(name)\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: repoURL)
        try runGit(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "init"], at: repoURL)

        return repoURL
    }

    private func runGit(_ args: [String], at repoURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = repoURL
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ResourceOptimizerTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "git command failed: \(args.joined(separator: " "))\n\(message)",
            ])
        }
    }

    private func sampleInsight(path: String) -> GitRepositoryInsight {
        GitRepositoryInsight(
            workDomain: "personal",
            workDomainConfidence: 0.5,
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
            lastCommitRelative: "today",
            upstreamLastCommitEpoch: nil,
            upstreamLastCommitISO8601: nil,
            upstreamLastCommitRelative: "unknown",
            daysSinceLastCommit: nil,
            recentCommitCount30d: 0,
            changedFileCount: 1,
            untrackedFileCount: 0,
            aheadCount: 0,
            behindCount: 0,
            score: 1
        )
    }
}
