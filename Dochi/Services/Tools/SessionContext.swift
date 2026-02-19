import Foundation

/// Holds mutable session state used by tools (current user, workspace, etc.).
/// Reset when session ends.
@MainActor
final class SessionContext {
    var workspaceId: UUID
    var currentUserId: String?
    var currentProjectId: String?
    var currentRepoPath: String?
    var currentBranch: String?

    init(
        workspaceId: UUID,
        currentUserId: String? = nil,
        currentProjectId: String? = nil,
        currentRepoPath: String? = nil,
        currentBranch: String? = nil
    ) {
        self.workspaceId = workspaceId
        self.currentUserId = currentUserId
        self.currentProjectId = currentProjectId
        self.currentRepoPath = currentRepoPath
        self.currentBranch = currentBranch
    }
}
