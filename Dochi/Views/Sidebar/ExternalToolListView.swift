import SwiftUI
#if os(macOS)
import AppKit
#endif

private enum SessionHistoryTimeFilter: String, CaseIterable, Identifiable {
    case day1 = "1d"
    case day7 = "7d"
    case day30 = "30d"
    case all = "all"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day1:
            return "최근 1일"
        case .day7:
            return "최근 7일"
        case .day30:
            return "최근 30일"
        case .all:
            return "전체"
        }
    }

    func sinceDate(now: Date = Date()) -> Date? {
        switch self {
        case .day1:
            return now.addingTimeInterval(-24 * 60 * 60)
        case .day7:
            return now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .day30:
            return now.addingTimeInterval(-30 * 24 * 60 * 60)
        case .all:
            return nil
        }
    }
}

private enum OrchestrationMonitorSeverity: Int {
    case error = 0
    case warning = 1
    case info = 2

    var color: Color {
        switch self {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .secondary
        }
    }

    var label: String {
        switch self {
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .info:
            return "info"
        }
    }
}

private struct OrchestrationMonitorEvent: Identifiable {
    let id: String
    let severity: OrchestrationMonitorSeverity
    let summary: String
    let timestamp: Date
}

@MainActor
@Observable
final class ExternalToolListSessionCache {
    var unifiedSessions: [UnifiedCodingSession] = []
    var discoveredSessions: [DiscoveredCodingSession] = []
    var gitInsights: [GitRepositoryInsight] = []
    var historyResults: [SessionHistorySearchResult] = []
    var historyIndexStatus = SessionHistoryIndexStatus(
        chunkCount: 0,
        lastIndexedAt: nil,
        latestChunkEndAt: nil
    )
    var kpiReport = SessionManagementKPIReport(
        generatedAt: Date(timeIntervalSince1970: 0),
        repositoryAssignmentSuccessRate: 0,
        dedupCorrectionRate: 0,
        activityClassificationAccuracy: nil,
        sessionSelectionFailureRate: 0,
        historySearchHitRate: 0,
        counters: SessionManagementKPICounters()
    )
    var subscriptionUtilizations: [ResourceUtilization] = []
    var subscriptionMonitoringSnapshots: [UUID: SubscriptionMonitoringSnapshot] = [:]
    var hasLoadedData = false
    var lastLoadedAt: Date?
}

struct ExternalToolListView: View {
    let manager: ExternalToolSessionManagerProtocol
    var resourceOptimizer: (any ResourceOptimizerProtocol)?
    var sessionCache: ExternalToolListSessionCache?
    @Binding var selectedSessionId: UUID?
    @Binding var selectedProfileId: UUID?
    @State private var showProfileEditor = false
    @State private var editingProfile: ExternalToolProfile?
    @State private var searchText = ""
    @State private var startingProfileId: UUID?
    @State private var startErrorMessage: String?
    @State private var unifiedSessions: [UnifiedCodingSession] = []
    @State private var discoveredSessions: [DiscoveredCodingSession] = []
    @State private var gitInsights: [GitRepositoryInsight] = []
    @State private var isRefreshingUnified = false
    @State private var explorerFilter = SessionExplorerFilter()
    @State private var sortOption: SessionExplorerSortOption = .activity
    @State private var mappingNotice: String?
    @State private var expandedRepositoryGroups: Set<String> = []
    @State private var didInitializeRepositoryExpansion = false
    @State private var focusedRepositoryKey: String?
    @State private var selectedUnifiedSessionKey: String?
    @State private var hoveredRepositoryKey: String?
    @State private var hoveredUnifiedSessionKey: String?
    @State private var selectedSessionDebugExpanded = false
    @State private var interactionErrorMessage: String?
    @State private var historyQueryText = ""
    @State private var historyRepositoryFilter: String?
    @State private var historyBranchFilter = ""
    @State private var historyTimeFilter: SessionHistoryTimeFilter = .day30
    @State private var historyLimit = 20
    @State private var historyResults: [SessionHistorySearchResult] = []
    @State private var historyIndexStatus = SessionHistoryIndexStatus(
        chunkCount: 0,
        lastIndexedAt: nil,
        latestChunkEndAt: nil
    )
    @State private var isHistoryIndexing = false
    @State private var isHistorySearching = false
    @State private var kpiReport = SessionManagementKPIReport(
        generatedAt: Date(timeIntervalSince1970: 0),
        repositoryAssignmentSuccessRate: 0,
        dedupCorrectionRate: 0,
        activityClassificationAccuracy: nil,
        sessionSelectionFailureRate: 0,
        historySearchHitRate: 0,
        counters: SessionManagementKPICounters()
    )
    @State private var orchestrationRepositoryRoot: String?
    @State private var orchestrationCommandText = ""
    @State private var orchestrationRequireConfirmation = false
    @State private var orchestrationSelection: OrchestrationSessionSelection?
    @State private var orchestrationGuardDecision: OrchestrationExecutionDecision?
    @State private var orchestrationStatusContract: OrchestrationStatusContractPayload?
    @State private var orchestrationSummarizeContract: OrchestrationSummarizeContractPayload?
    @State private var orchestrationOutputLines: [String] = []
    @State private var orchestrationBusy = false
    @State private var orchestrationErrorMessage: String?
    @State private var workboardLaneFilter: OrchestrationWorkboardLane?
    @State private var showExtendedInspectorSections = false
    @State private var subscriptionUtilizations: [ResourceUtilization] = []
    @State private var subscriptionMonitoringSnapshots: [UUID: SubscriptionMonitoringSnapshot] = [:]
    @State private var isRefreshingSubscriptionUsage = false
    private let orchestrationSummaryService = OrchestrationSummaryService()
    private static let orchestrationStatusCaptureLines = 120
    private static let orchestrationSummarizeCaptureLines = 160
    private static let orchestrationOutputPreviewLines = 3
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    private static let windowResetAbsoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
    @State private var unifiedAutoRefreshTask: Task<Void, Never>?

    private var runningSessions: [ExternalToolSession] {
        manager.sessions.filter { $0.status != .dead }
    }

    private var stoppedSessions: [ExternalToolSession] {
        manager.sessions.filter { $0.status == .dead }
    }

    private var unlaunchedProfiles: [ExternalToolProfile] {
        let activeProfileIds = Set(manager.sessions.map(\.profileId))
        return manager.profiles.filter { !activeProfileIds.contains($0.id) }
    }

    private var managedRepositories: [ManagedGitRepository] {
        manager.managedRepositories.filter { !$0.isArchived }
    }

    private var repositorySummaries: [RepositoryDashboardSummary] {
        SessionExplorerViewStateBuilder.repositorySummaries(from: unifiedSessions)
    }

    private var gitInsightByRepositoryPath: [String: GitRepositoryInsight] {
        var mapped: [String: GitRepositoryInsight] = [:]
        for insight in gitInsights {
            mapped[normalizedRepositoryPath(insight.path)] = insight
        }
        return mapped
    }

    private var repositorySessionGroups: [RepositorySessionGroup] {
        SessionExplorerViewStateBuilder.repositoryGroups(
            sessions: filteredUnifiedSessions.filter { !$0.isUnassigned },
            sort: sortOption
        )
    }

    private var selectedUnifiedSession: UnifiedCodingSession? {
        SessionExplorerViewStateBuilder.selectedSession(
            sessions: unifiedSessions,
            selectedSessionKey: selectedUnifiedSessionKey,
            selectedSessionId: selectedSessionId
        )
    }

    private var focusedRepositorySummary: RepositoryDashboardSummary? {
        SessionExplorerViewStateBuilder.selectedRepositorySummary(
            summaries: repositorySummaries,
            focusedRepositoryKey: focusedRepositoryKey
        )
    }

    private var dashboardChangeFeedTarget: (summary: RepositoryDashboardSummary, insight: GitRepositoryInsight?)? {
        if let focusedRepositorySummary {
            return (
                focusedRepositorySummary,
                repositoryInsight(for: focusedRepositorySummary.repositoryRoot)
            )
        }
        if let firstAssigned = repositorySummaries.first(where: { $0.repositoryRoot != nil }) {
            return (
                firstAssigned,
                repositoryInsight(for: firstAssigned.repositoryRoot)
            )
        }
        return nil
    }

