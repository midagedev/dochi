import Foundation

/// Protocol for building and retrieving context snapshots.
///
/// `@MainActor` 근거: ContextServiceProtocol이 `@MainActor` 격리이므로
/// 이를 사용하는 빌더도 동일 격리 필요.
@MainActor
protocol ContextSnapshotBuilderProtocol {
    /// Build a snapshot for the given session context.
    ///
    /// Assembles 4 layers in fixed order:
    /// 1. System (base instructions + agent persona + channel metadata)
    /// 2. Workspace (shared memory)
    /// 3. Agent (agent-specific memory)
    /// 4. Personal (current user only)
    ///
    /// - Parameters:
    ///   - workspaceId: The workspace UUID.
    ///   - agentId: The agent name/ID.
    ///   - userId: The current user ID. Personal memory is only included if non-nil and non-empty.
    ///   - channelMetadata: Optional runtime situational metadata.
    ///   - tokenBudget: Maximum token budget for all layers combined.
    /// - Returns: A fully assembled ContextSnapshot.
    func build(
        workspaceId: UUID,
        agentId: String,
        userId: String?,
        channelMetadata: String?,
        tokenBudget: Int
    ) -> ContextSnapshot

    /// Validate that a snapshot respects workspace and privacy boundaries.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot to validate.
    ///   - expectedWorkspaceId: The workspace this session belongs to.
    ///   - expectedUserId: The user making the request.
    /// - Returns: Array of boundary violation descriptions (empty = valid).
    static func validateBoundaries(
        snapshot: ContextSnapshot,
        expectedWorkspaceId: String,
        expectedUserId: String?
    ) -> [String]
}
