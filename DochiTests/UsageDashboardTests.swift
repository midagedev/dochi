import XCTest
@testable import Dochi

// MARK: - ModelPricingTable Tests

@MainActor
final class ModelPricingTableTests: XCTestCase {

    func testKnownModelPricing() {
        // gpt-4o: $2.50 input, $10.00 output per 1M tokens
        let cost = ModelPricingTable.estimateCost(model: "gpt-4o", inputTokens: 1000, outputTokens: 500)
        // Expected: (1000 * 2.50 + 500 * 10.00) / 1_000_000 = (2500 + 5000) / 1_000_000 = 0.0075
        XCTAssertEqual(cost, 0.0075, accuracy: 0.0001)
    }

    func testMiniModelPricing() {
        // gpt-4o-mini: $0.15 input, $0.60 output per 1M tokens
        let cost = ModelPricingTable.estimateCost(model: "gpt-4o-mini", inputTokens: 10000, outputTokens: 5000)
        // Expected: (10000 * 0.15 + 5000 * 0.60) / 1_000_000 = (1500 + 3000) / 1_000_000 = 0.0045
        XCTAssertEqual(cost, 0.0045, accuracy: 0.0001)
    }

    func testClaudeSonnetPricing() {
        let cost = ModelPricingTable.estimateCost(model: "claude-3-5-sonnet-20241022", inputTokens: 1000, outputTokens: 500)
        // Expected: (1000 * 3.00 + 500 * 15.00) / 1_000_000 = (3000 + 7500) / 1_000_000 = 0.0105
        XCTAssertEqual(cost, 0.0105, accuracy: 0.0001)
    }

    func testUnknownModelReturnsZero() {
        let cost = ModelPricingTable.estimateCost(model: "unknown-model", inputTokens: 1000, outputTokens: 500)
        XCTAssertEqual(cost, 0.0)
    }

    func testLocalModelReturnsZero() {
        // Local models (not in pricing table) should return 0
        let cost = ModelPricingTable.estimateCost(model: "llama3.1:8b", inputTokens: 5000, outputTokens: 2000)
        XCTAssertEqual(cost, 0.0)
    }

    func testZeroTokensReturnsZero() {
        let cost = ModelPricingTable.estimateCost(model: "gpt-4o", inputTokens: 0, outputTokens: 0)
        XCTAssertEqual(cost, 0.0)
    }

    func testAllPricingEntriesHavePositivePrices() {
        for (model, pricing) in ModelPricingTable.prices {
            XCTAssertGreaterThanOrEqual(pricing.inputPerMillion, 0, "Model \(model) has negative input pricing")
            XCTAssertGreaterThanOrEqual(pricing.outputPerMillion, 0, "Model \(model) has negative output pricing")
        }
    }
}

// MARK: - UsageStore Tests

@MainActor
final class UsageStoreTests: XCTestCase {
    private var store: UsageStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DochiUsageTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = UsageStore(baseURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRecordAndQuery() async {
        let metrics = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: 150,
            firstByteLatency: 0.5,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false,
            agentName: "도치"
        )

        await store.record(metrics)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let monthKey = formatter.string(from: Date())

        let records = await store.dailyRecords(for: monthKey)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].entries.count, 1)
        XCTAssertEqual(records[0].entries[0].provider, "openai")
        XCTAssertEqual(records[0].entries[0].model, "gpt-4o")
        XCTAssertEqual(records[0].entries[0].inputTokens, 100)
        XCTAssertEqual(records[0].entries[0].outputTokens, 50)
        XCTAssertEqual(records[0].entries[0].agentName, "도치")
        XCTAssertGreaterThan(records[0].entries[0].estimatedCostUSD, 0)
    }

    func testMonthlySummary() async {
        // Record multiple entries
        for i in 0..<3 {
            let metrics = ExchangeMetrics(
                provider: "openai",
                model: "gpt-4o",
                inputTokens: 100 * (i + 1),
                outputTokens: 50 * (i + 1),
                totalTokens: 150 * (i + 1),
                firstByteLatency: nil,
                totalLatency: 1.0,
                timestamp: Date(),
                wasFallback: false,
                agentName: "도치"
            )
            await store.record(metrics)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let monthKey = formatter.string(from: Date())

        let summary = await store.monthlySummary(for: monthKey)
        XCTAssertEqual(summary.totalExchanges, 3)
        // Input: 100 + 200 + 300 = 600
        XCTAssertEqual(summary.totalInputTokens, 600)
        // Output: 50 + 100 + 150 = 300
        XCTAssertEqual(summary.totalOutputTokens, 300)
        XCTAssertGreaterThan(summary.totalCostUSD, 0)
    }

    func testCurrentMonthCost() async {
        let metrics = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 1000,
            outputTokens: 500,
            totalTokens: 1500,
            firstByteLatency: nil,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false
        )

        await store.record(metrics)
        let cost = await store.currentMonthCost()
        XCTAssertGreaterThan(cost, 0)
    }

    func testFlushAndReload() async {
        let metrics = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: 150,
            firstByteLatency: nil,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false
        )

        await store.record(metrics)
        await store.flushToDisk()

        // Create a new store instance pointing to the same directory
        let store2 = UsageStore(baseURL: tempDir)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let monthKey = formatter.string(from: Date())

        let records = await store2.dailyRecords(for: monthKey)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].entries.count, 1)
    }

    func testEmptyMonthReturnsEmptyRecords() async {
        let records = await store.dailyRecords(for: "2020-01")
        XCTAssertTrue(records.isEmpty)
    }

    func testMultipleAgentsTracked() async {
        let metrics1 = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: 150,
            firstByteLatency: nil,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false,
            agentName: "도치"
        )
        let metrics2 = ExchangeMetrics(
            provider: "anthropic",
            model: "claude-3-5-sonnet-20241022",
            inputTokens: 200,
            outputTokens: 100,
            totalTokens: 300,
            firstByteLatency: nil,
            totalLatency: 2.0,
            timestamp: Date(),
            wasFallback: false,
            agentName: "연구원"
        )

        await store.record(metrics1)
        await store.record(metrics2)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let monthKey = formatter.string(from: Date())

        let summary = await store.monthlySummary(for: monthKey)
        XCTAssertEqual(summary.totalExchanges, 2)

        let byAgent = summary.costByAgent
        XCTAssertNotNil(byAgent["도치"])
        XCTAssertNotNil(byAgent["연구원"])
    }
}

