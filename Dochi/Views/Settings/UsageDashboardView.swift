import SwiftUI
import Charts

/// Settings > AI > Usage dashboard showing token usage, cost, and budget.
struct UsageDashboardView: View {
    let metricsCollector: MetricsCollector
    let settings: AppSettings
    var resourceOptimizer: (any ResourceOptimizerProtocol)?

    @State private var selectedPeriod: Period = .thisMonth
    @State private var chartMode: ChartMode = .cost
    @State private var breakdownMode: BreakdownMode = .model
    @State private var summary: MonthlyUsageSummary?
    @State private var allMonthsSummaries: [MonthlyUsageSummary] = []
    @State private var isLoading = true
    @State private var utilizations: [ResourceUtilization] = []
    @State private var monitoringSnapshots: [UUID: SubscriptionMonitoringSnapshot] = [:]
    @State private var showSubscriptionSheet = false
    @State private var editingSubscription: SubscriptionPlan?
    @State private var showDeleteConfirm = false
    @State private var deletingSubscriptionId: UUID?

    enum Period: String, CaseIterable {
        case today = "오늘"
        case thisWeek = "이번 주"
        case thisMonth = "이번 달"
        case all = "전체"
    }

    enum ChartMode: String, CaseIterable {
        case cost = "비용"
        case tokens = "토큰"
    }

    enum BreakdownMode: String, CaseIterable {
        case model = "모델별"
        case agent = "에이전트별"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Period selector
                Picker("기간", selection: $selectedPeriod) {
                    ForEach(Period.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                usageAxisHeader(
                    title: "종량제 (Dochi API)",
                    detail: "UsageStore 기반 토큰/비용 집계"
                )
                .padding(.horizontal)

                if isLoading {
                    ProgressView("로딩 중...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let summary {
                    // Summary cards
                    summaryCards(summary)
                        .padding(.horizontal)

                    if let deviationReport = metricsCollector.tokenEstimationDeviationReport {
                        tokenEstimatorHealthSection(deviationReport)
                            .padding(.horizontal)
                    }

                    // Chart
                    chartSection(summary)
                        .padding(.horizontal)

                    // Breakdown table
                    breakdownSection(summary)
                        .padding(.horizontal)
                } else {
                    emptyState
                }

                Divider()
                    .padding(.horizontal)

                // Budget settings
                budgetSection
                    .padding(.horizontal)

                if let resourceOptimizer {
                    Divider()
                        .padding(.horizontal)

                    // Subscription plan cards
                    subscriptionCardsSection()
                        .padding(.horizontal)

                    // Auto task settings
                    autoTaskSection
                        .padding(.horizontal)

                    // Subscription management
                    subscriptionManagementSection(resourceOptimizer)
                        .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .task {
            await loadData()
            await loadUtilizations()
        }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await loadData() }
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            SubscriptionEditSheet(
                subscription: editingSubscription,
                onSave: { plan in
                    guard let optimizer = resourceOptimizer else { return }
                    Task {
                        if editingSubscription != nil {
                            await optimizer.updateSubscription(plan)
                        } else {
                            await optimizer.addSubscription(plan)
                        }
                        await loadUtilizations()
                    }
                    editingSubscription = nil
                    showSubscriptionSheet = false
                },
                onCancel: {
                    editingSubscription = nil
                    showSubscriptionSheet = false
                }
            )
        }
        .alert("구독 삭제", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) {
                guard let id = deletingSubscriptionId else { return }
                Task {
                    await resourceOptimizer?.deleteSubscription(id: id)
                    await loadUtilizations()
                }
                deletingSubscriptionId = nil
            }
            Button("취소", role: .cancel) {
                deletingSubscriptionId = nil
            }
        } message: {
            Text("이 구독 플랜을 삭제하시겠습니까?")
        }
    }

    // MARK: - Summary Cards

    private func usageAxisHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func summaryCards(_ summary: MonthlyUsageSummary) -> some View {
        let filtered = filteredDays(from: summary)
        let exchanges = filtered.reduce(0) { $0 + $1.totalExchanges }
        let inputTokens = filtered.reduce(0) { $0 + $1.totalInputTokens }
        let outputTokens = filtered.reduce(0) { $0 + $1.totalOutputTokens }
        let cost = filtered.reduce(0.0) { $0 + $1.totalCostUSD }

        return HStack(spacing: 12) {
            summaryCard(title: "교환 수", value: "\(exchanges)", icon: "arrow.left.arrow.right")
            summaryCard(title: "입력 토큰", value: formatTokens(inputTokens), icon: "arrow.up.doc")
            summaryCard(title: "출력 토큰", value: formatTokens(outputTokens), icon: "arrow.down.doc")
            summaryCard(title: "추정 비용", value: formatCost(cost), icon: "dollarsign.circle")
        }
    }

