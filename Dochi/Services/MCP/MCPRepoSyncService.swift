import Foundation
import os

// MARK: - MCPRepoSyncService

/// Synchronizes the coding-git MCP profile's `--repository` argument
/// with the session's current repo path.
///
/// Key behaviours:
///   - When `SessionContext.currentRepoPath` is confirmed (non-nil, valid git repo),
///     finds the coding-git profile and updates its `--repository` argument.
///   - Validates the path before applying (must be a directory with `.git`).
///   - Persists updated config to `mcpServersJSON` in AppSettings.
///   - If the coding-git profile was disabled (no repo at bootstrap), enables it.
@MainActor
final class MCPRepoSyncService {

    private let mcpService: MCPServiceProtocol
    private let settings: AppSettings

    init(mcpService: MCPServiceProtocol, settings: AppSettings) {
        self.mcpService = mcpService
        self.settings = settings
    }

    // MARK: - Public API

    /// Result of a sync attempt.
    enum SyncResult: Equatable, Sendable {
        case updated(oldPath: String?, newPath: String)
        case alreadyInSync
        case invalidPath(String)
        case profileNotFound
    }

    /// Attempts to sync the coding-git profile's repository path.
    ///
    /// - Parameter repoPath: The new repository path to set.
    /// - Returns: A `SyncResult` describing the outcome.
    func syncRepoPath(_ repoPath: String) async -> SyncResult {
        let trimmed = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.mcp.warning("Repo sync skipped: empty path")
            return .invalidPath(trimmed)
        }

        let normalized = NSString(string: trimmed).expandingTildeInPath

        guard MCPServerConfig.isValidGitRepository(at: normalized) else {
            Log.mcp.warning("Repo sync skipped: invalid git repository at '\(normalized)'")
            return .invalidPath(normalized)
        }

        guard let gitProfile = findCodingGitProfile() else {
            Log.mcp.warning("Repo sync skipped: coding-git profile not found")
            return .profileNotFound
        }

        let currentPath = gitProfile.codingGitRepoPath
        if currentPath == normalized && gitProfile.isEnabled {
            Log.mcp.debug("Repo sync: already in sync (\(normalized))")
            return .alreadyInSync
        }

        let updatedConfig = gitProfile.withUpdatedRepoPath(normalized)

        do {
            try await mcpService.updateServer(config: updatedConfig)
            persistServers()
            Log.mcp.info("Repo sync: updated coding-git from '\(currentPath ?? "nil")' to '\(normalized)'")
            return .updated(oldPath: currentPath, newPath: normalized)
        } catch {
            Log.mcp.error("Repo sync: failed to update server — \(error.localizedDescription)")
            return .invalidPath(normalized)
        }
    }

    /// Syncs the repo path from the given `SessionContext` if it has a non-nil `currentRepoPath`.
    /// Intended to be called when the session context repo changes (e.g., after a git tool call).
    func syncFromSessionContext(_ context: SessionContext) async -> SyncResult? {
        guard let repoPath = context.currentRepoPath, !repoPath.isEmpty else {
            return nil
        }
        return await syncRepoPath(repoPath)
    }

    // MARK: - Query

    /// Returns the current coding-git profile's repo path, or nil if not found / not set.
    var currentCodingGitRepoPath: String? {
        findCodingGitProfile()?.codingGitRepoPath
    }

    /// Returns whether a coding-git profile exists and is enabled.
    var isCodingGitEnabled: Bool {
        findCodingGitProfile()?.isEnabled ?? false
    }

    // MARK: - Private

    private func findCodingGitProfile() -> MCPServerConfig? {
        mcpService.listServers().first { $0.isCodingGitProfile }
    }

    private func persistServers() {
        let servers = mcpService.listServers()
        guard let data = try? JSONEncoder().encode(servers),
              let json = String(data: data, encoding: .utf8) else {
            Log.mcp.error("Failed to persist MCP servers after repo sync")
            return
        }
        settings.mcpServersJSON = json
    }
}
