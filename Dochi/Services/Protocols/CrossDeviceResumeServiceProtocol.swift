import Foundation

// MARK: - CrossDeviceResumeResult

/// Outcome of a cross-device session resolution attempt.
enum CrossDeviceResumeResult: Sendable, Equatable {
    /// An existing session was successfully resumed.
    /// - Parameters:
    ///   - sessionId: Dochi-side session ID.
    ///   - sdkSessionId: Claude SDK session ID for resume.
    ///   - previousDeviceId: The device ID that previously held the session, or `nil` if same device.
    case resumed(sessionId: String, sdkSessionId: String, previousDeviceId: String?)

    /// A brand-new session was created (no existing session found).
    /// - Parameters:
    ///   - sessionId: Dochi-side session ID.
    ///   - sdkSessionId: Claude SDK session ID.
    case created(sessionId: String, sdkSessionId: String)

    /// Resume attempt failed.
    case failed(reason: CrossDeviceFailureReason)
}

// MARK: - CrossDeviceFailureReason

/// Reasons a cross-device resume can fail.
enum CrossDeviceFailureReason: String, Sendable, Equatable {
    /// The agent runtime is not in a ready state.
    case runtimeNotReady
    /// The session mapping data is corrupted or unreadable.
    case sessionCorrupted
    /// The target conversation could not be found.
    case conversationNotFound
    /// Session open RPC returned an error.
    case sessionOpenFailed
}

// MARK: - DeviceTransferRecord

/// Audit record for a cross-device session transfer.
struct DeviceTransferRecord: Sendable, Equatable {
    let sessionId: String
    let fromDeviceId: String
    let toDeviceId: String
    let timestamp: Date

    init(sessionId: String, fromDeviceId: String, toDeviceId: String, timestamp: Date = Date()) {
        self.sessionId = sessionId
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
        self.timestamp = timestamp
    }
}

// MARK: - Protocol

/// Coordinates session resolution across devices.
///
/// When a user opens a conversation on a different device (e.g. Mac at home vs. office,
/// or Telegram vs. native app), this service determines whether to resume the existing
/// SDK session or create a new one.
///
/// @MainActor required: session state lookups and mutations are coordinated on the main
/// actor to avoid data races with ViewModel and SessionMappingService.
@MainActor
protocol CrossDeviceResumeServiceProtocol: Sendable {
    /// Resolve which session to use for the given conversation, regardless of device.
    ///
    /// 1. Looks up an active session for (workspaceId, agentId, conversationId).
    /// 2. If found and deviceId differs: cross-device resume with transfer record.
    /// 3. If found and deviceId matches: same-device resume.
    /// 4. If not found: opens a new session via the runtime bridge.
    /// 5. If open fails: returns `.failed`.
    func resolveSession(
        workspaceId: String,
        agentId: String,
        conversationId: String,
        userId: String,
        deviceId: String
    ) async -> CrossDeviceResumeResult

    /// Record an explicit device transfer for audit purposes.
    func recordDeviceTransfer(sessionId: String, fromDeviceId: String, toDeviceId: String)

    /// All device transfer records, ordered by timestamp ascending.
    var transferHistory: [DeviceTransferRecord] { get }
}
