import SwiftUI

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
    @State private var isRefreshingUnified = false
    @State private var explorerFilter = SessionExplorerFilter()
    @State private var sortOption: SessionExplorerSortOption = .activity
    @State private var mappingNotice: String?

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
            ].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private var unassignedUnifiedSessions: [UnifiedCodingSession] {
        unifiedSessions
            .filter(\.isUnassigned)
            .sorted(by: ExternalToolSessionManager.isPreferredUnifiedSessionOrder(_:_:))
    }

    private var repositoryFilterOptions: [String] {
        var options = Set(managedRepositories.map(\.rootPath))
        options.formUnion(unifiedSessions.compactMap(\.repositoryRoot))
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
        .task {
            await refreshUnifiedSessions()
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
                unassignedQueueSection

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
                Text("레포 대시보드 / 필터 / Unassigned 매핑")
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text("세션 \(summary.sessionCount) · 활성 \(summary.activeSessionCount) · 오류 \(summary.errorSessionCount)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if let repositoryRoot = summary.repositoryRoot {
                                let branch = managedRepositories.first(where: {
                                    URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == repositoryRoot
                                })?.defaultBranch ?? "-"
                                Text("브랜치 \(branch)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("Unassigned")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(8)
                        .frame(width: 170, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var sessionExplorerSection: some View {
        sectionHeader("Session Explorer")

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

        if filteredUnifiedSessions.isEmpty {
            Text("필터 조건에 맞는 세션이 없습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            ForEach(
                filteredUnifiedSessions.map { (key: ExternalToolSessionManager.sessionStableKey($0), value: $0) },
                id: \.key
            ) { item in
                unifiedSessionRow(item.value)
            }
        }
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
    private func unifiedSessionRow(_ session: UnifiedCodingSession) -> some View {
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

                Text("state=\(session.activityState.rawValue), score=\(session.activityScore), repo=\(session.repositoryRoot ?? "(unassigned)")")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
                Task { @MainActor in
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
                    } catch {
                        startErrorMessage = error.localizedDescription
                    }
                }
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
        unifiedSessions = await manager.listUnifiedCodingSessions(limit: 180)
        isRefreshingUnified = false
    }

    @MainActor
    private func applyManualMapping(session: UnifiedCodingSession, repositoryRoot: String) {
        manager.setManualRepositoryBinding(
            provider: session.provider,
            nativeSessionId: session.nativeSessionId,
            path: session.path,
            repositoryRoot: repositoryRoot
        )
        let repoName = URL(fileURLWithPath: repositoryRoot).lastPathComponent
        mappingNotice = "[\(session.nativeSessionId)] 세션을 \(repoName) 레포로 연결했습니다."
        Task {
            await refreshUnifiedSessions()
        }
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
