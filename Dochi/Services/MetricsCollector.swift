import Foundation
import os

/// Collects and stores LLM exchange metrics locally for diagnostics.
@MainActor
@Observable
final class MetricsCollector {
    /// Recent exchange metrics (ring buffer, capped at `maxEntries`).
    private(set) var recentMetrics: [ExchangeMetrics] = []
    private static let maxEntries = 100

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
}

/// Aggregated session metrics summary.
struct SessionMetricsSummary: Sendable {
    let totalExchanges: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let averageLatency: TimeInterval
    let fallbackCount: Int
}