    private func summaryCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tokenEstimatorHealthSection(_ report: TokenEstimationDeviationReport) -> some View {
        let p95Percent = report.p95RelativeErrorRatio * 100
        let thresholdPercent = report.thresholdRatio * 100
        let meanPercent = report.meanRelativeErrorRatio * 100
        let alertColor: Color = report.meetsThreshold ? .green : .orange
        let headline = report.meetsThreshold
            ? "토큰 추정 정확도 정상"
            : "토큰 추정 drift 경고"
        let detail = metricsCollector.tokenEstimationDriftAlertMessage ??
            String(
                format: "토큰 추정 p95 %.1f%% (임계 %.1f%%)",
                p95Percent,
                thresholdPercent
            )

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(headline, systemImage: report.meetsThreshold ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(alertColor)
                Spacer()
                Text("샘플 \(report.sampleCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(report.meetsThreshold ? Color.secondary : Color.orange)

            HStack(spacing: 12) {
                Text(String(format: "p95 %.1f%%", p95Percent))
                    .font(.system(size: 10, design: .monospaced))
                Text(String(format: "mean %.1f%%", meanPercent))
                    .font(.system(size: 10, design: .monospaced))
                Text(String(format: "max %.1f%%", report.maxRelativeErrorRatio * 100))
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.secondary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(alertColor.opacity(0.25), lineWidth: report.meetsThreshold ? 0 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Chart Section

    private func chartSection(_ summary: MonthlyUsageSummary) -> some View {
        let filtered = filteredDays(from: summary)
        let chartData: [(label: String, value: Double)] = filtered.map { day in
            let label = String(day.date.suffix(5))
            let value: Double = chartMode == .cost
                ? day.totalCostUSD
                : Double(day.totalInputTokens + day.totalOutputTokens)
            return (label, value)
        }
        let yLabel: String = chartMode == .cost ? "USD" : "토큰"

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("일별 추이")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            if chartData.isEmpty {
                Text("데이터가 없습니다")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(chartData, id: \.label) { item in
                        BarMark(
                            x: .value("날짜", item.label),
                            y: .value(yLabel, item.value)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(3)
                    }
                }
                .chartYAxisLabel(yLabel)
                .frame(height: 180)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Breakdown Section

    private func breakdownSection(_ summary: MonthlyUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("분류")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("", selection: $breakdownMode) {
                    ForEach(BreakdownMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            let filtered = filteredDays(from: summary)
            let breakdown = computeBreakdown(from: filtered)
            let totalCost = breakdown.reduce(0.0) { $0 + $1.cost }

            if breakdown.isEmpty {
                Text("데이터가 없습니다")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(breakdown, id: \.name) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 11))
                            .frame(width: 140, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { geo in
                            let ratio = totalCost > 0 ? item.cost / totalCost : 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: max(2, geo.size.width * ratio))
                        }
                        .frame(height: 12)

                        Text(formatCost(item.cost))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 70, alignment: .trailing)

                        let pct = totalCost > 0 ? (item.cost / totalCost) * 100 : 0
                        Text(String(format: "%.0f%%", pct))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Budget Section

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("예산 설정")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.budgetEnabled },
                    set: { settings.budgetEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if settings.budgetEnabled {
                HStack {
                    Text("월 예산")
                        .font(.system(size: 12))
                    Spacer()
                    HStack(spacing: 2) {
                        Text("$")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("10.00", value: Binding(
                            get: { settings.monthlyBudgetUSD },
                            set: { settings.monthlyBudgetUSD = $0 }
                        ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .font(.system(size: 12, design: .monospaced))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("알림 기준")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Toggle("50% 도달 시", isOn: Binding(
                        get: { settings.budgetAlert50 },
                        set: { settings.budgetAlert50 = $0 }
                    ))
                    .font(.system(size: 12))
                    Toggle("80% 도달 시", isOn: Binding(
                        get: { settings.budgetAlert80 },
                        set: { settings.budgetAlert80 = $0 }
                    ))
                    .font(.system(size: 12))
                    Toggle("100% 도달 시", isOn: Binding(
                        get: { settings.budgetAlert100 },
                        set: { settings.budgetAlert100 = $0 }
                    ))
                    .font(.system(size: 12))
                }

                Toggle("예산 초과 시 요청 차단", isOn: Binding(
                    get: { settings.budgetBlockOnExceed },
                    set: { settings.budgetBlockOnExceed = $0 }
                ))
                .font(.system(size: 12))

                if settings.budgetBlockOnExceed {
                    Text("예산 초과 시 LLM 요청이 차단됩니다. 주의하세요.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                // Current month budget usage bar
                if let summary {
                    let currentCost = summary.totalCostUSD
                    let budget = settings.monthlyBudgetUSD
                    let ratio = budget > 0 ? min(currentCost / budget, 1.5) : 0

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("이번 달 사용량")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(formatCost(currentCost)) / \(formatCost(budget))")
                                .font(.system(size: 11, design: .monospaced))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.secondary.opacity(0.15))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(budgetBarColor(ratio: ratio))
                                    .frame(width: max(0, min(geo.size.width, geo.size.width * ratio)))
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("사용량 데이터가 없습니다")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("대화를 시작하면 API 사용량이 여기에 표시됩니다.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        guard let store = metricsCollector.usageStore else {
            isLoading = false
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let currentMonth = formatter.string(from: Date())

        summary = await store.monthlySummary(for: currentMonth)

        if selectedPeriod == .all {
            let months = await store.allMonths()
            var summaries: [MonthlyUsageSummary] = []
            for month in months {
                let s = await store.monthlySummary(for: month)
                summaries.append(s)
            }
            allMonthsSummaries = summaries
        }

        isLoading = false
    }

    // MARK: - Filtering

    private func filteredDays(from summary: MonthlyUsageSummary) -> [DailyUsageRecord] {
        let calendar = Calendar.current
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        switch selectedPeriod {
        case .today:
            let todayStr = dayFormatter.string(from: now)
            return summary.days.filter { $0.date == todayStr }

        case .thisWeek:
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
                return summary.days
            }
            let weekStartStr = dayFormatter.string(from: weekStart)
            return summary.days.filter { $0.date >= weekStartStr }

        case .thisMonth:
            return summary.days

        case .all:
            // Combine all months' days
            return allMonthsSummaries.flatMap(\.days).sorted { $0.date < $1.date }
        }
    }

    // MARK: - Breakdown

    private struct BreakdownItem: Sendable {
        let name: String
        let cost: Double
    }

    private func computeBreakdown(from days: [DailyUsageRecord]) -> [BreakdownItem] {
        var map: [String: Double] = [:]
        for day in days {
            for entry in day.entries {
                let key = breakdownMode == .model ? entry.model : entry.agentName
                map[key, default: 0] += entry.estimatedCostUSD
            }
        }
        return map
            .map { BreakdownItem(name: $0.key, cost: $0.value) }
            .sorted { $0.cost > $1.cost }
    }

    // MARK: - Subscription Cards Section

    private func subscriptionCardsSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            usageAxisHeader(
                title: "구독제 (Subscription)",
                detail: "구독 플랜별 잔여량과 낭비 위험 추적"
            )

            if utilizations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("등록된 구독 플랜이 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("구독을 등록하면 사용량을 추적하고 낭비를 방지합니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Button("구독 추가") {
                        editingSubscription = nil
                        showSubscriptionSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(SubscriptionUsageSource.allCases, id: \.self) { source in
                    let sourceUtilizations = utilizations.filter { $0.subscription.usageSource == source }
                    if !sourceUtilizations.isEmpty {
                        subscriptionSourceSection(source: source, utilizations: sourceUtilizations)
                    }
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func subscriptionSourceSection(
        source: SubscriptionUsageSource,
        utilizations: [ResourceUtilization]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.axisSectionTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(utilizations, id: \.subscription.id) { util in
                subscriptionCard(util)
            }
        }
        .padding(10)
        .background(.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func subscriptionCard(_ util: ResourceUtilization) -> some View {
        let snapshot = monitoringSnapshots[util.subscription.id]
        let status = snapshot?.statusPresentation

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(util.subscription.providerName)
                    .font(.system(size: 12, weight: .semibold))
                Text(util.subscription.planName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                riskBadge(util.riskLevel)
            }

            HStack(spacing: 6) {
                providerBadge(util.subscription.providerName)
                usageSourceBadge(util.subscription.usageSource)
                if let status {
                    monitoringStatusBadge(status)
                } else {
                    monitoringStatusBadge(
                        MonitoringStatusPresentation(
                            label: "수집 대기",
                            detail: nil,
                            tone: .neutral
                        )
                    )
                }
                Text(util.subscription.usageSource.detailText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text("최근 수집:")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let collectedAt = snapshot?.lastCollectedAt {
                        Text(collectedAt, style: .relative)
                            .font(.system(size: 10, weight: .medium))
                    } else {
                        Text("없음")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("최근 수집")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let collectedAt = snapshot?.lastCollectedAt {
                        Text(collectedAt, style: .relative)
                            .font(.system(size: 10, weight: .medium))
                    } else {
                        Text("없음")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let status, let detail = status.detail, !detail.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: monitoringStatusIcon(status.tone))
                        .font(.system(size: 10))
                        .foregroundStyle(monitoringStatusColor(status.tone))
                        .padding(.top, 1)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(monitoringStatusColor(status.tone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Usage gauge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(riskColor(util.riskLevel))
                        .frame(width: max(0, min(geo.size.width, geo.size.width * util.usageRatio)))
                }
            }
            .frame(height: 8)

            ViewThatFits(in: .horizontal) {
                HStack {
                    usageAmountText(util)
                    Spacer()
                    Text("리셋일: 매월 \(util.subscription.resetDayOfMonth)일")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("잔여: \(util.daysRemaining)일")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    usageAmountText(util)
                    Text("리셋일: 매월 \(util.subscription.resetDayOfMonth)일")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("잔여: \(util.daysRemaining)일")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if util.subscription.monthlyTokenLimit != nil {
                Text("예상 미사용: \(String(format: "%.0f", util.currentUnusedPercent))%")
                    .font(.system(size: 10))
                    .foregroundStyle(util.riskLevel == .wasteRisk ? .red : .secondary)

                Text(
                    "기간 종료 예상 사용률: \(String(format: "%.0f", util.projectedUsageRatio * 100))% · "
                        + "보존 버퍼: \(String(format: "%.0f", util.reserveBufferRatio * 100))%"
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func riskBadge(_ level: WasteRiskLevel) -> some View {
        Text(level.displayName)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(riskColor(level).opacity(0.15))
            .foregroundStyle(riskColor(level))
            .clipShape(Capsule())
    }

    private func riskColor(_ level: WasteRiskLevel) -> Color {
        switch level {
        case .comfortable: return .green
        case .caution: return .yellow
        case .wasteRisk: return .red
        case .normal: return .blue
        }
    }

    private func providerBadge(_ providerName: String) -> some View {
        Text(providerBadgeName(providerName))
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(providerBadgeColor(providerName).opacity(0.14))
            .foregroundStyle(providerBadgeColor(providerName))
            .clipShape(Capsule())
    }

    private func providerBadgeName(_ providerName: String) -> String {
        let normalized = providerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("claude") || normalized.contains("anthropic") {
            return "Claude"
        }
        if normalized.contains("gemini") {
            return "Gemini"
        }
        if normalized.contains("codex") || normalized.contains("chatgpt") {
            return "Codex"
        }
        if normalized.contains("openai") {
            return "OpenAI"
        }
        return providerName
    }

    private func providerBadgeColor(_ providerName: String) -> Color {
        let normalized = providerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("claude") || normalized.contains("anthropic") {
            return .orange
        }
        if normalized.contains("gemini") {
            return .green
        }
        if normalized.contains("codex") || normalized.contains("chatgpt") || normalized.contains("openai") {
            return .blue
        }
        return .gray
    }

    private func usageSourceBadge(_ source: SubscriptionUsageSource) -> some View {
        Text(source.displayName)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(usageSourceColor(source).opacity(0.14))
            .foregroundStyle(usageSourceColor(source))
            .clipShape(Capsule())
    }

    private func usageSourceColor(_ source: SubscriptionUsageSource) -> Color {
        switch source {
        case .externalToolLogs:
            return .indigo
        case .dochiUsageStore:
            return .teal
        }
    }

    private func monitoringStatusBadge(_ presentation: MonitoringStatusPresentation) -> some View {
        Text(presentation.label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(monitoringStatusColor(presentation.tone).opacity(0.14))
            .foregroundStyle(monitoringStatusColor(presentation.tone))
            .clipShape(Capsule())
    }

    private func monitoringStatusColor(_ tone: MonitoringStatusTone) -> Color {
        switch tone {
        case .success:
            return .green
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        case .neutral:
            return .gray
        }
    }

    private func monitoringStatusIcon(_ tone: MonitoringStatusTone) -> String {
        switch tone {
        case .success:
            return "checkmark.circle"
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        case .neutral:
            return "circle.dashed"
        }
    }

    @ViewBuilder
    private func usageAmountText(_ util: ResourceUtilization) -> some View {
        if let limit = util.subscription.monthlyTokenLimit {
            Text("사용: \(formatTokens(util.usedTokens)) / \(formatTokens(limit))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            Text("사용: \(formatTokens(util.usedTokens)) (무제한)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Auto Task Section

    private var autoTaskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("자동 작업 설정")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.resourceAutoTaskEnabled },
                    set: { settings.resourceAutoTaskEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if settings.resourceAutoTaskEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("자동 작업 유형")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    ForEach(AutoTaskType.allCases, id: \.rawValue) { taskType in
                        Toggle(isOn: autoTaskBinding(for: taskType)) {
                            HStack(spacing: 6) {
                                Image(systemName: taskType.icon)
                                    .font(.system(size: 11))
                                    .frame(width: 16)
                                Text(taskType.displayName)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                }

                Text("Heartbeat 설정 주기마다 조건을 평가하며, 같은 자동 작업은 구독별로 하루 1회만 큐잉됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("\"낭비 위험\" 시에만 실행", isOn: Binding(
                    get: { settings.resourceAutoTaskOnlyWasteRisk },
                    set: { settings.resourceAutoTaskOnlyWasteRisk = $0 }
                ))
                .font(.system(size: 12))

                if !settings.resourceAutoTaskOnlyWasteRisk {
                    Text("잔여 토큰이 있으면 항상 자동 작업을 실행합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isGitScanAutoTaskEnabled {
                    Divider()
                    if let latestGitScanRecord {
                        Text("Git 스캔 자동작업 상태: 최근 큐잉 \(latestGitScanRecord.executedAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !latestGitScanRecord.summary.isEmpty {
                            Text(latestGitScanRecord.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } else {
                        Text("Git 스캔 자동작업 상태: 아직 큐잉된 작업이 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func autoTaskBinding(for taskType: AutoTaskType) -> Binding<Bool> {
        Binding(
            get: {
                let enabled = settings.resourceAutoTaskTypes
                return enabled.contains(taskType.rawValue)
            },
            set: { newValue in
                var enabled = settings.resourceAutoTaskTypes
                if newValue {
                    if !enabled.contains(taskType.rawValue) {
                        enabled.append(taskType.rawValue)
                    }
                } else {
                    enabled.removeAll { $0 == taskType.rawValue }
                }
                settings.resourceAutoTaskTypes = enabled
            }
        )
    }

    // MARK: - Subscription Management Section

    private func subscriptionManagementSection(_ optimizer: any ResourceOptimizerProtocol) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("구독 플랜 관리")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    editingSubscription = nil
                    showSubscriptionSheet = true
                } label: {
                    Label("구독 추가", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if optimizer.subscriptions.isEmpty {
                Text("등록된 구독이 없습니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(optimizer.subscriptions) { sub in
                    HStack(spacing: 8) {
                        Text(sub.providerName)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 76, alignment: .leading)
                        Text(sub.planName)
                            .font(.system(size: 11))
                            .frame(width: 72, alignment: .leading)
                            .lineLimit(1)
                        Text(sub.usageSource.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 82, alignment: .leading)
                        if let limit = sub.monthlyTokenLimit {
                            Text(formatTokens(limit))
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 56, alignment: .trailing)
                        } else {
                            Text("무제한")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                        Text("매월 \(sub.resetDayOfMonth)일")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .trailing)
                        Spacer()
                        Button {
                            editingSubscription = sub
                            showSubscriptionSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        Button {
                            deletingSubscriptionId = sub.id
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.7))
                    }
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Utilization Loading

    private func loadUtilizations() async {
        guard let optimizer = resourceOptimizer else { return }
        let loaded = await optimizer.allUtilizations()
        utilizations = loaded
        monitoringSnapshots = await optimizer.monitoringSnapshots(for: loaded.map(\.subscription))
    }

    private var isGitScanAutoTaskEnabled: Bool {
        settings.resourceAutoTaskEnabled
            && settings.resourceAutoTaskTypes.contains(AutoTaskType.gitScanReview.rawValue)
    }

    private var latestGitScanRecord: AutoTaskRecord? {
        resourceOptimizer?
            .autoTaskRecords
            .filter { $0.taskType == .gitScanReview }
            .sorted { $0.executedAt > $1.executedAt }
            .first
    }

    // MARK: - Formatting

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private func formatCost(_ cost: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: cost)) ?? "$0.00"
    }

    private func budgetBarColor(ratio: Double) -> Color {
        if ratio >= 1.0 { return .red }
        if ratio >= 0.8 { return .orange }
        return .green
    }
}
