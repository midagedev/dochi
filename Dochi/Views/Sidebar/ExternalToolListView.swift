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

struct ExternalToolListView: View {
    let manager: ExternalToolSessionManagerProtocol
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
    private let orchestrationSummaryService = OrchestrationSummaryService()
    private static let orchestrationStatusCaptureLines = 120
    private static let orchestrationSummarizeCaptureLines = 160
    private static let orchestrationOutputPreviewLines = 3
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
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
            await refreshUnifiedSessions()
            refreshHistoryIndexStatus()
            refreshKPIReport()
        }
        .onAppear {
            startUnifiedAutoRefreshLoop()
        }
        .onDisappear {
            unifiedAutoRefreshTask?.cancel()
            unifiedAutoRefreshTask = nil
        }
        .onChange(of: explorerFilter.activeOnly) { _, _ in
            Task { await refreshUnifiedSessions() }
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
                repoDashboardSection
                sessionExplorerSection
                selectionDetailSection
                discoveredSessionSection
                orchestrationLoopSection
                unassignedQueueSection
                sessionHistorySection

                Divider()
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                // Running sessions
                if !runningSessions.isEmpty {
                    sectionHeader("실행 중")
                    ForEach(runningSessions) { session in
                        sessionRow(session: session)
                    }
                }

                // Stopped sessions
                if !stoppedSessions.isEmpty {
                    sectionHeader("중지됨")
                    ForEach(stoppedSessions) { session in
                        sessionRow(session: session)
                    }
                }

                // Unlaunched profiles
                if !unlaunchedProfiles.isEmpty {
                    sectionHeader("프로파일")
                    ForEach(unlaunchedProfiles) { profile in
                        profileRow(profile: profile)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var observabilitySectionHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("세션 탐색기")
                    .font(.system(size: 13, weight: .semibold))
                Text("Repo-first 탐색 / 세션 메타 / Git 변화 지표")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRefreshingUnified {
                ProgressView()
                    .controlSize(.small)
            }
            Button("새로고침") {
                Task { await refreshUnifiedSessions() }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var repoDashboardSection: some View {
        sectionHeader("Repo Dashboard")

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
                                    if let commitContext = repositoryCommitContext(insight) {
                                        Text("최근 커밋: \(commitContext)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    } else {
                                        Text("최근 커밋: 최근 커밋 정보 없음")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("[\(session.provider)] \(session.nativeSessionId)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(session.activityState.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
                Text("업데이트 \(relativeTimestamp(session.updatedAt))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Text("현재 작업: \(sessionWorkSummary(session) ?? "현재 작업 정보 없음")")
                .font(.system(size: 10))
                .foregroundStyle(workSummaryColor(session))
                .lineLimit(2)

            Text("최근 커밋: \(repositoryCommitContext(for: session.repositoryRoot) ?? "최근 커밋 정보 없음")")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("경로: \(session.workingDirectory ?? session.path)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

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
        let commitContext = repositoryCommitContext(for: repository.repositoryRoot)
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

            Text("최근 커밋: \(commitContext ?? "최근 커밋 정보 없음")")
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
        sectionHeader("Orchestration Loop")

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Menu(orchestrationRepositoryRoot ?? "repo") {
                    Button("전체") { orchestrationRepositoryRoot = nil }
                    ForEach(repositoryFilterOptions, id: \.self) { root in
                        Button(root) { orchestrationRepositoryRoot = root }
                    }
                }
                TextField("실행 명령", text: $orchestrationCommandText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            HStack(spacing: 6) {
                Toggle("파괴적 명령 확인 완료", isOn: $orchestrationRequireConfirmation)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                Spacer()
                if orchestrationBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("action \(selection.action.rawValue)")
                        .font(.system(size: 10, weight: .semibold))
                    Text(selection.reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let selected = selection.selectedSession {
                        Text("[\(selected.provider)] \(selected.nativeSessionId) · tier \(selected.controllabilityTier.rawValue) · state \(selected.activityState.rawValue)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let guardDecision = orchestrationGuardDecision {
                Text("guard \(guardDecision.kind.rawValue) · \(guardDecision.policyCode.rawValue) · \(guardDecision.reason)")
                    .font(.system(size: 9))
                    .foregroundStyle(guardDecision.kind == .denied ? .red : .secondary)
                    .lineLimit(2)
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
                if !summarized.highlights.isEmpty {
                    Text(summarized.highlights.joined(separator: " | "))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            if !orchestrationOutputLines.isEmpty {
                Text(orchestrationOutputLines.suffix(Self.orchestrationOutputPreviewLines).joined(separator: " ⏎ "))
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
        .padding(.bottom, 8)
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
        let sessionTitle = normalizedSessionTitle(session)
        let workSummary = sessionWorkSummary(session)
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
                            Text("[\(session.provider)] \(session.nativeSessionId)")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(session.controllabilityTier.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        if let sessionTitle {
                            Text(sessionTitle)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }

                        if let workSummary {
                            Text("현재 작업: \(workSummary)")
                                .font(.system(size: 9))
                                .foregroundStyle(workSummaryColor(session))
                                .lineLimit(2)
                        } else {
                            Text("현재 작업: 현재 작업 정보 없음")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        if let commitContext = repositoryCommitContext(for: session.repositoryRoot) {
                            Text("최근 커밋: \(commitContext)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        } else {
                            Text("최근 커밋: 최근 커밋 정보 없음")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        if let clientDescriptor = sessionClientDescriptor(session) {
                            Text(clientDescriptor)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text("state=\(session.activityState.rawValue), score=\(session.activityScore), repo=\(session.repositoryRoot ?? "(unassigned)")")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Text("업데이트 \(relativeTimestamp(session.updatedAt))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
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
        async let insights = manager.discoverGitRepositoryInsights(searchPaths: nil, limit: 60)
        unifiedSessions = await unified
        discoveredSessions = await discovered
        gitInsights = await insights
        if let repositoryRoot = explorerFilter.repositoryRoot {
            explorerFilter.repositoryRoot = normalizedRepositoryPath(repositoryRoot)
        }
        if let repositoryRoot = orchestrationRepositoryRoot {
            orchestrationRepositoryRoot = normalizedRepositoryPath(repositoryRoot)
        }
        syncExpandedRepositoryGroups()
        refreshKPIReport()
        isRefreshingUnified = false
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
                command: command
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
                command: command
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
    }

    @MainActor
    private func refreshKPIReport() {
        kpiReport = manager.sessionManagementKPIReport()
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

    private func normalizedRepositoryPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
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
