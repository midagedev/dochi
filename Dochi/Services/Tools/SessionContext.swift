import Foundation

/// Holds mutable session state used by tools (current user, workspace, etc.).
/// Reset when session ends.
@MainActor
final class SessionContext {
    var workspaceId: UUID
    var currentUserId: String?
    var currentProjectId: String?
    var currentBranch: String?

    /// Called when `currentRepoPath` changes to a new non-nil value.
    var onRepoPathChanged: ((String) async -> Void)?

    /// The active repository path. Setting a new value triggers `onRepoPathChanged`.
    var currentRepoPath: String? {
        didSet {
            guard let newPath = currentRepoPath, newPath != oldValue else { return }
            if let callback = onRepoPathChanged {
                Task { @MainActor in
                    await callback(newPath)
                }
            }
        }
    }

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
