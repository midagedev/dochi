import Foundation

struct SessionExplorerFilter: Sendable, Equatable {
    var repositoryRoot: String? = nil
    var provider: String? = nil
    var tier: CodingSessionControllabilityTier? = nil
    var activeOnly: Bool = false
    var unassignedOnly: Bool = false
}

enum SessionExplorerSortOption: String, CaseIterable, Sendable {
    case activity
    case updatedAt = "updated_at"
    case provider
}

struct RepositoryDashboardSummary: Identifiable, Sendable, Equatable {
    let id: String
    let repositoryRoot: String?
    let displayName: String
    let branch: String?
    let sessionCount: Int
    let activeSessionCount: Int
    let errorSessionCount: Int
    let lastActivityAt: Date?
}

struct RepositorySessionGroup: Identifiable, Sendable, Equatable {
    let id: String
    let repositoryRoot: String
    let displayName: String
    let sessionCount: Int
    let activeSessionCount: Int
    let errorSessionCount: Int
    let lastActivityAt: Date?
    let sessions: [UnifiedCodingSession]
}

enum OrchestrationWorkboardLane: String, CaseIterable, Sendable {
    case blocked
    case running
    case review
    case queued
    case done

    static var displayOrder: [OrchestrationWorkboardLane] {
        [.blocked, .running, .review, .queued, .done]
    }
}

struct OrchestrationWorkboardGroup: Identifiable, Sendable, Equatable {
    let lane: OrchestrationWorkboardLane
    let sessions: [UnifiedCodingSession]

    var id: String { lane.rawValue }
}

struct OrchestrationProviderSummary: Identifiable, Sendable, Equatable {
    let provider: String
    let count: Int

    var id: String {
        provider.lowercased()
    }
}

struct OrchestrationLaneSummary: Identifiable, Sendable, Equatable {
    let lane: OrchestrationWorkboardLane
    let count: Int

    var id: String {
        lane.rawValue
    }
}

struct OrchestrationFleetSnapshot: Sendable, Equatable {
    let totalSessionCount: Int
    let activeSessionCount: Int
    let idleSessionCount: Int
    let blockedSessionCount: Int
    let queuedSessionCount: Int
    let unassignedSessionCount: Int
    let actionableSessionCount: Int
    let repositoryCount: Int
    let providerBreakdown: [OrchestrationProviderSummary]
    let laneBreakdown: [OrchestrationLaneSummary]
}

enum SessionExplorerViewStateBuilder {
    private static func normalizedRepositoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func repositoryContainsWorkingDirectory(
        repositoryRoot: String,
        workingDirectory: String
    ) -> Bool {
        let normalizedRoot = normalizedRepositoryPath(repositoryRoot)
        let normalizedWorkingDirectory = normalizedRepositoryPath(workingDirectory)
        guard let normalizedRoot, let normalizedWorkingDirectory else { return false }
        if normalizedWorkingDirectory == normalizedRoot {
            return true
        }
        return normalizedWorkingDirectory.hasPrefix(normalizedRoot + "/")
    }

    private static func sortSessions(
        _ sessions: [UnifiedCodingSession],
        sort: SessionExplorerSortOption
    ) -> [UnifiedCodingSession] {
        switch sort {
        case .activity:
            return sessions.sorted(by: ExternalToolSessionManager.isPreferredUnifiedSessionOrder(_:_:))
        case .updatedAt:
            return sessions.sorted(by: { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return ExternalToolSessionManager.sessionStableKey(lhs) < ExternalToolSessionManager.sessionStableKey(rhs)
            })
        case .provider:
            return sessions.sorted(by: { lhs, rhs in
                let compare = lhs.provider.localizedCaseInsensitiveCompare(rhs.provider)
                if compare != .orderedSame {
                    return compare == .orderedAscending
                }
                return ExternalToolSessionManager.isPreferredUnifiedSessionOrder(lhs, rhs)
            })
        }
    }

