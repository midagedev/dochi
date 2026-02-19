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

enum SessionExplorerViewStateBuilder {
    private static func normalizedRepositoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
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

        switch sort {
        case .activity:
            return filtered.sorted(by: ExternalToolSessionManager.isPreferredUnifiedSessionOrder(_:_:))
        case .updatedAt:
            return filtered.sorted(by: { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return ExternalToolSessionManager.sessionStableKey(lhs) < ExternalToolSessionManager.sessionStableKey(rhs)
            })
        case .provider:
            return filtered.sorted(by: { lhs, rhs in
                let compare = lhs.provider.localizedCaseInsensitiveCompare(rhs.provider)
                if compare != .orderedSame {
                    return compare == .orderedAscending
                }
                return ExternalToolSessionManager.isPreferredUnifiedSessionOrder(lhs, rhs)
            })
        }
    }
}