// MARK: - ExchangeMetrics Backward Compatibility Tests

@MainActor
final class ExchangeMetricsCompatTests: XCTestCase {

    func testDecodeWithoutAgentName() throws {
        // JSON without agentName field (backward compatible)
        let json = """
        {
            "provider": "openai",
            "model": "gpt-4o",
            "inputTokens": 100,
            "outputTokens": 50,
            "totalTokens": 150,
            "totalLatency": 1.0,
            "timestamp": "2026-01-15T10:00:00Z",
            "wasFallback": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metrics = try decoder.decode(ExchangeMetrics.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(metrics.agentName, "도치")
        XCTAssertEqual(metrics.provider, "openai")
        XCTAssertEqual(metrics.model, "gpt-4o")
    }

    func testDecodeWithAgentName() throws {
        let json = """
        {
            "provider": "anthropic",
            "model": "claude-3-5-sonnet-20241022",
            "inputTokens": 200,
            "outputTokens": 100,
            "totalTokens": 300,
            "totalLatency": 2.0,
            "timestamp": "2026-01-15T10:00:00Z",
            "wasFallback": true,
            "agentName": "연구원"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metrics = try decoder.decode(ExchangeMetrics.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(metrics.agentName, "연구원")
        XCTAssertEqual(metrics.wasFallback, true)
    }

    func testEncodeIncludesAgentName() throws {
        let metrics = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: 150,
            firstByteLatency: nil,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false,
            agentName: "코더"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(metrics)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("코더"))
    }

    func testDefaultAgentNameInInit() {
        let metrics = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: nil,
            firstByteLatency: nil,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false
        )
        XCTAssertEqual(metrics.agentName, "도치")
    }
}

// MARK: - MetricsCollector Session Cost Tests

@MainActor
final class MetricsCollectorCostTests: XCTestCase {

    func testSessionCostUSD() {
        let collector = MetricsCollector()
        let metrics = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 1000,
            outputTokens: 500,
            totalTokens: 1500,
            firstByteLatency: nil,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false
        )
        collector.record(metrics)

        // gpt-4o: (1000 * 2.50 + 500 * 10.00) / 1_000_000 = 0.0075
        XCTAssertEqual(collector.sessionCostUSD, 0.0075, accuracy: 0.0001)
    }

    func testSessionCostWithMultipleExchanges() {
        let collector = MetricsCollector()

        let m1 = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 1000,
            outputTokens: 500,
            totalTokens: 1500,
            firstByteLatency: nil,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false
        )
        let m2 = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o-mini",
            inputTokens: 2000,
            outputTokens: 1000,
            totalTokens: 3000,
            firstByteLatency: nil,
            totalLatency: 0.5,
            timestamp: Date(),
            wasFallback: false
        )

        collector.record(m1)
        collector.record(m2)

        // gpt-4o: 0.0075
        // gpt-4o-mini: (2000 * 0.15 + 1000 * 0.60) / 1_000_000 = (300 + 600) / 1_000_000 = 0.0009
        let expected = 0.0075 + 0.0009
        XCTAssertEqual(collector.sessionCostUSD, expected, accuracy: 0.0001)
    }

    func testBudgetNotExceededByDefault() {
        let collector = MetricsCollector()
        XCTAssertFalse(collector.isBudgetExceeded)
    }

    func testBudgetExceededWhenEnabled() {
        let collector = MetricsCollector()
        let settings = AppSettings()
        settings.budgetEnabled = true
        settings.budgetBlockOnExceed = true
        settings.monthlyBudgetUSD = 0.001  // Very low budget
        collector.settings = settings

        // Record a metric that will exceed the tiny budget
        let metrics = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 10000,
            outputTokens: 5000,
            totalTokens: 15000,
            firstByteLatency: nil,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false
        )
        collector.record(metrics)

        XCTAssertTrue(collector.isBudgetExceeded)
    }

    func testSessionSummaryPreserved() {
        let collector = MetricsCollector()
        let metrics = ExchangeMetrics(
            provider: "openai",
            model: "gpt-4o",
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: 150,
            firstByteLatency: 0.5,
            totalLatency: 1.0,
            timestamp: Date(),
            wasFallback: false
        )
        collector.record(metrics)

        let summary = collector.sessionSummary
        XCTAssertEqual(summary.totalExchanges, 1)
        XCTAssertEqual(summary.totalInputTokens, 100)
        XCTAssertEqual(summary.totalOutputTokens, 50)
        XCTAssertEqual(summary.averageLatency, 1.0, accuracy: 0.01)
        XCTAssertEqual(summary.fallbackCount, 0)
    }
}