    static func repositorySummaries(from sessions: [UnifiedCodingSession]) -> [RepositoryDashboardSummary] {
        let grouped = Dictionary(grouping: sessions, by: { $0.repositoryRoot })
        return grouped.map { repositoryRoot, groupedSessions in
            let standardized = repositoryRoot.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            let displayName = standardized.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unassigned"
            let activeCount = groupedSessions.filter { $0.activityState == .active || $0.activityState == .idle }.count
            let errorCount = groupedSessions.filter { $0.activitySignals.errorPenaltyScore > 0 }.count

            return RepositoryDashboardSummary(
                id: standardized ?? "unassigned",
                repositoryRoot: standardized,
                displayName: displayName,
                branch: nil,
                sessionCount: groupedSessions.count,
                activeSessionCount: activeCount,
                errorSessionCount: errorCount,
                lastActivityAt: groupedSessions.map(\.updatedAt).max()
            )
        }
        .sorted(by: { lhs, rhs in
            if lhs.activeSessionCount != rhs.activeSessionCount {
                return lhs.activeSessionCount > rhs.activeSessionCount
            }
            if lhs.lastActivityAt != rhs.lastActivityAt {
                return (lhs.lastActivityAt ?? .distantPast) > (rhs.lastActivityAt ?? .distantPast)
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        })
    }

    static func filteredSessions(
        sessions: [UnifiedCodingSession],
        filter: SessionExplorerFilter,
        sort: SessionExplorerSortOption
    ) -> [UnifiedCodingSession] {
        let normalizedFilterRoot = normalizedRepositoryPath(filter.repositoryRoot)
        let filtered = sessions.filter { session in
            if let normalizedFilterRoot {
                let normalizedSessionRoot = normalizedRepositoryPath(session.repositoryRoot)
                if normalizedSessionRoot != normalizedFilterRoot {
                    return false
                }
            }
            if let provider = filter.provider {
                if session.provider.localizedCaseInsensitiveCompare(provider) != .orderedSame {
                    return false
                }
            }
            if let tier = filter.tier, session.controllabilityTier != tier {
                return false
            }
            if filter.activeOnly, !(session.activityState == .active || session.activityState == .idle) {
                return false
            }
            if filter.unassignedOnly, !session.isUnassigned {
                return false
            }
            return true
        }

        return sortSessions(filtered, sort: sort)
    }

    static func repositoryGroups(
        sessions: [UnifiedCodingSession],
        sort: SessionExplorerSortOption
    ) -> [RepositorySessionGroup] {
        let assignedSessions = sessions.compactMap { session -> (String, UnifiedCodingSession)? in
            guard let repositoryRoot = normalizedRepositoryPath(session.repositoryRoot) else { return nil }
            return (repositoryRoot, session)
        }
        let grouped = Dictionary(grouping: assignedSessions, by: { $0.0 })

        return grouped.map { repositoryRoot, entries in
            let sortedSessions = sortSessions(entries.map(\.1), sort: sort)
            let displayName = URL(fileURLWithPath: repositoryRoot).lastPathComponent
            let activeCount = sortedSessions.filter { $0.activityState == .active || $0.activityState == .idle }.count
            let errorCount = sortedSessions.filter { $0.activitySignals.errorPenaltyScore > 0 }.count
            return RepositorySessionGroup(
                id: repositoryRoot,
                repositoryRoot: repositoryRoot,
                displayName: displayName,
                sessionCount: sortedSessions.count,
                activeSessionCount: activeCount,
                errorSessionCount: errorCount,
                lastActivityAt: sortedSessions.map(\.updatedAt).max(),
                sessions: sortedSessions
            )
        }
        .sorted(by: { lhs, rhs in
            if lhs.activeSessionCount != rhs.activeSessionCount {
                return lhs.activeSessionCount > rhs.activeSessionCount
            }
            if lhs.lastActivityAt != rhs.lastActivityAt {
                return (lhs.lastActivityAt ?? .distantPast) > (rhs.lastActivityAt ?? .distantPast)
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        })
    }

    static func orchestrationWorkboardLane(
        for session: UnifiedCodingSession
    ) -> OrchestrationWorkboardLane {
        if session.activityState == .dead || session.activitySignals.errorPenaltyScore > 0 {
            return .blocked
        }
        if session.isUnassigned {
            return .queued
        }
        if session.activityState == .active {
            return .running
        }
        if session.activityState == .idle && session.activityScore >= 70 {
            return .done
        }
        return .review
    }

    static func orchestrationWorkboardGroups(
        sessions: [UnifiedCodingSession],
        sort: SessionExplorerSortOption = .activity
    ) -> [OrchestrationWorkboardGroup] {
        let sorted = sortSessions(sessions, sort: sort)
        var grouped: [OrchestrationWorkboardLane: [UnifiedCodingSession]] = [:]
        for session in sorted {
            let lane = orchestrationWorkboardLane(for: session)
            grouped[lane, default: []].append(session)
        }

        return OrchestrationWorkboardLane.displayOrder.compactMap { lane in
            guard let laneSessions = grouped[lane], !laneSessions.isEmpty else { return nil }
            return OrchestrationWorkboardGroup(lane: lane, sessions: laneSessions)
        }
    }

    static func orchestrationFleetSnapshot(
        sessions: [UnifiedCodingSession],
        providerLimit: Int = 5
    ) -> OrchestrationFleetSnapshot {
        let normalizedProviderLimit = max(1, min(12, providerLimit))
        var activeSessionCount = 0
        var idleSessionCount = 0
        var unassignedSessionCount = 0
        var actionableSessionCount = 0
        var repositoryRoots: Set<String> = []
        var laneCounts: [OrchestrationWorkboardLane: Int] = [:]
        var providerCounts: [String: (display: String, count: Int)] = [:]

        for session in sessions {
            switch session.activityState {
            case .active:
                activeSessionCount += 1
            case .idle:
                idleSessionCount += 1
            case .stale, .dead:
                break
            }

            if session.isUnassigned {
                unassignedSessionCount += 1
            } else if let repositoryRoot = normalizedRepositoryPath(session.repositoryRoot) {
                repositoryRoots.insert(repositoryRoot)
            }

            if session.activityState != .dead,
               session.controllabilityTier == .t0Full || session.controllabilityTier == .t1Attach {
                actionableSessionCount += 1
            }

            let lane = orchestrationWorkboardLane(for: session)
            laneCounts[lane, default: 0] += 1

            let providerKey = session.provider
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let providerDisplay = normalizedProviderDisplayName(session.provider)
            if let existing = providerCounts[providerKey] {
                providerCounts[providerKey] = (display: existing.display, count: existing.count + 1)
            } else {
                providerCounts[providerKey] = (display: providerDisplay, count: 1)
            }
        }

        let providerBreakdown = providerCounts
            .values
            .map { entry in
                OrchestrationProviderSummary(provider: entry.display, count: entry.count)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) == .orderedAscending
            }
            .prefix(normalizedProviderLimit)

        let laneBreakdown = OrchestrationWorkboardLane.displayOrder.map { lane in
            OrchestrationLaneSummary(lane: lane, count: laneCounts[lane, default: 0])
        }

        return OrchestrationFleetSnapshot(
            totalSessionCount: sessions.count,
            activeSessionCount: activeSessionCount,
            idleSessionCount: idleSessionCount,
            blockedSessionCount: laneCounts[.blocked, default: 0],
            queuedSessionCount: laneCounts[.queued, default: 0],
            unassignedSessionCount: unassignedSessionCount,
            actionableSessionCount: actionableSessionCount,
            repositoryCount: repositoryRoots.count,
            providerBreakdown: Array(providerBreakdown),
            laneBreakdown: laneBreakdown
        )
    }

    static func preferredSession(
        in repositoryRoot: String?,
        sessions: [UnifiedCodingSession]
    ) -> UnifiedCodingSession? {
        let normalizedRoot = normalizedRepositoryPath(repositoryRoot)
        let scoped = sessions.filter { session in
            let normalizedSessionRoot = normalizedRepositoryPath(session.repositoryRoot)
            return normalizedSessionRoot == normalizedRoot
        }
        return sortSessions(scoped, sort: .activity).first
    }

    static func selectedSession(
        sessions: [UnifiedCodingSession],
        selectedSessionKey: String?,
        selectedSessionId: UUID?
    ) -> UnifiedCodingSession? {
        if let selectedSessionKey {
            if let matchedByKey = sessions.first(where: {
                ExternalToolSessionManager.sessionStableKey($0) == selectedSessionKey
            }) {
                return matchedByKey
            }
        }

        if let selectedSessionId {
            if let matchedByRuntime = sessions.first(where: { session in
                guard let runtimeSessionId = session.runtimeSessionId,
                      let runtimeUUID = UUID(uuidString: runtimeSessionId) else {
                    return false
                }
                return runtimeUUID == selectedSessionId
            }) {
                return matchedByRuntime
            }
        }

        return nil
    }

    static func selectedRepositorySummary(
        summaries: [RepositoryDashboardSummary],
        focusedRepositoryKey: String?
    ) -> RepositoryDashboardSummary? {
        guard let focusedRepositoryKey, !focusedRepositoryKey.isEmpty else { return nil }

        if let exact = summaries.first(where: { $0.id == focusedRepositoryKey }) {
            return exact
        }

        if focusedRepositoryKey == "unassigned" {
            return summaries.first(where: { $0.repositoryRoot == nil })
        }

        guard let normalized = normalizedRepositoryPath(focusedRepositoryKey) else { return nil }
        return summaries.first(where: { summary in
            guard let repositoryRoot = summary.repositoryRoot else { return false }
            return normalizedRepositoryPath(repositoryRoot) == normalized
        })
    }

    static func selectionFilter(for repositoryRoot: String?) -> SessionExplorerFilter {
        let normalizedRoot = normalizedRepositoryPath(repositoryRoot)
        return SessionExplorerFilter(
            repositoryRoot: normalizedRoot,
            provider: nil,
            tier: nil,
            activeOnly: false,
            unassignedOnly: normalizedRoot == nil
        )
    }

    static func displaySessionTitle(for session: UnifiedCodingSession) -> String {
        if let explicitTitle = normalizedCompactText(session.title, maxLength: 96),
           !looksLikeOpaqueSessionIdentifier(explicitTitle) {
            return explicitTitle
        }

        if let summary = normalizedCompactText(session.summary, maxLength: 96),
           !looksLikeOpaqueSessionIdentifier(summary) {
            return summary
        }

        let repositoryName = normalizedRepositoryPath(session.repositoryRoot ?? session.workingDirectory)
            .map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unassigned"
        let providerLabel = sessionProviderLabel(provider: session.provider, clientKind: session.clientKind)
        let action = defaultActivityAction(for: session.activityState)
        return "\(repositoryName) · \(providerLabel) · \(action)"
    }

    static func displaySessionIdentity(for session: UnifiedCodingSession) -> String {
        "[\(session.provider)] \(session.nativeSessionId)"
    }

    static func sessionWorkLine(for session: UnifiedCodingSession) -> String {
        if let summary = normalizedCompactText(session.summary, maxLength: 120),
           !looksLikeOpaqueSessionIdentifier(summary),
           summary != displaySessionTitle(for: session) {
            return summary
        }
        return defaultActivityAction(for: session.activityState)
    }

    static func sessionResultLine(for session: UnifiedCodingSession) -> String {
        let stateText: String
        switch session.activityState {
        case .active:
            stateText = "진행 중"
        case .idle:
            stateText = "입력 대기"
        case .stale:
            stateText = "업데이트 지연"
        case .dead:
            stateText = "세션 종료"
        }
        if session.activitySignals.errorPenaltyScore > 0 {
            return "오류 신호 · \(stateText)"
        }
        return stateText
    }

    static func sessionChangeLine(session: UnifiedCodingSession, insight: GitRepositoryInsight?) -> String {
        guard session.repositoryRoot != nil else { return "레포 미할당" }
        guard let insight else { return "변경 정보 없음" }
        return repositoryWorkingTreeLine(for: insight)
    }

    static func sessionRepositoryStatusLine(session: UnifiedCodingSession, insight: GitRepositoryInsight?) -> String {
        guard session.repositoryRoot != nil else { return "레포 미할당" }
        let branch = normalizedCompactText(insight?.branch, maxLength: 42) ?? "-"
        let workingTree = repositoryWorkingTreeLine(for: insight)
        return "브랜치 \(branch) · \(workingTree)"
    }

    static func sessionCommitLine(for insight: GitRepositoryInsight?) -> String {
        if let preview = repositoryCommitFeedLines(for: insight, limit: 1).first {
            return preview
        }
        guard let insight else { return "최근 커밋 정보 없음" }
        let relative = insight.lastCommitRelative.trimmingCharacters(in: .whitespacesAndNewlines)
        if !relative.isEmpty, relative != "-" {
            return "최근 커밋 \(relative)"
        }
        return "최근 커밋 정보 없음"
    }

    static func sessionLocationLine(
        for session: UnifiedCodingSession,
        homeDirectoryPath: String = NSHomeDirectory()
    ) -> String {
        compactPathForDisplay(
            session.workingDirectory ?? session.path,
            repositoryRoot: session.repositoryRoot,
            homeDirectoryPath: homeDirectoryPath
        )
    }

    static func repositoryCommitFeedLines(for insight: GitRepositoryInsight?, limit: Int = 5) -> [String] {
        guard let insight else { return [] }
        let normalizedLimit = max(1, min(8, limit))

        if let previews = insight.recentCommitPreviews, !previews.isEmpty {
            return previews.prefix(normalizedLimit).map { preview in
                "\(preview.shortHash) \(preview.subject) · \(preview.relative)"
            }
        }

        let shortHash = insight.lastCommitShortHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = insight.lastCommitSubject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let relative = insight.lastCommitRelative.trimmingCharacters(in: .whitespacesAndNewlines)
        if let shortHash, !shortHash.isEmpty,
           let subject, !subject.isEmpty {
            return ["\(shortHash) \(subject) · \(relative)"]
        }
        return []
    }

    static func repositoryWorkingTreeLine(for insight: GitRepositoryInsight?) -> String {
        guard let insight else { return "워킹트리 정보 없음" }
        let changed = max(0, insight.changedFileCount)
        let untracked = max(0, insight.untrackedFileCount)
        let total = changed + untracked
        guard total > 0 else { return "워킹트리 변경 없음" }

        let preview = Array((insight.changedPathPreview ?? [String]()).prefix(3))
        if !preview.isEmpty {
            let remained = max(0, total - preview.count)
            let suffix = remained > 0 ? " 외 \(remained)개" : ""
            return "\(preview.joined(separator: ", "))\(suffix)"
        }
        return "수정 \(changed) · 신규 \(untracked)"
    }

    private static func normalizedCompactText(_ raw: String?, maxLength: Int) -> String? {
        guard let raw else { return nil }
        let normalized = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(max(20, maxLength)))
    }

