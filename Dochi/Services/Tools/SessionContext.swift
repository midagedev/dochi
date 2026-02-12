import Foundation

/// Holds mutable session state used by tools (current user, workspace, etc.).
/// Reset when session ends.
@MainActor
final class SessionContext {
    let workspaceId: UUID
    var currentUserId: String?

    init(workspaceId: UUID, currentUserId: String? = nil) {
        self.workspaceId = workspaceId
        self.currentUserId = currentUserId
    }
}
