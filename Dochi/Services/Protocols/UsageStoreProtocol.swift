import Foundation

/// Protocol for persistent usage data storage.
@MainActor
protocol UsageStoreProtocol: Sendable {
    /// Record a single exchange metric with agent context.
    func record(_ metrics: ExchangeMetrics) async

    /// Get daily records for a given month (yyyy-MM).
    func dailyRecords(for month: String) async -> [DailyUsageRecord]

    /// Get aggregated monthly summary.
    func monthlySummary(for month: String) async -> MonthlyUsageSummary

    /// List all available months (yyyy-MM).
    func allMonths() async -> [String]

    /// Get total cost for the current month.
    func currentMonthCost() async -> Double
}
