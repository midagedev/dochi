import Foundation
import os

// MARK: - Metric Types

/// 메트릭 이벤트 타입.
enum MetricType: String, Codable, Sendable {
    case counter
    case histogram
    case gauge
}

/// 개별 메트릭 이벤트.
struct MetricEvent: Codable, Sendable {
    let type: MetricType
    let name: String
    let value: Double
    let labels: [String: String]
    let timestamp: Date

    init(
        type: MetricType,
        name: String,
        value: Double,
        labels: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.type = type
        self.name = name
        self.value = value
        self.labels = labels
        self.timestamp = timestamp
    }
}

/// 히스토그램 percentile 계산 결과.
struct HistogramSummary: Codable, Sendable {
    let name: String
    let labels: [String: String]
    let count: Int
    let sum: Double
    let min: Double
    let max: Double
    let p50: Double
    let p95: Double
    let p99: Double
}

/// 특정 시점의 메트릭 스냅샷 (SLO 평가용).
struct MetricsSnapshot: Codable, Sendable {
    let timestamp: Date
    let counters: [String: Double]
    let gauges: [String: Double]
    let histograms: [String: HistogramSummary]

    /// 라벨이 포함된 카운터를 조회한다.
    func counter(name: String) -> Double {
        counters[name] ?? 0.0
    }

    /// 라벨이 포함된 게이지를 조회한다.
    func gauge(name: String) -> Double {
        gauges[name] ?? 0.0
    }

    /// 히스토그램 요약을 조회한다.
    func histogram(name: String) -> HistogramSummary? {
        histograms[name]
    }
}

// MARK: - Metric Keys

/// 필수 메트릭 이름 상수.
enum MetricName {
    static let sessionActive = "dochi_runtime_session_active"
    static let sessionLatencyMs = "dochi_runtime_session_latency_ms"
    static let toolCallTotal = "dochi_tool_call_total"
    static let approvalWaitMs = "dochi_approval_wait_ms"
    static let contextSnapshotTokens = "dochi_context_snapshot_tokens"
    static let sessionResumeTotal = "dochi_session_resume_total"
    static let sessionResumeSuccess = "dochi_session_resume_success"
    static let requestTotal = "dochi_request_total"
    static let requestErrorTotal = "dochi_request_error_total"
    static let firstPartialLatencyMs = "dochi_first_partial_latency_ms"
    static let toolLatencyMs = "dochi_tool_latency_ms"
    static let totalResponseLatencyMs = "dochi_total_response_latency_ms"
}

// MARK: - RuntimeMetrics

/// 구조화 메트릭 수집 — 카운터/히스토그램/게이지 기반.
@MainActor
@Observable
final class RuntimeMetrics: RuntimeMetricsProtocol {
    /// 키 = "name|label1=val1,label2=val2" 형태로 고유 식별
    private var counterValues: [String: Double] = [:]
    private var gaugeValues: [String: Double] = [:]
    private var histogramValues: [String: [Double]] = [:]

    /// 라벨 정보를 보존하기 위한 매핑
    private var keyLabels: [String: [String: String]] = [:]
    private var keyNames: [String: String] = [:]

    private static let maxHistogramSamples = 10000

    // MARK: - RuntimeMetricsProtocol

    func incrementCounter(name: String, labels: [String: String], delta: Double) {
        let key = makeKey(name: name, labels: labels)
        counterValues[key, default: 0.0] += delta
        keyLabels[key] = labels
        keyNames[key] = name

        Log.app.debug("Counter \(name) += \(String(format: "%.0f", delta)) -> \(String(format: "%.0f", self.counterValues[key]!))")
    }

    func recordHistogram(name: String, labels: [String: String], value: Double) {
        let key = makeKey(name: name, labels: labels)
        histogramValues[key, default: []].append(value)
        keyLabels[key] = labels
        keyNames[key] = name

        // 최대 샘플 수 제한 (FIFO)
        if let count = histogramValues[key]?.count, count > Self.maxHistogramSamples {
            histogramValues[key]?.removeFirst(count - Self.maxHistogramSamples)
        }

        Log.app.debug("Histogram \(name) <- \(String(format: "%.2f", value))")
    }

    func setGauge(name: String, labels: [String: String], value: Double) {
        let key = makeKey(name: name, labels: labels)
        gaugeValues[key, default: 0.0] = value
        keyLabels[key] = labels
        keyNames[key] = name

        Log.app.debug("Gauge \(name) = \(String(format: "%.2f", value))")
    }

    func snapshot() -> MetricsSnapshot {
        var counters: [String: Double] = [:]
        for (key, value) in counterValues {
            counters[key] = value
        }

        var gauges: [String: Double] = [:]
        for (key, value) in gaugeValues {
            gauges[key] = value
        }

        var histograms: [String: HistogramSummary] = [:]
        for (key, values) in histogramValues {
            guard !values.isEmpty else { continue }
            let sorted = values.sorted()
            histograms[key] = HistogramSummary(
                name: keyNames[key] ?? key,
                labels: keyLabels[key] ?? [:],
                count: sorted.count,
                sum: sorted.reduce(0, +),
                min: sorted.first ?? 0,
                max: sorted.last ?? 0,
                p50: percentile(sorted, p: 0.50),
                p95: percentile(sorted, p: 0.95),
                p99: percentile(sorted, p: 0.99)
            )
        }

        return MetricsSnapshot(
            timestamp: Date(),
            counters: counters,
            gauges: gauges,
            histograms: histograms
        )
    }

    func reset() {
        counterValues.removeAll()
        gaugeValues.removeAll()
        histogramValues.removeAll()
        keyLabels.removeAll()
        keyNames.removeAll()
        Log.app.info("RuntimeMetrics reset")
    }

    // MARK: - Private

    private func makeKey(name: String, labels: [String: String]) -> String {
        if labels.isEmpty { return name }
        let labelStr = labels.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "\(name)|\(labelStr)"
    }

    /// Percentile 계산 (nearest-rank).
    private func percentile(_ sortedValues: [Double], p: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        if sortedValues.count == 1 { return sortedValues[0] }
        let rank = p * Double(sortedValues.count - 1)
        let lower = Int(rank)
        let upper = min(lower + 1, sortedValues.count - 1)
        let fraction = rank - Double(lower)
        return sortedValues[lower] + fraction * (sortedValues[upper] - sortedValues[lower])
    }
}
