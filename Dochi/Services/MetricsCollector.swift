import Foundation
import os
import UserNotifications

/// Collects and stores LLM exchange metrics locally for diagnostics.
@MainActor
@Observable
final class MetricsCollector {
    /// Recent exchange metrics (ring buffer, capped at `maxEntries`).
    private(set) var recentMetrics: [ExchangeMetrics] = []
    private static let maxEntries = 100

    /// Persistent usage store for historical tracking.
    var usageStore: UsageStoreProtocol?

    /// App settings for budget checking.
    var settings: AppSettings?

    /// Tracks which budget thresholds have already fired notifications this month.
    private var firedBudgetAlerts: Set<Int> = []
    private var currentAlertMonth: String = ""

    /// Cached persistent monthly cost (updated after each record).
    private(set) var cachedMonthCostUSD: Double = 0.0

    /// Record a new exchange metric.
    func record(_ metrics: ExchangeMetrics) {
        recentMetrics.append(metrics)
        if recentMetrics.count > Self.maxEntries {
            recentMetrics.removeFirst(recentMetrics.count - Self.maxEntries)
        }

        let tokens = metrics.totalTokensDisplay
        let latency = String(format: "%.1fs", metrics.totalLatency)
        let fallback = metrics.wasFallback ? " [fallback]" : ""
        Log.llm.info(
            "Exchange metrics: \(metrics.provider)/\(metrics.model) — \(tokens) tokens, \(latency)\(fallback)"
        )

        // Persist to usage store
        if let store = usageStore {
            Task {
                await store.record(metrics)
                self.cachedMonthCostUSD = await store.currentMonthCost()
                await checkBudget()
            }
        }
    }

    /// Aggregate stats for the current session.
    var sessionSummary: SessionMetricsSummary {
        let totalExchanges = recentMetrics.count
        let totalInputTokens = recentMetrics.compactMap(\.inputTokens).reduce(0, +)
        let totalOutputTokens = recentMetrics.compactMap(\.outputTokens).reduce(0, +)
        let avgLatency = totalExchanges > 0
            ? recentMetrics.map(\.totalLatency).reduce(0, +) / Double(totalExchanges)
            : 0
        let fallbackCount = recentMetrics.filter(\.wasFallback).count

        return SessionMetricsSummary(
            totalExchanges: totalExchanges,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            averageLatency: avgLatency,
            fallbackCount: fallbackCount
        )
    }

    /// Estimated cost for the current session based on in-memory metrics.
    var sessionCostUSD: Double {
        recentMetrics.reduce(0.0) { total, m in
            total + ModelPricingTable.estimateCost(
                model: m.model,
                inputTokens: m.inputTokens ?? 0,
                outputTokens: m.outputTokens ?? 0
            )
        }
    }

    /// Whether the current month budget has been exceeded (based on persistent monthly cost).
    var isBudgetExceeded: Bool {
        guard let settings, settings.budgetEnabled, settings.budgetBlockOnExceed else { return false }
        return cachedMonthCostUSD > settings.monthlyBudgetUSD
    }

    /// Refresh the cached monthly cost from the persistent usage store.
    func refreshMonthCost() async {
        guard let store = usageStore else { return }
        cachedMonthCostUSD = await store.currentMonthCost()
    }

    // MARK: - Budget Checking

    private func checkBudget() async {
        guard let settings, settings.budgetEnabled, let store = usageStore else { return }

        let currentCost = await store.currentMonthCost()
        let budget = settings.monthlyBudgetUSD
        guard budget > 0 else { return }

        let percentage = (currentCost / budget) * 100.0

        // Reset alerts for new month
        let monthKey = Self.monthFormatter.string(from: Date())
        if currentAlertMonth != monthKey {
            currentAlertMonth = monthKey
            firedBudgetAlerts.removeAll()
        }

        // Check thresholds
        if percentage >= 100 && settings.budgetAlert100 && !firedBudgetAlerts.contains(100) {
            firedBudgetAlerts.insert(100)
            sendBudgetNotification(
                title: "월 예산 초과",
                body: String(format: "이번 달 API 비용이 예산($%.2f)을 초과했습니다. 현재: $%.2f", budget, currentCost)
            )
        } else if percentage >= 80 && settings.budgetAlert80 && !firedBudgetAlerts.contains(80) {
            firedBudgetAlerts.insert(80)
            sendBudgetNotification(
                title: "월 예산 80% 도달",
                body: String(format: "이번 달 API 비용이 예산의 80%%에 도달했습니다. $%.2f / $%.2f", currentCost, budget)
            )
        } else if percentage >= 50 && settings.budgetAlert50 && !firedBudgetAlerts.contains(50) {
            firedBudgetAlerts.insert(50)
            sendBudgetNotification(
                title: "월 예산 50% 도달",
                body: String(format: "이번 달 API 비용이 예산의 50%%에 도달했습니다. $%.2f / $%.2f", currentCost, budget)
            )
        }
    }

    private func sendBudgetNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "budget-\(title.hashValue)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
        Log.app.info("Budget notification: \(title)")
    }

    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
}

/// Aggregated session metrics summary.
struct SessionMetricsSummary: Sendable {
    let totalExchanges: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let averageLatency: TimeInterval
    let fallbackCount: Int
}