    private var filteredUnifiedSessions: [UnifiedCodingSession] {
        let filtered = SessionExplorerViewStateBuilder.filteredSessions(
            sessions: unifiedSessions,
            filter: explorerFilter,
            sort: sortOption
        )
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return filtered }
        return filtered.filter { session in
            let haystack = [
                session.provider,
                session.nativeSessionId,
                session.path,
                session.repositoryRoot ?? "",
                session.workingDirectory ?? "",
                session.title ?? "",
                session.summary ?? "",
                session.originator ?? "",
                session.sessionSource ?? "",
                session.clientKind ?? "",
            ].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private var unassignedUnifiedSessions: [UnifiedCodingSession] {
        unifiedSessions
            .filter(\.isUnassigned)
            .sorted(by: ExternalToolSessionManager.isPreferredUnifiedSessionOrder(_:_:))
    }

    private var recentDiscoveredSessions: [DiscoveredCodingSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = discoveredSessions.filter { session in
            guard !query.isEmpty else { return true }
            let haystack = [
                session.provider,
                session.sessionId,
                session.path,
                session.workingDirectory ?? "",
                session.title ?? "",
                session.summary ?? "",
                session.originator ?? "",
                session.sessionSource ?? "",
                session.clientKind ?? "",
            ]
            .joined(separator: " ")
            .lowercased()
            return haystack.contains(query)
        }
        return Array(filtered.prefix(20))
    }

    private var repositoryFilterOptions: [String] {
        var options = Set(managedRepositories.map { normalizedRepositoryPath($0.rootPath) })
        options.formUnion(unifiedSessions.compactMap(\.repositoryRoot).map { normalizedRepositoryPath($0) })
        return options.sorted()
    }

    private var providerFilterOptions: [String] {
        Array(Set(unifiedSessions.map(\.provider))).sorted()
    }

    private var orchestrationFleetSnapshot: OrchestrationFleetSnapshot {
        SessionExplorerViewStateBuilder.orchestrationFleetSnapshot(
            sessions: unifiedSessions,
            providerLimit: 5
        )
    }

    private var overviewActiveSessions: [UnifiedCodingSession] {
        unifiedSessions
            .filter { $0.activityState == .active || $0.activityState == .idle }
            .sorted(by: ExternalToolSessionManager.isPreferredUnifiedSessionOrder(_:_:))
    }

    private var prioritizedSubscriptionUtilizations: [ResourceUtilization] {
        subscriptionUtilizations.sorted(by: { lhs, rhs in
            let lhsRank = riskRank(lhs.riskLevel)
            let rhsRank = riskRank(rhs.riskLevel)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.projectedUsageRatio != rhs.projectedUsageRatio {
                return lhs.projectedUsageRatio > rhs.projectedUsageRatio
            }
            return lhs.subscription.providerName.localizedCaseInsensitiveCompare(rhs.subscription.providerName) == .orderedAscending
        })
    }

    private var subscriptionRiskCount: Int {
        subscriptionUtilizations.filter { $0.riskLevel == .wasteRisk || $0.riskLevel == .caution }.count
    }

    private var totalSubscriptionUsedTokens: Int {
        subscriptionUtilizations.reduce(0) { partialResult, util in
            partialResult + util.usedTokens
        }
    }

    private var orchestrationWorkboardGroups: [OrchestrationWorkboardGroup] {
        let groups = SessionExplorerViewStateBuilder.orchestrationWorkboardGroups(
            sessions: filteredUnifiedSessions
        )
        guard let workboardLaneFilter else { return groups }
        return groups.filter { $0.lane == workboardLaneFilter }
    }

    private var orchestrationMonitorEvents: [OrchestrationMonitorEvent] {
        var events: [OrchestrationMonitorEvent] = []
        let now = Date()

        let blockedCount = filteredUnifiedSessions.filter {
            SessionExplorerViewStateBuilder.orchestrationWorkboardLane(for: $0) == .blocked
        }.count
        if blockedCount > 0 {
            events.append(
                OrchestrationMonitorEvent(
                    id: "blocked-count",
                    severity: .warning,
                    summary: "Blocked/Failing 세션 \(blockedCount)개",
                    timestamp: now
                )
            )
        }

        let runningCount = filteredUnifiedSessions.filter { $0.activityState == .active }.count
        if runningCount > 0 {
            events.append(
                OrchestrationMonitorEvent(
                    id: "running-count",
                    severity: .info,
                    summary: "Running 세션 \(runningCount)개",
                    timestamp: now
                )
            )
        }

        if let guardDecision = orchestrationGuardDecision {
            events.append(
                OrchestrationMonitorEvent(
                    id: "guard-decision",
                    severity: guardDecision.kind == .denied ? .error : .warning,
                    summary: "guard \(guardDecision.kind.rawValue) · \(guardDecision.reason)",
                    timestamp: now
                )
            )
        }

        if let status = orchestrationStatusContract {
            events.append(
                OrchestrationMonitorEvent(
                    id: "status-contract",
                    severity: monitorSeverity(for: status.resultKind),
                    summary: "status \(status.resultKind) · \(status.summary)",
                    timestamp: now
                )
            )
        }

        if let summarized = orchestrationSummarizeContract {
            events.append(
                OrchestrationMonitorEvent(
                    id: "summary-contract",
                    severity: monitorSeverity(for: summarized.resultKind),
                    summary: "summary \(summarized.resultKind) · \(summarized.summary)",
                    timestamp: now
                )
            )
        }

        if let orchestrationErrorMessage {
            events.append(
                OrchestrationMonitorEvent(
                    id: "orchestration-error",
                    severity: .error,
                    summary: orchestrationErrorMessage,
                    timestamp: now
                )
            )
        }

        for (index, line) in orchestrationOutputLines.suffix(4).enumerated() {
            events.append(
                OrchestrationMonitorEvent(
                    id: "output-\(index)",
                    severity: .info,
                    summary: line,
                    timestamp: now.addingTimeInterval(Double(-index))
                )
            )
        }

        return events.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity.rawValue < rhs.severity.rawValue
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id < rhs.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if manager.profiles.isEmpty && unifiedSessions.isEmpty {
                emptyStateView
            } else {
                listContent
            }

            Divider()

            // Add profile button
            Button {
                editingProfile = nil
                showProfileEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                    Text("프로파일 추가")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showProfileEditor) {
            ExternalToolProfileEditorView(
                manager: manager,
                existingProfile: editingProfile,
                onSave: { profile in
                    manager.saveProfile(profile)
                    showProfileEditor = false
                },
                onCancel: {
                    showProfileEditor = false
                }
            )
        }
        .alert(
            "세션 시작 실패",
            isPresented: Binding(
                get: { startErrorMessage != nil },
                set: { newValue in
                    if !newValue { startErrorMessage = nil }
                }
            ),
            actions: {
                Button("확인", role: .cancel) {
                    startErrorMessage = nil
                }
            },
            message: {
                Text(startErrorMessage ?? "")
            }
        )
        .alert(
            "세션 매핑",
            isPresented: Binding(
                get: { mappingNotice != nil },
                set: { newValue in
                    if !newValue { mappingNotice = nil }
                }
            ),
            actions: {
                Button("확인", role: .cancel) {
                    mappingNotice = nil
                }
            },
            message: {
                Text(mappingNotice ?? "")
            }
        )
        .alert(
            "동작 실행 실패",
            isPresented: Binding(
                get: { interactionErrorMessage != nil },
                set: { newValue in
                    if !newValue { interactionErrorMessage = nil }
                }
            ),
            actions: {
                Button("확인", role: .cancel) {
                    interactionErrorMessage = nil
                }
            },
            message: {
                Text(interactionErrorMessage ?? "")
            }
        )
        .task {
            restoreCachedStateIfNeeded()
            if shouldRunInitialRefresh() {
                async let unified: Void = refreshUnifiedSessions()
                async let subscription: Void = refreshSubscriptionUsageWithBootstrap()
                _ = await (unified, subscription)
                refreshHistoryIndexStatus()
                refreshKPIReport()
                persistSessionCache()
            } else {
                refreshHistoryIndexStatus()
                refreshKPIReport()
            }
        }
        .onAppear {
            restoreCachedStateIfNeeded()
            startUnifiedAutoRefreshLoop()
        }
        .onDisappear {
            unifiedAutoRefreshTask?.cancel()
            unifiedAutoRefreshTask = nil
            persistSessionCache()
        }
        .onChange(of: resourceOptimizer != nil) { _, available in
            guard available else { return }
            Task {
                await refreshSubscriptionUsageWithBootstrap()
            }
        }
        .onChange(of: explorerFilter.activeOnly) { _, _ in
            Task { await refreshUnifiedSessions() }
        }
        .onChange(of: selectedUnifiedSessionKey) { _, _ in
            selectedSessionDebugExpanded = false
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hammer")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("등록된 외부 AI 도구가 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Claude Code, Codex, aider 등을 추가하여\n도치에서 통합 관리하세요.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("프로파일 추가") {
                editingProfile = nil
                showProfileEditor = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                observabilitySectionHeader
                orchestrationFleetSnapshotSection
                repoDashboardSection
                codingPlanUsageSection
                orchestrationLoopSection
                orchestrationActiveAgentsSection
                orchestrationWorkboardSection
                orchestrationLiveMonitorSection
                orchestrationActionQueueSection
                extendedInspectorSection
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var orchestrationFleetSnapshotSection: some View {
        sectionHeader("Fleet Snapshot")

        let snapshot = orchestrationFleetSnapshot
        let metricColumns = [
            GridItem(.flexible(minimum: 80), spacing: 6),
            GridItem(.flexible(minimum: 80), spacing: 6),
            GridItem(.flexible(minimum: 80), spacing: 6),
        ]

        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 6) {
                fleetMetricBadge(title: "전체", value: "\(snapshot.totalSessionCount)", color: .secondary)
                fleetMetricBadge(title: "실행중", value: "\(snapshot.activeSessionCount)", color: .green)
                fleetMetricBadge(title: "대기", value: "\(snapshot.idleSessionCount)", color: .blue)
                fleetMetricBadge(title: "Blocked", value: "\(snapshot.blockedSessionCount)", color: .red)
                fleetMetricBadge(title: "Queue", value: "\(snapshot.queuedSessionCount)", color: .orange)
                fleetMetricBadge(title: "레포", value: "\(snapshot.repositoryCount)", color: .secondary)
                fleetMetricBadge(title: "미할당", value: "\(snapshot.unassignedSessionCount)", color: .orange)
                fleetMetricBadge(title: "개입 가능", value: "\(snapshot.actionableSessionCount)", color: .accentColor)
            }

            if !snapshot.providerBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider 분포")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(snapshot.providerBreakdown) { provider in
                                Text("\(provider.provider) \(provider.count)")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(snapshot.laneBreakdown) { lane in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(workboardLaneColor(lane.lane))
                                .frame(width: 6, height: 6)
                            Text("\(workboardLaneTitle(lane.lane)) \(lane.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var codingPlanUsageSection: some View {
        sectionHeader("Coding Plan Usage")

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("구독 코딩플랜 사용량")
                        .font(.system(size: 11, weight: .semibold))
                    Text("오케스트레이션 비용/낭비 리스크를 함께 모니터링")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRefreshingSubscriptionUsage {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button("새로고침") {
                    Task { await refreshSubscriptionUsage(forceRefresh: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if resourceOptimizer == nil {
                Text("구독 사용량 서비스를 찾을 수 없습니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if subscriptionUtilizations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("등록된 구독 플랜이 없습니다.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button("기본 플랜 자동 감지") {
                        Task {
                            await bootstrapSubscriptionsIfNeeded()
                            await refreshSubscriptionUsage(forceRefresh: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            } else {
                HStack(spacing: 8) {
                    fleetMetricBadge(title: "플랜", value: "\(subscriptionUtilizations.count)", color: .secondary)
                    fleetMetricBadge(title: "리스크", value: "\(subscriptionRiskCount)", color: .red)
                    fleetMetricBadge(title: "총 사용", value: formatTokenCount(totalSubscriptionUsedTokens), color: .accentColor)
                }

                ForEach(prioritizedSubscriptionUtilizations.prefix(4), id: \.subscription.id) { util in
                    subscriptionUsageCard(util)
                }

                if prioritizedSubscriptionUtilizations.count > 4 {
                    Text("추가 \(prioritizedSubscriptionUtilizations.count - 4)개 플랜은 사용량 설정 화면에서 확인하세요.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func subscriptionUsageCard(_ util: ResourceUtilization) -> some View {
        let snapshot = subscriptionMonitoringSnapshots[util.subscription.id]
        let status = snapshot?.statusPresentation
        let primaryWindow = snapshot?.primaryWindow
        let secondaryWindow = snapshot?.secondaryWindow
        let hasWindowMetrics = primaryWindow != nil || secondaryWindow != nil
        let usageRatio = primaryWindow?.usedRatio ?? (util.subscription.monthlyTokenLimit == nil ? 0 : max(0, min(1, util.usageRatio)))

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(util.subscription.providerName) · \(util.subscription.planName)")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(util.riskLevel.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(riskColor(util.riskLevel).opacity(0.16))
                    .foregroundStyle(riskColor(util.riskLevel))
                    .clipShape(Capsule())
            }

            HStack(spacing: 6) {
                Text(util.subscription.usageSource.displayName)
                    .font(.system(size: 9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(usageSourceColor(util.subscription.usageSource).opacity(0.16))
                    .foregroundStyle(usageSourceColor(util.subscription.usageSource))
                    .clipShape(Capsule())
                if let status {
                    Text(status.label)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(monitoringStatusColor(status.tone).opacity(0.16))
                        .foregroundStyle(monitoringStatusColor(status.tone))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(
                    compactResetLabel(
                        primaryWindow: primaryWindow,
                        secondaryWindow: secondaryWindow,
                        source: util.subscription.usageSource,
                        fallbackDaysRemaining: util.daysRemaining
                    )
                )
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(riskColor(util.riskLevel))
                        .frame(width: proxy.size.width * usageRatio)
                }
            }
            .frame(height: 7)

            HStack(spacing: 6) {
                Text(subscriptionUsageAmountText(util))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if util.subscription.usageSource == .externalToolLogs {
                    if let primaryWindow {
                        Text("\(Int(primaryWindow.usedPercent.rounded()))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("-")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("예상 \(Int((util.projectedUsageRatio * 100).rounded()))%")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            if util.subscription.usageSource == .externalToolLogs {
                if let primaryWindow {
                    compactWindowUsageBlock(primaryWindow, fallbackTitle: "세션")
                }
                if let secondaryWindow {
                    compactWindowUsageBlock(
                        secondaryWindow,
                        fallbackTitle: secondaryWindow.windowMinutes == 10_080 ? "주간" : "보조"
                    )
                }
                if !hasWindowMetrics {
                    Text("윈도우/리셋 정보 없음")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var orchestrationActiveAgentsSection: some View {
        sectionHeader("Active Agents")

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("활성/대기 에이전트 \(overviewActiveSessions.count)개")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("활성만 필터") {
                    explorerFilter.activeOnly = true
                    explorerFilter.unassignedOnly = false
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if overviewActiveSessions.isEmpty {
                Text("현재 활성 에이전트가 없습니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(
                    overviewActiveSessions.prefix(6).map {
                        (key: ExternalToolSessionManager.sessionStableKey($0), value: $0)
                    },
                    id: \.key
                ) { item in
                    unifiedSessionRow(item.value)
                }
                if overviewActiveSessions.count > 6 {
                    Text("추가 \(overviewActiveSessions.count - 6)개는 Workboard/Explorer에서 확인하세요.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var orchestrationWorkboardSection: some View {
        sectionHeader("Workboard")

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Menu("Lane") {
                    Button("전체") { workboardLaneFilter = nil }
                    ForEach(OrchestrationWorkboardLane.displayOrder, id: \.rawValue) { lane in
                        Button(workboardLaneTitle(lane)) {
                            workboardLaneFilter = lane
                        }
                    }
                }
                .font(.system(size: 10))

                Spacer()

                Text("\(filteredUnifiedSessions.count)개 세션")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if orchestrationWorkboardGroups.isEmpty {
                Text("표시할 Workboard 항목이 없습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(orchestrationWorkboardGroups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(workboardLaneColor(group.lane))
                                .frame(width: 7, height: 7)
                            Text(workboardLaneTitle(group.lane))
                                .font(.system(size: 10, weight: .semibold))
                            Spacer()
                            Text("\(group.sessions.count)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)

                        ForEach(
                            group.sessions.prefix(6).map {
                                (key: ExternalToolSessionManager.sessionStableKey($0), value: $0)
                            },
                            id: \.key
                        ) { item in
                            unifiedSessionRow(item.value)
                        }

                        if group.sessions.count > 6 {
                            Text("추가 \(group.sessions.count - 6)개 항목은 필터로 확인하세요.")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 4)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(workboardLaneColor(group.lane).opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 10)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var orchestrationLiveMonitorSection: some View {
        sectionHeader("Live Monitor")

        if orchestrationMonitorEvents.isEmpty {
            Text("최근 이벤트가 없습니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(orchestrationMonitorEvents.prefix(12)) { event in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(event.severity.color)
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.summary)
                                .font(.system(size: 10))
                                .lineLimit(2)
                            Text("\(event.severity.label) · \(relativeTimestamp(event.timestamp))")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var orchestrationActionQueueSection: some View {
        sectionHeader("Action Queue")

        VStack(alignment: .leading, spacing: 4) {
            if let command = nonEmptyOrchestrationCommand() {
                Text("명령: \(command)")
                    .font(.system(size: 10, weight: .semibold))
            }

            if orchestrationBusy {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("오케스트레이션 액션 실행 중")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let selection = orchestrationSelection {
                Text("selection \(selection.action.rawValue) · \(selection.reason)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let guardDecision = orchestrationGuardDecision {
                Text("guard \(guardDecision.kind.rawValue) · \(guardDecision.policyCode.rawValue)")
                    .font(.system(size: 10))
                    .foregroundStyle(guardDecision.kind == .denied ? .red : .secondary)
                    .lineLimit(1)
            }

            if let status = orchestrationStatusContract {
                Text("status \(status.resultKind): \(status.summary)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let summarized = orchestrationSummarizeContract {
                Text("summary \(summarized.resultKind): \(summarized.summary)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !orchestrationOutputLines.isEmpty {
                Text("output \(orchestrationOutputLines.suffix(Self.orchestrationOutputPreviewLines).joined(separator: " ⏎ "))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if let orchestrationErrorMessage {
                Text(orchestrationErrorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var extendedInspectorSection: some View {
        sectionHeader("Extended Inspector")

        DisclosureGroup(
            isExpanded: $showExtendedInspectorSections,
            content: {
                sessionExplorerSection
                selectionDetailSection
                discoveredSessionSection
                unassignedQueueSection
                sessionHistorySection

                Divider()
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if !runningSessions.isEmpty {
                    sectionHeader("실행 중")
                    ForEach(runningSessions) { session in
                        sessionRow(session: session)
                    }
                }

                if !stoppedSessions.isEmpty {
                    sectionHeader("중지됨")
                    ForEach(stoppedSessions) { session in
                        sessionRow(session: session)
                    }
                }

                if !unlaunchedProfiles.isEmpty {
                    sectionHeader("프로파일")
                    ForEach(unlaunchedProfiles) { profile in
                        profileRow(profile: profile)
                    }
                }
            },
            label: {
                Text("세션 탐색/히스토리/레거시 리스트 펼치기")
                    .font(.system(size: 11, weight: .semibold))
            }
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var observabilitySectionHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("오케스트레이션 콘솔")
                    .font(.system(size: 13, weight: .semibold))
                Text("상태 파악 → 개입 → 결과 확인 루프")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRefreshingUnified || isRefreshingSubscriptionUsage {
                ProgressView()
                    .controlSize(.small)
            }
            Button("새로고침") {
                Task {
                    await refreshUnifiedSessions()
                    await refreshSubscriptionUsage()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var repoDashboardSection: some View {
        sectionHeader("Project Status")

        if repositorySummaries.isEmpty {
            Text("표시할 레포 상태가 없습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(repositorySummaries) { summary in
                        let representative = representativeSession(for: summary.repositoryRoot)
                        let representativeTitle = representative.map {
                            SessionExplorerViewStateBuilder.displaySessionTitle(for: $0)
                        }
                        let workSummary = representative.flatMap { sessionWorkSummary($0) }
                        let insight = summary.repositoryRoot.flatMap { root in
                            gitInsightByRepositoryPath[normalizedRepositoryPath(root)]
                        }
                        let isFocused = focusedRepositoryKey == summary.id
                        let isHovered = hoveredRepositoryKey == summary.id
                        Button {
                            handleRepositoryCardTap(summary)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Text("세션 \(summary.sessionCount) · 활성 \(summary.activeSessionCount) · 오류 \(summary.errorSessionCount)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                if let representativeTitle {
                                    Text("대표 세션: \(representativeTitle)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("대표 세션: 표시 가능한 제목 없음")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                if let workSummary, let representative {
                                    Text("현재 작업: \(workSummary)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(workSummaryColor(representative))
                                        .lineLimit(2)
                                } else {
                                    Text("현재 작업: 현재 작업 정보 없음")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                if let repositoryRoot = summary.repositoryRoot {
                                    let managedBranch = managedRepositories.first(where: {
                                        normalizedRepositoryPath($0.rootPath) == normalizedRepositoryPath(repositoryRoot)
                                    })?.defaultBranch
                                    let branch = insight?.branch ?? managedBranch ?? "-"
                                    Text("브랜치 \(branch) · 업데이트 \(relativeTimestamp(representative?.updatedAt ?? summary.lastActivityAt))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    Text("변경: \(SessionExplorerViewStateBuilder.repositoryWorkingTreeLine(for: insight))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                    if let recentCommitLine = SessionExplorerViewStateBuilder
                                        .repositoryCommitFeedLines(for: insight, limit: 1)
                                        .first {
                                        Text("커밋: \(recentCommitLine)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    } else {
                                        Text("커밋: 최근 커밋 정보 없음")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                } else {
                                    Text("Unassigned · 업데이트 \(relativeTimestamp(representative?.updatedAt ?? summary.lastActivityAt))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(8)
                            .frame(width: 210, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isFocused ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.35) : Color.clear),
                                        lineWidth: isFocused ? 1.5 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .onHover { hovering in
                            if hovering {
                                hoveredRepositoryKey = summary.id
                            } else if hoveredRepositoryKey == summary.id {
                                hoveredRepositoryKey = nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.bottom, 4)

            repositoryRecentChangeFeedSection
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }

        HStack(spacing: 8) {
            kpiBadge(
                title: "Repo Assignment",
                value: percentString(kpiReport.repositoryAssignmentSuccessRate),
                detail: "\(kpiReport.counters.repositoryAssignedCount)/\(max(1, kpiReport.counters.repositoryTotalCount))"
            )
            kpiBadge(
                title: "Selection Failure",
                value: percentString(kpiReport.sessionSelectionFailureRate),
                detail: "\(kpiReport.counters.selectionFailureCount)/\(max(1, kpiReport.counters.selectionAttemptCount))"
            )
            kpiBadge(
                title: "History Hit",
                value: percentString(kpiReport.historySearchHitRate),
                detail: "\(kpiReport.counters.historySearchHitCount)/\(max(1, kpiReport.counters.historySearchQueryCount))"
            )
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var repositoryRecentChangeFeedSection: some View {
        if let target = dashboardChangeFeedTarget {
            let commitLines = SessionExplorerViewStateBuilder.repositoryCommitFeedLines(
                for: target.insight,
                limit: 5
            )
            let workingTreeLine = SessionExplorerViewStateBuilder.repositoryWorkingTreeLine(
                for: target.insight
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("최근 변경사항 · \(target.summary.displayName)")
                    .font(.system(size: 10, weight: .semibold))

                if commitLines.isEmpty {
                    Text("커밋: 최근 커밋 정보 없음")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(commitLines.enumerated()), id: \.offset) { index, line in
                        Text("커밋 \(index + 1): \(line)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text("워킹트리: \(workingTreeLine)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    @ViewBuilder
    private var discoveredSessionSection: some View {
        sectionHeader("Recent File Sessions")

        if recentDiscoveredSessions.isEmpty {
            Text("표시할 최근 파일 세션이 없습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            ForEach(recentDiscoveredSessions, id: \.path) { session in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("[\(session.provider)] \(session.sessionId)")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text("file")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if let title = normalizedDiscoveredTitle(session) {
                        Text(title)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }

                    if let summary = normalizedDiscoveredSummary(session) {
                        Text(summary)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let descriptor = discoveredClientDescriptor(session) {
                        Text(descriptor)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("업데이트 \(relativeTimestamp(session.updatedAt)) · \(session.workingDirectory ?? session.path)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var sessionExplorerSection: some View {
        sectionHeader("Repo Session Explorer")

        VStack(spacing: 6) {
            TextField("세션 검색 (provider/id/path)", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            HStack(spacing: 6) {
                Menu("repo") {
                    Button("전체") { explorerFilter.repositoryRoot = nil }
                    ForEach(repositoryFilterOptions, id: \.self) { root in
                        Button(root) { explorerFilter.repositoryRoot = root }
                    }
                }
                Menu("provider") {
                    Button("전체") { explorerFilter.provider = nil }
                    ForEach(providerFilterOptions, id: \.self) { provider in
                        Button(provider) { explorerFilter.provider = provider }
                    }
                }
                Menu("tier") {
                    Button("전체") { explorerFilter.tier = nil }
                    Button("T0") { explorerFilter.tier = .t0Full }
                    Button("T1") { explorerFilter.tier = .t1Attach }
                    Button("T2") { explorerFilter.tier = .t2Observe }
                    Button("T3") { explorerFilter.tier = .t3Unknown }
                }
                Menu("정렬") {
                    Button("활성도") { sortOption = .activity }
                    Button("최근 활동") { sortOption = .updatedAt }
                    Button("Provider") { sortOption = .provider }
                }
            }
            .font(.system(size: 10))
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Toggle("활성만", isOn: $explorerFilter.activeOnly)
                    .toggleStyle(.checkbox)
                Toggle("Unassigned만", isOn: $explorerFilter.unassignedOnly)
                    .toggleStyle(.checkbox)
                Spacer()
                Text("\(filteredUnifiedSessions.count)개")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)

        if repositorySessionGroups.isEmpty {
            Text("필터 조건에 맞는 세션이 없습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            ForEach(repositorySessionGroups) { group in
                repositoryGroupRow(group)
            }
        }
    }

    @ViewBuilder
    private var selectionDetailSection: some View {
        sectionHeader("Selection Detail")

        if let session = selectedUnifiedSession {
            selectedSessionDetailCard(session)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        } else if let repository = focusedRepositorySummary {
            selectedRepositoryDetailCard(repository)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        } else {
            Text("상세를 보려면 세션 또는 레포를 선택하세요.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func selectedSessionDetailCard(_ session: UnifiedCodingSession) -> some View {
        let runtimeUUID = session.runtimeSessionId.flatMap(UUID.init(uuidString:))
        let canOpenTerminal = runtimeUUID.map { runtimeId in
            manager.sessions.contains(where: { $0.id == runtimeId })
        } ?? false
        let sessionTitle = SessionExplorerViewStateBuilder.displaySessionTitle(for: session)
        let sessionIdentity = SessionExplorerViewStateBuilder.displaySessionIdentity(for: session)
        let sessionWorkLine = sessionWorkSummary(session) ?? SessionExplorerViewStateBuilder.sessionWorkLine(for: session)
        let sessionResultLine = SessionExplorerViewStateBuilder.sessionResultLine(for: session)
        let sessionChangeLine = SessionExplorerViewStateBuilder.sessionChangeLine(
            session: session,
            insight: repositoryInsight(for: session.repositoryRoot)
        )
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(sessionTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(sessionStatusBadgeLabel(session))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(activityColor(session.activityState))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(activityColor(session.activityState).opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
                Text("업데이트 \(relativeTimestamp(session.updatedAt))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Text(sessionIdentity)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Text("진행: \(sessionWorkLine)")
                .font(.system(size: 10))
                .foregroundStyle(workSummaryColor(session))
                .lineLimit(2)

            Text("결과: \(sessionResultLine)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("변경: \(sessionChangeLine)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("활동: \(relativeTimestamp(session.updatedAt))")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            DisclosureGroup("디버그 메타", isExpanded: $selectedSessionDebugExpanded) {
                Text(
                    "state=\(session.activityState.rawValue), score=\(session.activityScore), tier=\(session.controllabilityTier.rawValue), source=\(session.source), repo=\(session.repositoryRoot ?? "(unassigned)")"
                )
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
            }
            .font(.system(size: 9))
            .tint(.secondary)

            HStack(spacing: 6) {
                if canOpenTerminal, let runtimeUUID {
                    Button("터미널 열기") {
                        Task { await openSessionInTerminal(runtimeUUID: runtimeUUID) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .keyboardShortcut(.defaultAction)
                }

                if let repositoryRoot = session.repositoryRoot {
                    Button("레포 열기") {
                        openRepositoryInFinder(path: repositoryRoot)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Button("경로 복사") {
                    copyToPasteboard(session.workingDirectory ?? session.path)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("히스토리 점프") {
                    Task { await jumpToSessionHistory(session) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func selectedRepositoryDetailCard(_ repository: RepositoryDashboardSummary) -> some View {
        let representative = representativeSession(for: repository.repositoryRoot)
        let insight = repositoryInsight(for: repository.repositoryRoot)
        let workingTreeLine = SessionExplorerViewStateBuilder.repositoryWorkingTreeLine(for: insight)
        let commitFeedLines = SessionExplorerViewStateBuilder.repositoryCommitFeedLines(
            for: insight,
            limit: 3
        )
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(repository.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("세션 \(repository.sessionCount) · 활성 \(repository.activeSessionCount) · 오류 \(repository.errorSessionCount)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("업데이트 \(relativeTimestamp(repository.lastActivityAt))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if let representative {
                Text("대표 세션: [\(representative.provider)] \(representative.nativeSessionId)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("현재 작업: \(sessionWorkSummary(representative) ?? "현재 작업 정보 없음")")
                    .font(.system(size: 9))
                    .foregroundStyle(workSummaryColor(representative))
                    .lineLimit(2)
            } else {
                Text("대표 세션 정보가 없습니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if commitFeedLines.isEmpty {
                Text("커밋: 최근 커밋 정보 없음")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                ForEach(Array(commitFeedLines.enumerated()), id: \.offset) { index, line in
                    Text("커밋 \(index + 1): \(line)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Text("워킹트리: \(workingTreeLine)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if let repositoryRoot = repository.repositoryRoot {
                Text("경로: \(repositoryRoot)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Button("레포 열기") {
                        openRepositoryInFinder(path: repositoryRoot)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .keyboardShortcut(.defaultAction)

                    Button("세션 추천") {
                        Task { await recommendAttachableSession(for: repositoryRoot) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("경로 복사") {
                        copyToPasteboard(repositoryRoot)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var orchestrationLoopSection: some View {
        sectionHeader("Command Bar")

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Menu(orchestrationRepositoryRoot ?? "repo") {
                    Button("전체") { orchestrationRepositoryRoot = nil }
                    ForEach(repositoryFilterOptions, id: \.self) { root in
                        Button(root) { orchestrationRepositoryRoot = root }
                    }
                }
                Menu("필터") {
                    Button("전체") {
                        applyWorkboardLaneFilter(nil)
                    }
                    Button("Blocked/Failing") {
                        applyWorkboardLaneFilter(.blocked)
                    }
                    Button("Running") {
                        applyWorkboardLaneFilter(.running)
                    }
                    Button("Needs Review") {
                        applyWorkboardLaneFilter(.review)
                    }
                }
                TextField("세션 검색 (provider/id/path)", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            HStack(spacing: 6) {
                TextField("실행 명령", text: $orchestrationCommandText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                if orchestrationBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            HStack(spacing: 6) {
                Toggle("파괴적 명령 확인 완료", isOn: $orchestrationRequireConfirmation)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                Spacer()
                Button("선택") {
                    Task { await orchestrationSelectFromUI() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(orchestrationBusy)

                Button("실행") {
                    Task { await orchestrationExecuteFromUI() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(orchestrationBusy)

                Button("상태") {
                    Task { await orchestrationStatusFromUI() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(orchestrationBusy)

                Button("요약") {
                    Task { await orchestrationSummarizeFromUI() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(orchestrationBusy)
            }

            if let selection = orchestrationSelection {
                Text("선택 결과: \(selection.action.rawValue) · \(selection.reason)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let guardDecision = orchestrationGuardDecision {
                Text("guard \(guardDecision.kind.rawValue) · \(guardDecision.reason)")
                    .font(.system(size: 9))
                    .foregroundStyle(guardDecision.kind == .denied ? .red : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var unassignedQueueSection: some View {
        sectionHeader("Unassigned Queue")

        if unassignedUnifiedSessions.isEmpty {
            Text("Unassigned 세션이 없습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            ForEach(
                unassignedUnifiedSessions.map { (key: ExternalToolSessionManager.sessionStableKey($0), value: $0) },
                id: \.key
            ) { item in
                let session = item.value
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(session.provider)] \(session.nativeSessionId)")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text(session.path)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Menu("레포 연결") {
                        if managedRepositories.isEmpty {
                            Text("관리 중인 레포가 없습니다.")
                        } else {
                            ForEach(managedRepositories) { repository in
                                Button(repository.name) {
                                    applyManualMapping(session: session, repositoryRoot: repository.rootPath)
                                }
                            }
                        }
                    }
                    .font(.system(size: 10))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var sessionHistorySection: some View {
        sectionHeader("Session History")

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("히스토리 검색어", text: $historyQueryText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("검색") {
                    Task { await searchSessionHistoryFromUI() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(isHistorySearching)
            }

            HStack(spacing: 6) {
                Menu("repo") {
                    Button("전체") { historyRepositoryFilter = nil }
                    ForEach(repositoryFilterOptions, id: \.self) { root in
                        Button(root) { historyRepositoryFilter = root }
                    }
                }
                TextField("branch(선택)", text: $historyBranchFilter)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                Menu("기간") {
                    ForEach(SessionHistoryTimeFilter.allCases) { filter in
                        Button(filter.label) { historyTimeFilter = filter }
                    }
                }
                Menu("limit") {
                    Button("20") { historyLimit = 20 }
                    Button("50") { historyLimit = 50 }
                    Button("100") { historyLimit = 100 }
                }
            }
            .font(.system(size: 10))

            HStack(spacing: 8) {
                Text("chunks \(historyIndexStatus.chunkCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("indexed \(relativeTimestamp(historyIndexStatus.lastIndexedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let latestChunkEndAt = historyIndexStatus.latestChunkEndAt {
                    Text("latest \(relativeTimestamp(latestChunkEndAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isHistoryIndexing {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button("재인덱싱") {
                    Task { await rebuildSessionHistoryFromUI() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isHistoryIndexing)
            }

            if historyResults.isEmpty {
                Text("검색 결과가 없습니다. 검색어를 입력해 히스토리를 조회하세요.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(historyResults.prefix(30)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("[\(item.provider)] \(item.sessionId)")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            if let branch = item.branch {
                                Text(branch)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(String(format: "%.2f", item.score))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.maskedSnippet)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(relativeTimestamp(item.endAt))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button("세션 보기") {
                                jumpToHistoryResult(item)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func repositoryGroupRow(_ group: RepositorySessionGroup) -> some View {
        let isExpanded = expandedRepositoryGroups.contains(group.repositoryRoot)
        let isFocused = focusedRepositoryKey == group.id
        let isHovered = hoveredRepositoryKey == group.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    toggleRepositoryGroup(group.repositoryRoot)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)

                Button {
                    handleRepositoryGroupTap(group)
                } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text("세션 \(group.sessionCount) · 활성 \(group.activeSessionCount) · 오류 \(group.errorSessionCount)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("업데이트 \(relativeTimestamp(group.lastActivityAt))")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Menu("새 세션 시작") {
                        let candidates = startableProfiles(for: group.repositoryRoot)
                        if candidates.isEmpty {
                            Text("시작 가능한 프로파일이 없습니다.")
                        } else {
                            ForEach(candidates) { profile in
                                Button(profile.name) {
                                    Task { await startProfileSession(profile) }
                                }
                            }
                        }
                    }
                    Button("attach 가능한 세션 추천") {
                        Task {
                            await recommendAttachableSession(for: group.repositoryRoot)
                        }
                    }
                    Menu("Unassigned 매핑") {
                        if unassignedUnifiedSessions.isEmpty {
                            Text("매핑할 Unassigned 세션이 없습니다.")
                        } else {
                            ForEach(
                                unassignedUnifiedSessions.prefix(12).map {
                                    (key: ExternalToolSessionManager.sessionStableKey($0), value: $0)
                                },
                                id: \.key
                            ) { item in
                                let session = item.value
                                Button("[\(session.provider)] \(session.nativeSessionId)") {
                                    applyManualMapping(session: session, repositoryRoot: group.repositoryRoot)
                                }
                            }
                            if unassignedUnifiedSessions.count > 12 {
                                Text("추가 \(unassignedUnifiedSessions.count - 12)개는 Unassigned Queue에서 선택")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFocused ? Color.accentColor.opacity(0.12) : (isHovered ? Color.accentColor.opacity(0.06) : Color.clear))
            )
            .onHover { hovering in
                if hovering {
                    hoveredRepositoryKey = group.id
                } else if hoveredRepositoryKey == group.id {
                    hoveredRepositoryKey = nil
                }
            }

            if isExpanded {
                ForEach(
                    group.sessions.map { (key: ExternalToolSessionManager.sessionStableKey($0), value: $0) },
                    id: \.key
                ) { item in
                    unifiedSessionRow(item.value)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused ? Color.accentColor.opacity(0.8) : Color.clear,
                    lineWidth: isFocused ? 1.2 : 0
                )
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func unifiedSessionRow(_ session: UnifiedCodingSession) -> some View {
        let sessionKey = ExternalToolSessionManager.sessionStableKey(session)
        let runtimeUUID = session.runtimeSessionId.flatMap(UUID.init(uuidString:))
        let isSelected = selectedUnifiedSessionKey == sessionKey || runtimeUUID == selectedSessionId
        let isHovered = hoveredUnifiedSessionKey == sessionKey
        let sessionTitle = SessionExplorerViewStateBuilder.displaySessionTitle(for: session)
        let sessionIdentity = SessionExplorerViewStateBuilder.displaySessionIdentity(for: session)
        let sessionRawTitle = normalizedSessionTitle(session)
        let sessionDescriptor = sessionClientDescriptor(session)
        let workSummary = sessionWorkSummary(session) ?? SessionExplorerViewStateBuilder.sessionWorkLine(for: session)
        let resultSummary = SessionExplorerViewStateBuilder.sessionResultLine(for: session)
        let insight = repositoryInsight(for: session.repositoryRoot)
        let repositoryStatusSummary = SessionExplorerViewStateBuilder.sessionRepositoryStatusLine(
            session: session,
            insight: insight
        )
        let commitSummary = SessionExplorerViewStateBuilder.sessionCommitLine(for: insight)
        let locationSummary = SessionExplorerViewStateBuilder.sessionLocationLine(for: session)
        HStack(spacing: 8) {
            Button {
                handleUnifiedSessionTap(session)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(activityColor(session.activityState))
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(sessionTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(sessionStatusBadgeLabel(session))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(activityColor(session.activityState))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(activityColor(session.activityState).opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text(session.controllabilityTier.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        Text(sessionIdentity)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        if let sessionRawTitle,
                           !sessionRawTitle.isEmpty,
                           sessionRawTitle != sessionTitle {
                            Text("세션 제목: \(sessionRawTitle)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let sessionDescriptor,
                           !sessionDescriptor.isEmpty {
                            Text("클라이언트: \(sessionDescriptor)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text("진행: \(workSummary)")
                            .font(.system(size: 9))
                            .foregroundStyle(workSummaryColor(session))
                            .lineLimit(2)

                        Text("상태: \(resultSummary) · 점수 \(session.activityScore)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("레포: \(repositoryStatusSummary)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("커밋: \(commitSummary)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Text("활동: \(relativeTimestamp(session.updatedAt)) · 위치: \(locationSummary)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if let repositoryRoot = session.repositoryRoot {
                    Button("이 레포만 보기") {
                        explorerFilter.repositoryRoot = normalizedRepositoryPath(repositoryRoot)
                        explorerFilter.unassignedOnly = false
                    }
                }
                if session.isUnassigned {
                    Menu("레포 연결") {
                        if managedRepositories.isEmpty {
                            Text("관리 중인 레포가 없습니다.")
                        } else {
                            ForEach(managedRepositories) { repository in
                                Button(repository.name) {
                                    applyManualMapping(session: session, repositoryRoot: repository.rootPath)
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : (isHovered ? Color.accentColor.opacity(0.07) : Color.clear))
        )
        .onHover { hovering in
            if hovering {
                hoveredUnifiedSessionKey = sessionKey
            } else if hoveredUnifiedSessionKey == sessionKey {
                hoveredUnifiedSessionKey = nil
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func sessionRow(session: ExternalToolSession) -> some View {
        let profile = manager.profiles.first(where: { $0.id == session.profileId })
        let isSelected = selectedSessionId == session.id

        Button {
            selectedSessionId = session.id
            selectedProfileId = nil
        } label: {
            HStack(spacing: 8) {
                statusIndicator(session.status)
                    .frame(width: 10)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(profile?.name ?? "알 수 없음")
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer()
                        Text(session.status.displayText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Text(profile?.workingDirectory ?? "~")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        if profile?.isRemote == true {
                            Text("SSH")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        } else {
                            Text("로컬")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func profileRow(profile: ExternalToolProfile) -> some View {
        let isSelected = selectedProfileId == profile.id

        Button {
            selectedProfileId = profile.id
            selectedSessionId = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                Text("\(profile.name) (미시작)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if startingProfileId == profile.id {
                    ProgressView()
                        .controlSize(.mini)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("시작") {
                Task { await startProfileSession(profile) }
            }
            .disabled(startingProfileId == profile.id)
            Button("편집") {
                editingProfile = profile
                showProfileEditor = true
            }
            Divider()
            Button("삭제", role: .destructive) {
                manager.deleteProfile(id: profile.id)
            }
        }
    }

    @ViewBuilder
    private func statusIndicator(_ status: ExternalToolStatus) -> some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .opacity(status == .unknown ? 0.5 : 1.0)
    }

    @MainActor
    private func refreshUnifiedSessions() async {
        guard !isRefreshingUnified else { return }
        isRefreshingUnified = true
        async let unified = manager.listUnifiedCodingSessions(limit: 180)
        async let discovered = manager.discoverLocalCodingSessions(limit: 120)
        async let baselineInsights = manager.discoverGitRepositoryInsights(searchPaths: nil, limit: 60)

        let unifiedResult = await unified
        unifiedSessions = unifiedResult
        discoveredSessions = await discovered

        let sessionRepositoryRoots = Array(
            Set(
                unifiedResult.compactMap(\.repositoryRoot).map { normalizedRepositoryPath($0) }
            )
        )
        .sorted()

        let scopedInsights: [GitRepositoryInsight]
        if sessionRepositoryRoots.isEmpty {
            scopedInsights = []
        } else {
            let scopedLimit = max(90, min(220, sessionRepositoryRoots.count * 6))
            scopedInsights = await manager.discoverGitRepositoryInsights(
                searchPaths: sessionRepositoryRoots,
                limit: scopedLimit
            )
        }

        let mergedInsights = mergeGitInsights(
            primary: await baselineInsights,
            scoped: scopedInsights
        )
        gitInsights = mergedInsights
        if let repositoryRoot = explorerFilter.repositoryRoot {
            explorerFilter.repositoryRoot = normalizedRepositoryPath(repositoryRoot)
        }
        if let repositoryRoot = orchestrationRepositoryRoot {
            orchestrationRepositoryRoot = normalizedRepositoryPath(repositoryRoot)
        }
        syncExpandedRepositoryGroups()
        refreshKPIReport()
        isRefreshingUnified = false
        persistSessionCache()
    }

    private func mergeGitInsights(
        primary: [GitRepositoryInsight],
        scoped: [GitRepositoryInsight]
    ) -> [GitRepositoryInsight] {
        var mapped: [String: GitRepositoryInsight] = [:]

        for insight in primary {
            mapped[normalizedRepositoryPath(insight.path)] = insight
        }

        // Scoped insights target repos currently visible in this dashboard.
        // Prefer them when keys collide so branch/commit/status stay aligned to active work.
        for insight in scoped {
            mapped[normalizedRepositoryPath(insight.path)] = insight
        }

        return mapped.values.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsEpoch = lhs.lastCommitEpoch ?? Int.min
            let rhsEpoch = rhs.lastCommitEpoch ?? Int.min
            if lhsEpoch != rhsEpoch {
                return lhsEpoch > rhsEpoch
            }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    @MainActor
    private func refreshSubscriptionUsage(forceRefresh: Bool = false) async {
        guard !isRefreshingSubscriptionUsage else { return }
        guard let resourceOptimizer else {
            return
        }

        isRefreshingSubscriptionUsage = true
        defer { isRefreshingSubscriptionUsage = false }

        let snapshot = await resourceOptimizer.refreshSubscriptionUsageSnapshot(force: forceRefresh)
        subscriptionUtilizations = snapshot.utilizations
        subscriptionMonitoringSnapshots = snapshot.monitoringSnapshots
        persistSessionCache()
    }

    @MainActor
    private func refreshSubscriptionUsageWithBootstrap(forceRefresh: Bool = false) async {
        await bootstrapSubscriptionsIfNeeded()
        await refreshSubscriptionUsage(forceRefresh: forceRefresh)
    }

    @MainActor
    private func bootstrapSubscriptionsIfNeeded() async {
        guard let resourceOptimizer else { return }
        _ = await resourceOptimizer.bootstrapDefaultExternalSubscriptionsIfNeeded()
    }

    private func startUnifiedAutoRefreshLoop() {
        guard unifiedAutoRefreshTask == nil else { return }
        unifiedAutoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if Task.isCancelled { break }
                await refreshUnifiedSessions()
            }
        }
    }

    @MainActor
    private func applyManualMapping(session: UnifiedCodingSession, repositoryRoot: String) {
        let normalizedRepositoryRoot = normalizedRepositoryPath(repositoryRoot)
        manager.setManualRepositoryBinding(
            provider: session.provider,
            nativeSessionId: session.nativeSessionId,
            path: session.path,
            repositoryRoot: normalizedRepositoryRoot
        )
        if let filterRoot = explorerFilter.repositoryRoot {
            explorerFilter.repositoryRoot = normalizedRepositoryPath(filterRoot)
        }
        let repoName = URL(fileURLWithPath: normalizedRepositoryRoot).lastPathComponent
        mappingNotice = "[\(session.nativeSessionId)] 세션을 \(repoName) 레포로 연결했습니다."
        Task {
            await refreshUnifiedSessions()
        }
    }

    @MainActor
    private func startProfileSession(_ profile: ExternalToolProfile) async {
        startingProfileId = profile.id
        defer {
            if startingProfileId == profile.id {
                startingProfileId = nil
            }
        }
        do {
            try await manager.startSession(profileId: profile.id)
            if let active = manager.activeSession(for: profile.id) {
                selectedSessionId = active.id
                selectedProfileId = nil
            } else {
                startErrorMessage = "세션이 즉시 종료되었습니다. 프로파일 설정을 확인해주세요."
            }
            await refreshUnifiedSessions()
        } catch {
            startErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func recommendAttachableSession(for repositoryRoot: String) async {
        let selection = await manager.selectSessionForOrchestration(repositoryRoot: repositoryRoot)
        explorerFilter.repositoryRoot = repositoryRoot
        explorerFilter.activeOnly = true
        orchestrationRepositoryRoot = repositoryRoot
        orchestrationSelection = selection
        switch selection.action {
        case .reuseT0Active, .attachT1, .analyzeOnly:
            if let selected = selection.selectedSession {
                searchText = selected.nativeSessionId
                mappingNotice = "추천 세션 [\(selected.provider)] \(selected.nativeSessionId) · \(selection.reason)"
            } else {
                mappingNotice = selection.reason
            }
        case .createT0:
            mappingNotice = "이 레포에서 재사용 가능한 세션이 없습니다. 새 세션 시작을 선택하세요."
        case .none:
            mappingNotice = selection.reason
        }
        refreshKPIReport()
    }

    @MainActor
    private func orchestrationSelectFromUI() async {
        guard !orchestrationBusy else { return }
        orchestrationBusy = true
        defer { orchestrationBusy = false }

        let selection = await manager.selectSessionForOrchestration(repositoryRoot: orchestrationRepositoryRoot)
        orchestrationSelection = selection
        orchestrationStatusContract = nil
        orchestrationSummarizeContract = nil
        orchestrationOutputLines = []
        orchestrationErrorMessage = nil
        orchestrationGuardDecision = nil

        if let selected = selection.selectedSession,
           let command = nonEmptyOrchestrationCommand() {
            orchestrationGuardDecision = manager.evaluateOrchestrationExecutionGuard(
                tier: selected.controllabilityTier,
                command: command,
                repositoryRoot: selected.repositoryRoot ?? orchestrationRepositoryRoot
            )
        }

        refreshKPIReport()
    }

    @MainActor
    private func orchestrationExecuteFromUI() async {
        guard !orchestrationBusy else { return }
        guard let command = nonEmptyOrchestrationCommand() else {
            orchestrationErrorMessage = "실행 명령을 입력해주세요."
            return
        }

        orchestrationBusy = true
        defer { orchestrationBusy = false }
        orchestrationErrorMessage = nil

        if orchestrationSelection == nil {
            let selection = await manager.selectSessionForOrchestration(repositoryRoot: orchestrationRepositoryRoot)
            orchestrationSelection = selection
            refreshKPIReport()
        }
        guard let selection = orchestrationSelection else {
            orchestrationErrorMessage = "세션 선택에 실패했습니다."
            return
        }

        switch selection.action {
        case .reuseT0Active, .attachT1:
            guard let selected = selection.selectedSession else {
                orchestrationErrorMessage = "선택된 세션을 찾지 못했습니다."
                return
            }
            let decision = manager.evaluateOrchestrationExecutionGuard(
                tier: selected.controllabilityTier,
                command: command,
                repositoryRoot: selected.repositoryRoot ?? orchestrationRepositoryRoot
            )
            orchestrationGuardDecision = decision
            if decision.kind == .denied {
                orchestrationErrorMessage = decision.reason
                refreshKPIReport()
                return
            }
            if decision.kind == .confirmationRequired, !orchestrationRequireConfirmation {
                orchestrationErrorMessage = "\(decision.reason) (체크박스를 켜고 다시 실행하세요.)"
                refreshKPIReport()
                return
            }

            guard let runtimeSessionId = selected.runtimeSessionId,
                  let sessionId = UUID(uuidString: runtimeSessionId) else {
                orchestrationErrorMessage = "실행 가능한 runtime session이 없습니다."
                return
            }

            do {
                try await manager.sendCommand(sessionId: sessionId, command: command)
                let output = await manager.captureOutput(sessionId: sessionId, lines: Self.orchestrationStatusCaptureLines)
                orchestrationOutputLines = output
                orchestrationStatusContract = orchestrationSummaryService.makeStatusContract(outputLines: output)
                refreshKPIReport()
            } catch {
                orchestrationErrorMessage = error.localizedDescription
            }
        case .createT0, .analyzeOnly, .none:
            orchestrationErrorMessage = selection.reason
            refreshKPIReport()
        }
    }

    @MainActor
    private func orchestrationStatusFromUI() async {
        guard !orchestrationBusy else { return }
        orchestrationBusy = true
        defer { orchestrationBusy = false }
        orchestrationErrorMessage = nil

        guard let sessionId = await resolveOrchestrationRuntimeSessionId() else {
            orchestrationErrorMessage = "상태 조회 대상 세션이 없습니다."
            return
        }

        let output = await manager.captureOutput(sessionId: sessionId, lines: Self.orchestrationStatusCaptureLines)
        orchestrationOutputLines = output
        orchestrationStatusContract = orchestrationSummaryService.makeStatusContract(outputLines: output)
    }

    @MainActor
    private func orchestrationSummarizeFromUI() async {
        guard !orchestrationBusy else { return }
        orchestrationBusy = true
        defer { orchestrationBusy = false }
        orchestrationErrorMessage = nil

        guard let sessionId = await resolveOrchestrationRuntimeSessionId() else {
            orchestrationErrorMessage = "요약 대상 세션이 없습니다."
            return
        }

        let output = await manager.captureOutput(sessionId: sessionId, lines: Self.orchestrationSummarizeCaptureLines)
        orchestrationOutputLines = output
        orchestrationSummarizeContract = orchestrationSummaryService.makeSummarizeContract(outputLines: output)
    }

    @MainActor
    private func resolveOrchestrationRuntimeSessionId() async -> UUID? {
        if orchestrationSelection == nil {
            let selection = await manager.selectSessionForOrchestration(repositoryRoot: orchestrationRepositoryRoot)
            orchestrationSelection = selection
            refreshKPIReport()
        }
        guard let runtimeSessionId = orchestrationSelection?.selectedSession?.runtimeSessionId else {
            return nil
        }
        return UUID(uuidString: runtimeSessionId)
    }

    private func nonEmptyOrchestrationCommand() -> String? {
        let trimmed = orchestrationCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    private func rebuildSessionHistoryFromUI() async {
        guard !isHistoryIndexing else { return }
        isHistoryIndexing = true
        let chunkCount = await manager.rebuildSessionHistoryIndex(limit: max(100, historyLimit * 20))
        refreshHistoryIndexStatus()
        refreshKPIReport()
        isHistoryIndexing = false
        mappingNotice = "세션 히스토리 인덱스를 재구축했습니다. (chunks: \(chunkCount))"
    }

    @MainActor
    private func searchSessionHistoryFromUI() async {
        guard !isHistorySearching else { return }
        let queryText = historyQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else {
            mappingNotice = "히스토리 검색어를 입력해주세요."
            return
        }
        isHistorySearching = true
        let results = await manager.searchSessionHistory(
            query: SessionHistorySearchQuery(
                query: queryText,
                repositoryRoot: historyRepositoryFilter,
                branch: historyBranchFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : historyBranchFilter.trimmingCharacters(in: .whitespacesAndNewlines),
                since: historyTimeFilter.sinceDate(),
                until: nil,
                limit: historyLimit
            )
        )
        historyResults = results
        refreshHistoryIndexStatus()
        refreshKPIReport()
        isHistorySearching = false
        persistSessionCache()
    }

    @MainActor
    private func jumpToHistoryResult(_ result: SessionHistorySearchResult) {
        historyQueryText = result.sessionId
        searchText = result.sessionId
        explorerFilter.repositoryRoot = result.repositoryRoot
        explorerFilter.unassignedOnly = false
        explorerFilter.activeOnly = false
    }

    @MainActor
    private func refreshHistoryIndexStatus() {
        historyIndexStatus = manager.sessionHistoryIndexStatus()
        persistSessionCache()
    }

    @MainActor
    private func refreshKPIReport() {
        kpiReport = manager.sessionManagementKPIReport()
        persistSessionCache()
    }

    @MainActor
    private func restoreCachedStateIfNeeded() {
        guard let sessionCache else { return }

        if unifiedSessions.isEmpty {
            unifiedSessions = sessionCache.unifiedSessions
        }
        if discoveredSessions.isEmpty {
            discoveredSessions = sessionCache.discoveredSessions
        }
        if gitInsights.isEmpty {
            gitInsights = sessionCache.gitInsights
        }
        if historyResults.isEmpty {
            historyResults = sessionCache.historyResults
        }
        if historyIndexStatus.chunkCount == 0, historyIndexStatus.lastIndexedAt == nil {
            historyIndexStatus = sessionCache.historyIndexStatus
        }
        if kpiReport.generatedAt.timeIntervalSince1970 <= 0 {
            kpiReport = sessionCache.kpiReport
        }
        if subscriptionUtilizations.isEmpty {
            subscriptionUtilizations = sessionCache.subscriptionUtilizations
        }
        if subscriptionMonitoringSnapshots.isEmpty {
            subscriptionMonitoringSnapshots = sessionCache.subscriptionMonitoringSnapshots
        }
    }

    @MainActor
    private func persistSessionCache() {
        guard let sessionCache else { return }
        sessionCache.unifiedSessions = unifiedSessions
        sessionCache.discoveredSessions = discoveredSessions
        sessionCache.gitInsights = gitInsights
        sessionCache.historyResults = historyResults
        sessionCache.historyIndexStatus = historyIndexStatus
        sessionCache.kpiReport = kpiReport
        sessionCache.subscriptionUtilizations = subscriptionUtilizations
        sessionCache.subscriptionMonitoringSnapshots = subscriptionMonitoringSnapshots
        sessionCache.hasLoadedData = !unifiedSessions.isEmpty
            || !historyResults.isEmpty
            || historyIndexStatus.chunkCount > 0
        sessionCache.lastLoadedAt = Date()
    }

    @MainActor
    private func shouldRunInitialRefresh() -> Bool {
        guard let sessionCache else { return true }
        guard sessionCache.hasLoadedData else { return true }
        guard let lastLoadedAt = sessionCache.lastLoadedAt else { return true }
        return Date().timeIntervalSince(lastLoadedAt) > 20
    }

    private func startableProfiles(for repositoryRoot: String) -> [ExternalToolProfile] {
        unlaunchedProfiles
            .filter { profile in
                SessionExplorerViewStateBuilder.repositoryContainsWorkingDirectory(
                    repositoryRoot: repositoryRoot,
                    workingDirectory: profile.workingDirectory
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func syncExpandedRepositoryGroups() {
        let available = Set(
            SessionExplorerViewStateBuilder.repositoryGroups(
                sessions: unifiedSessions.filter { !$0.isUnassigned },
                sort: sortOption
            )
            .map(\.repositoryRoot)
        )

        if !didInitializeRepositoryExpansion {
            expandedRepositoryGroups = available
            didInitializeRepositoryExpansion = true
        } else {
            expandedRepositoryGroups.formIntersection(available)
        }
    }

    private func toggleRepositoryGroup(_ repositoryRoot: String) {
        if expandedRepositoryGroups.contains(repositoryRoot) {
            expandedRepositoryGroups.remove(repositoryRoot)
        } else {
            expandedRepositoryGroups.insert(repositoryRoot)
        }
    }

    private func handleRepositoryCardTap(_ summary: RepositoryDashboardSummary) {
        focusedRepositoryKey = summary.id
        searchText = ""
        selectedProfileId = nil
        explorerFilter = SessionExplorerViewStateBuilder.selectionFilter(for: summary.repositoryRoot)

        if let normalizedRoot = explorerFilter.repositoryRoot {
            expandedRepositoryGroups.insert(normalizedRoot)
            orchestrationRepositoryRoot = normalizedRoot
        } else {
            orchestrationRepositoryRoot = nil
        }

        if let preferred = SessionExplorerViewStateBuilder.preferredSession(
            in: summary.repositoryRoot,
            sessions: unifiedSessions
        ) {
            handleUnifiedSessionTap(preferred)
        } else {
            selectedSessionId = nil
        }
    }

    private func handleRepositoryGroupTap(_ group: RepositorySessionGroup) {
        focusedRepositoryKey = group.id
        searchText = ""
        selectedProfileId = nil
        explorerFilter = SessionExplorerViewStateBuilder.selectionFilter(for: group.repositoryRoot)
        orchestrationRepositoryRoot = group.repositoryRoot
        expandedRepositoryGroups.insert(group.repositoryRoot)

        if let preferred = group.sessions.first {
            handleUnifiedSessionTap(preferred)
        } else {
            selectedSessionId = nil
        }
    }

    private func handleUnifiedSessionTap(_ session: UnifiedCodingSession) {
        selectedUnifiedSessionKey = ExternalToolSessionManager.sessionStableKey(session)
        searchText = session.nativeSessionId
        selectedProfileId = nil

        if let repositoryRoot = session.repositoryRoot {
            let normalizedRoot = normalizedRepositoryPath(repositoryRoot)
            focusedRepositoryKey = normalizedRoot
            explorerFilter.repositoryRoot = normalizedRoot
            explorerFilter.unassignedOnly = false
            expandedRepositoryGroups.insert(normalizedRoot)
            orchestrationRepositoryRoot = normalizedRoot
        } else {
            focusedRepositoryKey = "unassigned"
            explorerFilter.repositoryRoot = nil
            explorerFilter.unassignedOnly = true
            orchestrationRepositoryRoot = nil
        }

        if let runtimeSessionId = session.runtimeSessionId,
           let runtimeUUID = UUID(uuidString: runtimeSessionId),
           manager.sessions.contains(where: { $0.id == runtimeUUID }) {
            selectedSessionId = runtimeUUID
            mappingNotice = nil
        } else {
            selectedSessionId = nil
        }
    }

    @MainActor
    private func openSessionInTerminal(runtimeUUID: UUID) async {
        do {
            try await manager.openInTerminal(sessionId: runtimeUUID)
            mappingNotice = "선택한 세션을 외부 터미널에서 열었습니다."
        } catch {
            interactionErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func jumpToSessionHistory(_ session: UnifiedCodingSession) async {
        historyQueryText = session.nativeSessionId
        if let repositoryRoot = session.repositoryRoot {
            historyRepositoryFilter = normalizedRepositoryPath(repositoryRoot)
        } else {
            historyRepositoryFilter = nil
        }
        historyTimeFilter = .day30
        await searchSessionHistoryFromUI()
        mappingNotice = "세션 히스토리 필터를 적용했습니다."
    }

    private func openRepositoryInFinder(path: String) {
#if os(macOS)
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let url = URL(fileURLWithPath: standardized, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
#endif
        mappingNotice = "레포 경로를 열었습니다."
    }

    private func copyToPasteboard(_ value: String) {
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
#endif
        mappingNotice = "경로를 클립보드에 복사했습니다."
    }

    private func normalizedSessionTitle(_ session: UnifiedCodingSession) -> String? {
        guard let raw = session.title else { return nil }
        let normalized = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(100))
    }

    private func normalizedSessionSummary(_ session: UnifiedCodingSession) -> String? {
        guard let raw = session.summary else { return nil }
        let normalized = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(140))
    }

    private func sessionWorkSummary(_ session: UnifiedCodingSession) -> String? {
        // 오래된 stale/dead 세션은 요약 노이즈를 숨긴다.
        if session.activityState == .stale || session.activityState == .dead {
            if Date().timeIntervalSince(session.updatedAt) > 60 * 60 * 3 {
                return nil
            }
        }
        if let summary = normalizedSessionSummary(session) {
            return summary
        }
        switch session.activityState {
        case .active:
            return "작업 진행 중"
        case .idle:
            return "입력 대기 중"
        case .stale:
            return "최근 작업 정보가 오래되었습니다"
        case .dead:
            return "세션이 종료되었습니다"
        }
    }

    private func representativeSession(for repositoryRoot: String?) -> UnifiedCodingSession? {
        SessionExplorerViewStateBuilder.preferredSession(
            in: repositoryRoot,
            sessions: unifiedSessions
        )
    }

    private func workSummaryColor(_ session: UnifiedCodingSession) -> Color {
        if session.activityState == .stale || session.activityState == .dead {
            return .gray
        }
        return .secondary
    }

    private func repositoryInsight(for repositoryRoot: String?) -> GitRepositoryInsight? {
        guard let repositoryRoot else { return nil }
        return gitInsightByRepositoryPath[normalizedRepositoryPath(repositoryRoot)]
    }

    private func sessionStatusBadgeLabel(_ session: UnifiedCodingSession) -> String {
        switch session.activityState {
        case .active:
            return "작업중"
        case .idle:
            return "대기"
        case .stale:
            return "지연"
        case .dead:
            return "종료"
        }
    }

    private func repositoryCommitContext(for repositoryRoot: String?) -> String? {
        guard let repositoryRoot else { return nil }
        let normalizedRoot = normalizedRepositoryPath(repositoryRoot)
        guard let insight = gitInsightByRepositoryPath[normalizedRoot] else { return nil }
        return repositoryCommitContext(insight)
    }

    private func repositoryCommitContext(_ insight: GitRepositoryInsight?) -> String? {
        guard let insight else { return nil }
        let shortHash = insight.lastCommitShortHash?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = insight.lastCommitSubject?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let relative = insight.lastCommitRelative.trimmingCharacters(in: .whitespacesAndNewlines)

        if let shortHash, !shortHash.isEmpty,
           let subject, !subject.isEmpty {
            return "\(shortHash) \(String(subject.prefix(90))) · \(relative)"
        }
        if let subject, !subject.isEmpty {
            return "\(String(subject.prefix(90))) · \(relative)"
        }
        if let shortHash, !shortHash.isEmpty {
            return "\(shortHash) · \(relative)"
        }
        if !relative.isEmpty, relative != "-" {
            return relative
        }
        return nil
    }

    private func normalizedDiscoveredTitle(_ session: DiscoveredCodingSession) -> String? {
        let raw = session.title ?? session.summary
        let normalized = raw?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return nil }
        return String(normalized.prefix(100))
    }

    private func normalizedDiscoveredSummary(_ session: DiscoveredCodingSession) -> String? {
        guard let raw = session.summary else { return nil }
        let normalized = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let title = normalizedDiscoveredTitle(session), title == normalized {
            return nil
        }
        return String(normalized.prefix(160))
    }

    private func sessionClientDescriptor(_ session: UnifiedCodingSession) -> String? {
        var parts: [String] = []
        if session.provider.lowercased() == "codex" {
            switch session.clientKind {
            case "desktop":
                parts.append("Codex Desktop")
            case "cli":
                parts.append("Codex CLI")
            case "unknown":
                parts.append("Codex")
            default:
                if let originator = session.originator {
                    parts.append(originator)
                }
            }
        } else if let originator = session.originator {
            parts.append(originator)
        }

        if let sessionSource = session.sessionSource, !sessionSource.isEmpty {
            parts.append("src=\(sessionSource)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func discoveredClientDescriptor(_ session: DiscoveredCodingSession) -> String? {
        var parts: [String] = []
        if session.provider.lowercased() == "codex" {
            switch session.clientKind {
            case "desktop":
                parts.append("Codex Desktop")
            case "cli":
                parts.append("Codex CLI")
            case "unknown":
                parts.append("Codex")
            default:
                if let originator = session.originator {
                    parts.append(originator)
                }
            }
        } else if let originator = session.originator {
            parts.append(originator)
        }

        if let sessionSource = session.sessionSource, !sessionSource.isEmpty {
            parts.append("src=\(sessionSource)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func relativeTimestamp(_ date: Date?) -> String {
        guard let date else { return "-" }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func applyWorkboardLaneFilter(_ lane: OrchestrationWorkboardLane?) {
        explorerFilter.activeOnly = false
        explorerFilter.unassignedOnly = false
        workboardLaneFilter = lane
    }

    private func normalizedRepositoryPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func workboardLaneTitle(_ lane: OrchestrationWorkboardLane) -> String {
        switch lane {
        case .blocked:
            return "Blocked"
        case .running:
            return "Running"
        case .review:
            return "Review"
        case .queued:
            return "Queued"
        case .done:
            return "Done"
        }
    }

    private func workboardLaneColor(_ lane: OrchestrationWorkboardLane) -> Color {
        switch lane {
        case .blocked:
            return .red
        case .running:
            return .green
        case .review:
            return .orange
        case .queued:
            return .blue
        case .done:
            return .secondary
        }
    }

    private func monitorSeverity(for resultKind: String) -> OrchestrationMonitorSeverity {
        let normalized = resultKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("fail") || normalized.contains("error") {
            return .error
        }
        if normalized.contains("running") || normalized.contains("unknown") {
            return .warning
        }
        return .info
    }

    private func activityColor(_ state: CodingSessionActivityState) -> Color {
        switch state {
        case .active:
            return .green
        case .idle:
            return .blue
        case .stale:
            return .orange
        case .dead:
            return .gray
        }
    }

    private func riskRank(_ level: WasteRiskLevel) -> Int {
        switch level {
        case .wasteRisk:
            return 0
        case .caution:
            return 1
        case .normal:
            return 2
        case .comfortable:
            return 3
        }
    }

    private func riskColor(_ level: WasteRiskLevel) -> Color {
        switch level {
        case .comfortable:
            return .green
        case .caution:
            return .orange
        case .wasteRisk:
            return .red
        case .normal:
            return .blue
        }
    }

    private func usageSourceColor(_ source: SubscriptionUsageSource) -> Color {
        switch source {
        case .externalToolLogs:
            return .indigo
        case .dochiUsageStore:
            return .teal
        }
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

    private func compactResetLabel(
        primaryWindow: MonitoringUsageWindowSnapshot?,
        secondaryWindow: MonitoringUsageWindowSnapshot?,
        source: SubscriptionUsageSource,
        fallbackDaysRemaining: Int
    ) -> String {
        let targetWindow = secondaryWindow ?? primaryWindow
        guard source == .externalToolLogs else {
            return "리셋 D-\(fallbackDaysRemaining)"
        }
        guard let targetWindow else {
            return "리셋 정보 없음"
        }
        if let reset = targetWindow.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !reset.isEmpty {
            return "리셋 \(reset)"
        }
        guard let resetsAt = targetWindow.resetsAt else {
            return "리셋 정보 없음"
        }
        let absolute = Self.windowResetAbsoluteFormatter.string(from: resetsAt)
        return "리셋 \(absolute)"
    }

    private func compactWindowUsageLine(
        _ window: MonitoringUsageWindowSnapshot,
        fallbackTitle: String
    ) -> String {
        let title = compactWindowTitle(window, fallback: fallbackTitle)
        var parts: [String] = ["\(title) \(Int(window.usedPercent.rounded()))%"]

        if let reset = window.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !reset.isEmpty {
            parts.append("리셋 \(reset)")
        } else if let resetsAt = window.resetsAt {
            let absolute = Self.windowResetAbsoluteFormatter.string(from: resetsAt)
            parts.append("리셋 \(absolute)")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func compactWindowUsageBlock(
        _ window: MonitoringUsageWindowSnapshot,
        fallbackTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(compactWindowUsageLine(window, fallbackTitle: fallbackTitle))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(compactWindowUsageColor(window.usedPercent))
                        .frame(width: max(0, min(proxy.size.width, proxy.size.width * window.usedRatio)))
                }
            }
            .frame(height: 4)
        }
    }

    private func compactWindowUsageColor(_ usedPercent: Double) -> Color {
        if usedPercent >= 90 { return .red }
        if usedPercent >= 70 { return .orange }
        return .blue
    }

    private func compactWindowTitle(
        _ window: MonitoringUsageWindowSnapshot,
        fallback: String
    ) -> String {
        if let minutes = window.windowMinutes, minutes > 0 {
            if minutes == 300 { return "세션" }
            if minutes == 10_080 { return "주간" }
            if minutes == 1_440 { return "일간" }
            if minutes % 1_440 == 0 { return "\(minutes / 1_440)일" }
            if minutes % 60 == 0 { return "\(minutes / 60)시간" }
            return "\(minutes)분"
        }
        let trimmed = window.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func subscriptionUsageAmountText(_ util: ResourceUtilization) -> String {
        if let limit = util.subscription.monthlyTokenLimit {
            return "사용 \(formatTokenCount(util.usedTokens))/\(formatTokenCount(limit))"
        }
        return "사용 \(formatTokenCount(util.usedTokens)) (무제한)"
    }

    private func formatTokenCount(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    @ViewBuilder
    private func fleetMetricBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func kpiBadge(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
            Text(detail)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - ExternalToolStatus Helpers

extension ExternalToolStatus {
    var color: Color {
        switch self {
        case .idle: return .green
        case .busy: return .blue
        case .waiting: return .orange
        case .error: return .red
        case .dead: return .gray
        case .unknown: return .gray
        }
    }

    var displayText: String {
        switch self {
        case .idle: return "유휴"
        case .busy: return "작업 중"
        case .waiting: return "입력 대기"
        case .error: return "에러"
        case .dead: return "종료"
        case .unknown: return "확인 중"
        }
    }
}
