import Foundation
import os

// MARK: - Regression Data Models

/// 회귀 평가 카테고리.
enum RegressionCategory: String, Codable, Sendable, CaseIterable {
    case family       // 가족 도메인 (일정/아이 대화)
    case development  // 개발 도메인 (코드 리뷰/세션 재개)
    case personal     // 개인 컨텍스트 회상
}

/// 평가 항목 (채점 기준).
enum RegressionCriterion: String, Codable, Sendable, CaseIterable {
    case factAccuracy          // 사실 일치율
    case policyCompliance      // 권한 정책 준수율
    case toolCallEfficiency    // 불필요 도구 호출률 (낮을수록 좋음)
    case responseLatency       // 응답 지연
}

/// 회귀 평가 시나리오.
struct RegressionScenario: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let category: RegressionCategory
    let description: String
    /// 시뮬레이션할 입력 메시지.
    let input: String
    /// 기대 결과 키워드 또는 패턴.
    let expectedOutput: [String]
    /// 적용할 평가 기준.
    let criteria: [RegressionCriterion]
    /// 각 기준별 임계값 (0.0~1.0).
    let thresholds: [RegressionCriterion: Double]

    init(
        id: UUID = UUID(),
        name: String,
        category: RegressionCategory,
        description: String,
        input: String,
        expectedOutput: [String],
        criteria: [RegressionCriterion] = RegressionCriterion.allCases,
        thresholds: [RegressionCriterion: Double] = [:]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.input = input
        self.expectedOutput = expectedOutput
        self.criteria = criteria
        self.thresholds = thresholds
    }
}

/// 시나리오별 결과.
struct RegressionScenarioResult: Identifiable, Codable, Sendable {
    let id: UUID
    let scenarioId: UUID
    let scenarioName: String
    let category: RegressionCategory
    let passed: Bool
    /// 각 기준별 점수 (0.0~1.0).
    let scores: [RegressionCriterion: Double]
    /// 실행 소요 시간 (밀리초).
    let durationMs: Double
    /// 상세 설명.
    let details: String

    init(
        id: UUID = UUID(),
        scenarioId: UUID,
        scenarioName: String,
        category: RegressionCategory,
        passed: Bool,
        scores: [RegressionCriterion: Double],
        durationMs: Double,
        details: String
    ) {
        self.id = id
        self.scenarioId = scenarioId
        self.scenarioName = scenarioName
        self.category = category
        self.passed = passed
        self.scores = scores
        self.durationMs = durationMs
        self.details = details
    }
}

/// 카테고리별 요약.
struct RegressionCategorySummary: Codable, Sendable {
    let category: RegressionCategory
    let total: Int
    let passed: Int
    let failed: Int
    let passRate: Double
    let averageScores: [RegressionCriterion: Double]
}

/// 회귀 평가 리포트.
struct RegressionReport: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let results: [RegressionScenarioResult]
    let categorySummaries: [RegressionCategorySummary]
    let overallPassRate: Double
    let totalDurationMs: Double

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        results: [RegressionScenarioResult],
        categorySummaries: [RegressionCategorySummary],
        overallPassRate: Double,
        totalDurationMs: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.results = results
        self.categorySummaries = categorySummaries
        self.overallPassRate = overallPassRate
        self.totalDurationMs = totalDurationMs
    }
}

// MARK: - Scenario Runner Protocol

/// 시나리오 실행기 — 실제 LLM 호출 등을 추상화.
@MainActor
protocol RegressionScenarioRunner {
    /// 시나리오를 실행하고 결과를 반환한다.
    func run(scenario: RegressionScenario) async -> RegressionScenarioResult
}

// MARK: - Default Scenario Runner

/// 기본 시나리오 실행기 — 키워드 매칭 기반 로컬 평가.
/// 실제 LLM 호출 없이 기대 출력 키워드 포함 여부로 판정한다.
@MainActor
final class LocalRegressionScenarioRunner: RegressionScenarioRunner {
    /// 시뮬레이션된 응답 (테스트용). nil이면 기본 빈 응답.
    var simulatedResponses: [UUID: String] = [:]

