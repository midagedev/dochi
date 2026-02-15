import XCTest
@testable import Dochi

@MainActor
final class ResourceOptimizerTests: XCTestCase {

    private var tempDir: URL!
    private var service: ResourceOptimizerService!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = ResourceOptimizerService(baseURL: tempDir, usageStore: nil)
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
        XCTAssertEqual(util.estimatedUnusedPercent, 0)
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
        XCTAssertNil(decoded.monthlyTokenLimit)
        XCTAssertEqual(decoded.resetDayOfMonth, 1)
        XCTAssertEqual(decoded.monthlyCostUSD, 0)
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
        XCTAssertEqual(util.estimatedUnusedPercent, 70, accuracy: 0.1)
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
        XCTAssertEqual(util.estimatedUnusedPercent, 0)
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

        await mock.deleteSubscription(id: plan.id)
        XCTAssertEqual(mock.deleteSubscriptionCallCount, 1)
        XCTAssertEqual(mock.subscriptions.count, 0)
    }

    // MARK: - WasteRiskLevel

    func testWasteRiskLevelDisplayName() {
        XCTAssertEqual(WasteRiskLevel.comfortable.displayName, "여유")
        XCTAssertEqual(WasteRiskLevel.caution.displayName, "주의")
        XCTAssertEqual(WasteRiskLevel.wasteRisk.displayName, "낭비 위험")
        XCTAssertEqual(WasteRiskLevel.normal.displayName, "정상")
    }

    // MARK: - AutoTaskType

    func testAutoTaskTypeProperties() {
        XCTAssertEqual(AutoTaskType.research.displayName, "자료 조사")
        XCTAssertEqual(AutoTaskType.memoryCleanup.displayName, "메모리 정리")
        XCTAssertEqual(AutoTaskType.documentSummary.displayName, "문서 요약")
        XCTAssertEqual(AutoTaskType.kanbanCleanup.displayName, "칸반 정리")

        XCTAssertFalse(AutoTaskType.research.icon.isEmpty)
        XCTAssertFalse(AutoTaskType.memoryCleanup.icon.isEmpty)
        XCTAssertFalse(AutoTaskType.documentSummary.icon.isEmpty)
        XCTAssertFalse(AutoTaskType.kanbanCleanup.icon.isEmpty)
    }
}