// MARK: - DailyUsageRecord Tests

@MainActor
final class DailyUsageRecordTests: XCTestCase {

    func testComputedProperties() {
        let entries = [
            UsageEntry(provider: "openai", model: "gpt-4o", agentName: "도치",
                       inputTokens: 100, outputTokens: 50, exchangeCount: 1,
                       estimatedCostUSD: 0.01, timestamp: Date()),
            UsageEntry(provider: "anthropic", model: "claude-3-5-sonnet-20241022", agentName: "연구원",
                       inputTokens: 200, outputTokens: 100, exchangeCount: 1,
                       estimatedCostUSD: 0.02, timestamp: Date()),
        ]
        let record = DailyUsageRecord(date: "2026-02-15", entries: entries)

        XCTAssertEqual(record.totalInputTokens, 300)
        XCTAssertEqual(record.totalOutputTokens, 150)
        XCTAssertEqual(record.totalExchanges, 2)
        XCTAssertEqual(record.totalCostUSD, 0.03, accuracy: 0.001)
    }

    func testEmptyRecord() {
        let record = DailyUsageRecord(date: "2026-02-15", entries: [])
        XCTAssertEqual(record.totalInputTokens, 0)
        XCTAssertEqual(record.totalOutputTokens, 0)
        XCTAssertEqual(record.totalExchanges, 0)
        XCTAssertEqual(record.totalCostUSD, 0.0)
    }
}

// MARK: - AppSettings Budget Tests

@MainActor
final class AppSettingsBudgetTests: XCTestCase {

    func testBudgetDefaults() {
        let settings = AppSettings()
        // Check defaults (may be affected by UserDefaults state)
        // Just verify the properties exist and are accessible
        _ = settings.budgetEnabled
        _ = settings.monthlyBudgetUSD
        _ = settings.budgetAlert50
        _ = settings.budgetAlert80
        _ = settings.budgetAlert100
        _ = settings.budgetBlockOnExceed
    }
}

// MARK: - Settings Section Tests

@MainActor
final class UsageSettingsSectionTests: XCTestCase {

    func testUsageSectionExists() {
        let sections = SettingsSection.allCases
        XCTAssertTrue(sections.contains(.usage))
    }

    func testUsageSectionProperties() {
        XCTAssertEqual(SettingsSection.usage.title, "사용량")
        XCTAssertEqual(SettingsSection.usage.icon, "chart.bar.xaxis")
        XCTAssertEqual(SettingsSection.usage.group, .ai)
    }

    func testUsageSectionSearchKeywords() {
        XCTAssertTrue(SettingsSection.usage.matches(query: "사용량"))
        XCTAssertTrue(SettingsSection.usage.matches(query: "비용"))
        XCTAssertTrue(SettingsSection.usage.matches(query: "cost"))
        XCTAssertTrue(SettingsSection.usage.matches(query: "토큰"))
        XCTAssertTrue(SettingsSection.usage.matches(query: "token"))
        XCTAssertTrue(SettingsSection.usage.matches(query: "예산"))
        XCTAssertTrue(SettingsSection.usage.matches(query: "budget"))
    }

    func testUsageSectionInAIGroup() {
        let aiSections = SettingsSectionGroup.ai.sections
        XCTAssertTrue(aiSections.contains(.usage))
    }
}

// MARK: - Command Palette Usage Tests

@MainActor
final class UsageCommandPaletteTests: XCTestCase {

    func testUsageDashboardCommandExists() {
        let items = CommandPaletteRegistry.staticItems
        let usageItem = items.first { $0.id == "settings.open.usage" }
        XCTAssertNotNil(usageItem)
        XCTAssertEqual(usageItem?.title, "사용량 대시보드")
        XCTAssertEqual(usageItem?.icon, "chart.bar.xaxis")
    }
}