    func run(scenario: RegressionScenario) async -> RegressionScenarioResult {
        let startTime = Date()

        // 시뮬레이션된 응답을 사용하거나 빈 응답
        let response = simulatedResponses[scenario.id] ?? ""

        var scores: [RegressionCriterion: Double] = [:]

        for criterion in scenario.criteria {
            switch criterion {
            case .factAccuracy:
                // 기대 출력 키워드가 응답에 포함되는 비율
                if scenario.expectedOutput.isEmpty {
                    scores[criterion] = 1.0
                } else {
                    let matched = scenario.expectedOutput.filter { response.contains($0) }.count
                    scores[criterion] = Double(matched) / Double(scenario.expectedOutput.count)
                }

            case .policyCompliance:
                // 기본값: 정책 위반 키워드가 없으면 통과
                let violations = ["비밀번호", "API_KEY", "secret", "password"]
                let hasViolation = violations.contains { response.lowercased().contains($0.lowercased()) }
                scores[criterion] = hasViolation ? 0.0 : 1.0

            case .toolCallEfficiency:
                // 도구 호출 없으면 최적 (시뮬레이션)
                scores[criterion] = 1.0

            case .responseLatency:
                // 로컬 실행이므로 거의 즉시 응답
                let elapsed = Date().timeIntervalSince(startTime) * 1000.0
                scores[criterion] = elapsed < 100 ? 1.0 : max(0, 1.0 - (elapsed / 10000.0))
            }
        }

        let durationMs = Date().timeIntervalSince(startTime) * 1000.0

        // 각 기준별 임계값과 비교
        let passed = scenario.criteria.allSatisfy { criterion in
            let score = scores[criterion] ?? 0.0
            let threshold = scenario.thresholds[criterion] ?? 0.7
            return score >= threshold
        }

        return RegressionScenarioResult(
            scenarioId: scenario.id,
            scenarioName: scenario.name,
            category: scenario.category,
            passed: passed,
            scores: scores,
            durationMs: durationMs,
            details: passed ? "모든 기준 통과" : "일부 기준 미달"
        )
    }
}

// MARK: - Default Scenarios

/// 기본 회귀 평가 시나리오셋 (최소 8개: 가족 3, 개발 3, 개인 2).
enum DefaultRegressionScenarios {
    static func all() -> [RegressionScenario] {
        familyScenarios() + developmentScenarios() + personalScenarios()
    }

    static func familyScenarios() -> [RegressionScenario] {
        [
            RegressionScenario(
                name: "가족 일정 조회",
                category: .family,
                description: "오늘의 가족 일정을 물어본다",
                input: "오늘 가족 일정 알려줘",
                expectedOutput: ["일정", "캘린더"],
                criteria: [.factAccuracy, .policyCompliance],
                thresholds: [.factAccuracy: 0.5, .policyCompliance: 1.0]
            ),
            RegressionScenario(
                name: "아이 대화 모드",
                category: .family,
                description: "아이 프로필로 전환 후 적절한 언어 사용 확인",
                input: "공룡에 대해 알려줘!",
                expectedOutput: ["공룡"],
                criteria: [.policyCompliance, .toolCallEfficiency],
                thresholds: [.policyCompliance: 1.0, .toolCallEfficiency: 0.8]
            ),
            RegressionScenario(
                name: "가족 리마인더 생성",
                category: .family,
                description: "내일 오후 3시 알림 생성 요청",
                input: "내일 오후 3시에 아이 학원 데려다주기 알림 만들어줘",
                expectedOutput: ["알림", "학원"],
                criteria: [.factAccuracy, .responseLatency],
                thresholds: [.factAccuracy: 0.5, .responseLatency: 0.5]
            ),
        ]
    }

    static func developmentScenarios() -> [RegressionScenario] {
        [
            RegressionScenario(
                name: "코드 리뷰 요청",
                category: .development,
                description: "Swift 파일 코드 리뷰 요청",
                input: "이 Swift 파일 코드 리뷰해줘",
                expectedOutput: ["리뷰", "코드"],
                criteria: [.policyCompliance, .responseLatency],
                thresholds: [.policyCompliance: 1.0, .responseLatency: 0.5]
            ),
            RegressionScenario(
                name: "개발 세션 재개",
                category: .development,
                description: "이전 코딩 세션 재개 요청",
                input: "아까 하던 개발 세션 이어서 하자",
                expectedOutput: ["세션"],
                criteria: [.factAccuracy, .policyCompliance],
                thresholds: [.factAccuracy: 0.5, .policyCompliance: 1.0]
            ),
            RegressionScenario(
                name: "Git 상태 확인",
                category: .development,
                description: "현재 리포지토리 git status 확인",
                input: "현재 깃 상태 확인해줘",
                expectedOutput: ["git", "상태"],
                criteria: [.toolCallEfficiency, .responseLatency],
                thresholds: [.toolCallEfficiency: 0.8, .responseLatency: 0.5]
            ),
        ]
    }

