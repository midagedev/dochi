import Foundation

// MARK: - TraceContextProtocol

/// 요청 단위 traceId 관리 프로토콜.
///
/// `@MainActor` 근거: 트레이스 상태가 UI (세션 탐색기, 디버그 패널)에서 관찰되며,
/// 활성 span 관리가 단일 스레드에서 일관성을 유지해야 한다.
@MainActor
protocol TraceContextProtocol {
    /// 새 트레이스를 시작하고 루트 span을 생성한다.
    func startTrace(name: String, metadata: [String: String]) -> TraceContext

    /// 현재 활성 트레이스 내에서 자식 span을 시작한다.
    func startSpan(name: String, traceId: UUID, parentSpanId: UUID?, attributes: [String: String]) -> TraceSpan

    /// span을 종료하고 소요 시간을 기록한다.
    func endSpan(_ span: TraceSpan, status: TraceSpanStatus)

    /// 지정 traceId의 모든 span을 조회한다.
    func spans(for traceId: UUID) -> [TraceSpan]

    /// 활성 트레이스 목록을 반환한다.
    var activeTraces: [TraceContext] { get }

    /// 완료된 트레이스를 포함한 전체 트레이스 목록을 반환한다.
    var allTraces: [TraceContext] { get }
}

// MARK: - RuntimeMetricsProtocol

/// 런타임 메트릭 수집 프로토콜.
///
/// `@MainActor` 근거: 메트릭 스냅샷이 SLO 게이트 UI 및 배포 대시보드에서
/// 관찰되므로 UI 스레드 격리가 필요하다.
@MainActor
protocol RuntimeMetricsProtocol {
    /// 카운터 메트릭을 증가시킨다.
    func incrementCounter(name: String, labels: [String: String], delta: Double)

    /// 히스토그램 메트릭에 값을 기록한다.
    func recordHistogram(name: String, labels: [String: String], value: Double)

    /// 게이지 메트릭 값을 설정한다.
    func setGauge(name: String, labels: [String: String], value: Double)

    /// 현재 메트릭 스냅샷을 생성한다.
    func snapshot() -> MetricsSnapshot

    /// 모든 메트릭을 초기화한다.
    func reset()
}

// MARK: - StructuredEventLoggerProtocol

/// 구조화 JSON 이벤트 로그 프로토콜.
///
/// `@MainActor` 근거: 이벤트 로그가 세션 탐색기 UI에서 실시간으로 표시되며,
/// 이벤트 순서 보장을 위해 단일 스레드 격리가 필요하다.
@MainActor
protocol StructuredEventLoggerProtocol {
    /// 구조화 이벤트를 기록한다.
    func log(event: StructuredEvent)

    /// 특정 traceId에 대한 이벤트를 조회한다.
    func events(for traceId: UUID) -> [StructuredEvent]

    /// 특정 세션에 대한 이벤트를 조회한다.
    func events(for sessionId: String) -> [StructuredEvent]

    /// 전체 이벤트를 조회한다.
    var allEvents: [StructuredEvent] { get }

    /// 이벤트를 JSON 파일로 내보낸다.
    func exportJSON(to url: URL) throws
}

// MARK: - SLOEvaluatorProtocol

/// SLO 평가 프로토콜.
///
/// `@MainActor` 근거: SLO 결과가 배포 게이트 UI에서 표시되며,
/// 메트릭 스냅샷 기반 판정이 UI 업데이트와 동기화되어야 한다.
@MainActor
protocol SLOEvaluatorProtocol {
    /// SLO 정의 목록.
    var definitions: [SLODefinition] { get }

    /// 메트릭 스냅샷을 기반으로 SLO 충족 여부를 평가한다.
    func evaluate(snapshot: MetricsSnapshot) -> SLOResult

    /// 기본 SLO 프리셋을 반환한다.
    static func defaultDefinitions() -> [SLODefinition]
}

// MARK: - RegressionEvaluatorProtocol

/// 회귀 평가 프로토콜.
///
/// `@MainActor` 근거: 평가 리포트가 UI에서 표시되며,
/// 시나리오 실행 결과가 UI 상태와 동기화되어야 한다.
@MainActor
protocol RegressionEvaluatorProtocol {
    /// 등록된 시나리오 목록.
    var scenarios: [RegressionScenario] { get }

    /// 시나리오를 등록한다.
    func registerScenario(_ scenario: RegressionScenario)

    /// 전체 시나리오를 실행하고 리포트를 생성한다.
    func runAll() async -> RegressionReport

    /// 특정 카테고리의 시나리오만 실행한다.
    func run(category: RegressionCategory) async -> RegressionReport

    /// 마지막 실행 리포트를 반환한다.
    var lastReport: RegressionReport? { get }
}