    private static func compactPathForDisplay(
        _ rawPath: String,
        repositoryRoot: String?,
        homeDirectoryPath: String
    ) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        if trimmed.contains("://") {
            return String(trimmed.prefix(120))
        }

        let normalizedPath = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        if let normalizedRoot = normalizedRepositoryPath(repositoryRoot) {
            if normalizedPath == normalizedRoot {
                return "."
            }
            if normalizedPath.hasPrefix(normalizedRoot + "/") {
                let suffix = String(normalizedPath.dropFirst(normalizedRoot.count + 1))
                return "./" + String(suffix.prefix(120))
            }
        }

        let normalizedHome = URL(fileURLWithPath: homeDirectoryPath).standardizedFileURL.path
        if normalizedPath == normalizedHome {
            return "~"
        }
        if normalizedPath.hasPrefix(normalizedHome + "/") {
            let suffix = String(normalizedPath.dropFirst(normalizedHome.count + 1))
            return "~/" + String(suffix.prefix(120))
        }

        return String(normalizedPath.prefix(120))
    }

    private static func sessionProviderLabel(provider: String, clientKind: String?) -> String {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedProvider == "codex" {
            switch clientKind {
            case "desktop":
                return "Codex Desktop"
            case "cli":
                return "Codex CLI"
            default:
                return "Codex"
            }
        }

        let compact = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "Session" : compact.capitalized
    }

    private static func normalizedProviderDisplayName(_ provider: String) -> String {
        let trimmed = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }

        let normalized = trimmed.lowercased()
        if normalized == "codex" || normalized == "chatgpt" {
            return "Codex"
        }
        if normalized == "claude" || normalized == "anthropic" {
            return "Claude"
        }
        if normalized == "gemini" {
            return "Gemini"
        }
        if normalized == "openai" {
            return "OpenAI"
        }
        return trimmed.capitalized
    }

    private static func defaultActivityAction(for state: CodingSessionActivityState) -> String {
        switch state {
        case .active:
            return "작업 진행 중"
        case .idle:
            return "입력 대기 중"
        case .stale:
            return "최근 작업 정보가 지연됨"
        case .dead:
            return "세션이 종료됨"
        }
    }

    private static func looksLikeOpaqueSessionIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if trimmed.range(
            of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
            options: .regularExpression
        ) != nil {
            return true
        }

        let compact = trimmed.lowercased().replacingOccurrences(of: "-", with: "")
        if compact.count >= 24 {
            let isHexLike = compact.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdef").contains($0)
            }
            if isHexLike {
                return true
            }
        }
        return false
    }
}
