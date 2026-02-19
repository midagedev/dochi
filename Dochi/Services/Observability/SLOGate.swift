import Foundation
import os

// MARK: - SLO Data Models

/// SLO 조건 타입.
enum SLOConditionType: String, Codable, Sendable {
    /// 카운터/게이지 기반 임계값 비교 (>= threshold).
    case threshold
    /// 히스토그램 percentile 기반 비교 (<= threshold).
    case percentile
    /// 비율 기반 비교 (>= threshold). success/total 카운터 비율.
    case ratio
}

/// SLO 정의.
struct SLODefinition: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let metricName: String
    /// ratio 타입일 때 분모 메트릭 이름.
    let denominatorMetricName: String?
    let conditionType: SLOConditionType
    /// percentile 조건일 때 어떤 percentile을 사용할지 (0.0~1.0).
    let percentileLevel: Double?
    /// 기준값 — threshold/percentile은 이 값 이하, ratio는 이 값 이상.
    let thresholdValue: Double

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        metricName: String,
        denominatorMetricName: String? = nil,
        conditionType: SLOConditionType,
        percentileLevel: Double? = nil,
        thresholdValue: Double
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.metricName = metricName
        self.denominatorMetricName = denominatorMetricName
        self.conditionType = conditionType
        self.percentileLevel = percentileLevel
        self.thresholdValue = thresholdValue
    }
}

/// 개별 SLO 판정 결과.
struct SLOItemResult: Codable, Sendable, Identifiable {
    let id: UUID
    let definitionId: UUID
    let name: String
    let passed: Bool
    let actualValue: Double
    let thresholdValue: Double
    let description: String

    init(
        id: UUID = UUID(),
        definitionId: UUID,
        name: String,
        passed: Bool,
        actualValue: Double,
        thresholdValue: Double,
        description: String
    ) {
        self.id = id
        self.definitionId = definitionId
        self.name = name
        self.passed = passed
        self.actualValue = actualValue
        self.thresholdValue = thresholdValue
        self.description = description
    }
}

/// SLO 전체 평가 결과.
struct SLOResult: Codable, Sendable {
    let passed: Bool
    let timestamp: Date
    let items: [SLOItemResult]

    var failedItems: [SLOItemResult] { items.filter { !$0.passed } }
    var passedItems: [SLOItemResult] { items.filter(\.passed) }
    var passRate: Double {
        guard !items.isEmpty else { return 0.0 }
        return Double(passedItems.count) / Double(items.count)
    }
}

// MARK: - Security Check

/// 보안 점검 항목.
struct SecurityCheckItem: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    var passed: Bool

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        passed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.passed = passed
    }
}

// MARK: - SLOEvaluator

/// SLO 평가. 배포 게이트 판정은 DeployGate가 담당한다.
@MainActor
@Observable
final class SLOEvaluator: SLOEvaluatorProtocol {
    private(set) var definitions: [SLODefinition]
    private(set) var lastResult: SLOResult?

    init(definitions: [SLODefinition]? = nil) {
        self.definitions = definitions ?? Self.defaultDefinitions()
    }

    // MARK: - SLOEvaluatorProtocol

    func evaluate(snapshot: MetricsSnapshot) -> SLOResult {
        var items: [SLOItemResult] = []

        for definition in definitions {
            let result = evaluateDefinition(definition, snapshot: snapshot)
            items.append(result)
        }

        let allPassed = items.allSatisfy(\.passed)
        let result = SLOResult(
            passed: allPassed,
            timestamp: Date(),
            items: items
        )
        lastResult = result

        let status = allPassed ? "PASS" : "FAIL"
        Log.app.info("SLO evaluation: \(status) (\(items.filter(\.passed).count)/\(items.count) passed)")
        for item in items where !item.passed {
            Log.app.warning("SLO FAIL: \(item.name) — actual=\(String(format: "%.4f", item.actualValue)) threshold=\(String(format: "%.4f", item.thresholdValue))")
        }

        return result
    }

    static func defaultDefinitions() -> [SLODefinition] {
        [
            // 가용성: 99.5% (1 - error/total >= 0.995)
            SLODefinition(
                name: "가용성",
                description: "서비스 가용성 99.5% 이상",
                metricName: MetricName.requestErrorTotal,
                denominatorMetricName: MetricName.requestTotal,
                conditionType: .ratio,
                thresholdValue: 0.995
            ),
            // 첫 partial 응답 p95: 2.0초
            SLODefinition(
                name: "첫 partial 응답 지연",
                description: "첫 partial 응답 p95 2.0초 이하",
                metricName: MetricName.firstPartialLatencyMs,
                conditionType: .percentile,
                percentileLevel: 0.95,
                thresholdValue: 2000.0
            ),
            // 승인 제외 전체 응답 p95: 8.0초
            SLODefinition(
                name: "전체 응답 지연",
                description: "승인 제외 전체 응답 p95 8.0초 이하",
                metricName: MetricName.totalResponseLatencyMs,
                conditionType: .percentile,
                percentileLevel: 0.95,
                thresholdValue: 8000.0
            ),
            // 세션 resume 성공률: 99%
            SLODefinition(
                name: "세션 resume 성공률",
                description: "세션 resume 성공률 99% 이상",
                metricName: MetricName.sessionResumeSuccess,
                denominatorMetricName: MetricName.sessionResumeTotal,
                conditionType: .ratio,
                thresholdValue: 0.99
            ),
        ]
    }

    // MARK: - Private

    private func evaluateDefinition(
        _ definition: SLODefinition,
        snapshot: MetricsSnapshot
    ) -> SLOItemResult {
        switch definition.conditionType {
        case .threshold:
            let actual = snapshot.gauge(name: definition.metricName)
            let passed = actual >= definition.thresholdValue
            return SLOItemResult(
                definitionId: definition.id,
                name: definition.name,
                passed: passed,
                actualValue: actual,
                thresholdValue: definition.thresholdValue,
                description: definition.description
            )

        case .percentile:
            let level = definition.percentileLevel ?? 0.95
            let histogram = snapshot.histogram(name: definition.metricName)
            let actual: Double
            if let histogram {
                if level >= 0.99 {
                    actual = histogram.p99
                } else if level >= 0.95 {
                    actual = histogram.p95
                } else {
                    actual = histogram.p50
                }
            } else {
                actual = 0.0
            }
            // percentile 조건: 실제값이 기준값 이하여야 통과
            let passed = actual <= definition.thresholdValue
            return SLOItemResult(
                definitionId: definition.id,
                name: definition.name,
                passed: passed,
                actualValue: actual,
                thresholdValue: definition.thresholdValue,
                description: definition.description
            )

        case .ratio:
            let numerator = snapshot.counter(name: definition.metricName)
            let denominator: Double
            if let denomName = definition.denominatorMetricName {
                denominator = snapshot.counter(name: denomName)
            } else {
                denominator = 1.0
            }

            let actual: Double
            if denominator > 0 {
                // ratio: 에러 메트릭인 경우 1 - (error/total), 성공 메트릭인 경우 success/total
                if definition.metricName.contains("error") {
                    actual = 1.0 - (numerator / denominator)
                } else {
                    actual = numerator / denominator
                }
            } else {
                // 분모가 0이면 데이터 없음 — 통과로 처리
                actual = 1.0
            }
            let passed = actual >= definition.thresholdValue
            return SLOItemResult(
                definitionId: definition.id,
                name: definition.name,
                passed: passed,
                actualValue: actual,
                thresholdValue: definition.thresholdValue,
                description: definition.description
            )
        }
    }
}
