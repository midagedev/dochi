import Foundation

/// Protocol for session mapping persistence and lookup.
///
/// Maps Dochi session keys to SDK session IDs so sessions can be resumed.
/// The composite key (`workspaceId + agentId + conversationId`) uniquely
/// identifies a logical session; `deviceId` is excluded from lookup to
/// support cross-device resume.
///
/// @MainActor required: session state is shared across services
/// (SessionResumeService, CrossDeviceResumeService) which are all
/// MainActor-isolated. Keeping this protocol on MainActor prevents
/// data races without additional locking.
@MainActor
protocol SessionMappingServiceProtocol {
    /// Look up an existing active mapping by composite key (deviceId excluded for cross-device resume).
    func findActive(
        workspaceId: String,
        agentId: String,
        conversationId: String
    ) -> SessionMapping?

    /// Find a mapping by its Dochi session ID.
    func findBySessionId(_ sessionId: String) -> SessionMapping?

    /// Insert a new mapping and persist.
    func insert(_ mapping: SessionMapping)

    /// Update the status of a mapping by session ID.
    func updateStatus(sessionId: String, status: SessionMappingStatus)

    /// Update the device ID for a session mapping (cross-device resume).
    ///
    /// Called when a session is resumed from a different device so the mapping
    /// reflects the current device for audit and future lookups.
    func updateDeviceId(sessionId: String, newDeviceId: String)

    /// Touch the last-active timestamp for a session.
    func touch(sessionId: String)

    /// Return all mappings (for session.list).
    var allMappings: [SessionMapping] { get }

    /// Return only active mappings.
    var activeMappings: [SessionMapping] { get }

    /// Remove closed/interrupted mappings older than the given interval.
    func pruneStale(olderThan interval: TimeInterval)
}