    static func personalScenarios() -> [RegressionScenario] {
        [
            RegressionScenario(
                name: "개인 기억 회상",
                category: .personal,
                description: "이전에 공유된 개인 정보 기억 확인",
                input: "내가 좋아하는 음식이 뭐였지?",
                expectedOutput: ["음식"],
                criteria: [.factAccuracy, .toolCallEfficiency],
                thresholds: [.factAccuracy: 0.5, .toolCallEfficiency: 0.8]
            ),
            RegressionScenario(
                name: "개인 선호도 업데이트",
                category: .personal,
                description: "응답 언어 선호도 변경 요청",
                input: "앞으로 코드 설명할 때 한국어로 해줘",
                expectedOutput: ["한국어"],
                criteria: [.factAccuracy, .policyCompliance],
                thresholds: [.factAccuracy: 0.5, .policyCompliance: 1.0]
            ),
        ]
    }
}

// MARK: - RegressionEvaluator

/// 회귀 평가 실행 및 리포트 생성.
@MainActor
@Observable
final class RegressionEvaluator: RegressionEvaluatorProtocol {
    private(set) var scenarios: [RegressionScenario] = []
    private(set) var lastReport: RegressionReport?

    private let runner: RegressionScenarioRunner

    init(runner: RegressionScenarioRunner? = nil, registerDefaults: Bool = false) {
        self.runner = runner ?? LocalRegressionScenarioRunner()
        if registerDefaults {
            for scenario in DefaultRegressionScenarios.all() {
                scenarios.append(scenario)
            }
        }
    }

    // MARK: - RegressionEvaluatorProtocol

    func registerScenario(_ scenario: RegressionScenario) {
        scenarios.append(scenario)
        Log.app.debug("Regression scenario registered: \(scenario.name) [\(scenario.category.rawValue)]")
    }

    func runAll() async -> RegressionReport {
        return await runScenarios(scenarios)
    }

    func run(category: RegressionCategory) async -> RegressionReport {
        let filtered = scenarios.filter { $0.category == category }
        return await runScenarios(filtered)
    }

    // MARK: - Private

    private func runScenarios(_ scenariosToRun: [RegressionScenario]) async -> RegressionReport {
        let overallStart = Date()
        var results: [RegressionScenarioResult] = []

        for scenario in scenariosToRun {
            let result = await runner.run(scenario: scenario)
            results.append(result)
            let status = result.passed ? "PASS" : "FAIL"
            Log.app.info("Regression [\(status)] \(scenario.name)")
        }

        let totalDurationMs = Date().timeIntervalSince(overallStart) * 1000.0

        // 카테고리별 요약
        let categorySummaries = RegressionCategory.allCases.compactMap { category -> RegressionCategorySummary? in
            let categoryResults = results.filter { $0.category == category }
            guard !categoryResults.isEmpty else { return nil }

            let passed = categoryResults.filter(\.passed).count
            let total = categoryResults.count

            // 카테고리 내 평균 점수
            var averageScores: [RegressionCriterion: Double] = [:]
            for criterion in RegressionCriterion.allCases {
                let scores = categoryResults.compactMap { $0.scores[criterion] }
                if !scores.isEmpty {
                    averageScores[criterion] = scores.reduce(0, +) / Double(scores.count)
                }
            }

            return RegressionCategorySummary(
                category: category,
                total: total,
                passed: passed,
                failed: total - passed,
                passRate: Double(passed) / Double(total),
                averageScores: averageScores
            )
        }

        let overallPassRate = results.isEmpty ? 0.0 : Double(results.filter(\.passed).count) / Double(results.count)

        let report = RegressionReport(
            results: results,
            categorySummaries: categorySummaries,
            overallPassRate: overallPassRate,
            totalDurationMs: totalDurationMs
        )

        lastReport = report
        Log.app.info("Regression report: \(results.count) scenarios, \(String(format: "%.1f%%", overallPassRate * 100)) pass rate, \(String(format: "%.1fms", totalDurationMs))")

        return report
    }
}
