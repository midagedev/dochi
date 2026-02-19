import Foundation

// MARK: - ResumeFailureReason

/// Reason why a session resume attempt failed and a new session was created instead.
enum ResumeFailureReason: String, Codable, Sendable {
    /// No matching session found for the given conversation.
    case sessionNotFound
    /// Session was found but is closed/interrupted and cannot be resumed.
    case sessionClosed
    /// Lease reassignment to the requesting device failed.
    case leaseReassignmentFailed
    /// An unexpected error prevented resume.
    case internalError
}

// MARK: - ResumeMetadata

/// Contextual information about the previous session state at the time of resume.
struct ResumeMetadata: Codable, Sendable, Equatable {
    /// Device that previously held the session.
    let previousDeviceId: UUID?
    /// Channel that was used in the previous session.
    let previousChannel: SessionChannel?
    /// Timestamp of the last activity in the previous session.
    let lastActivityAt: Date?

    init(
        previousDeviceId: UUID? = nil,
        previousChannel: SessionChannel? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.previousDeviceId = previousDeviceId
        self.previousChannel = previousChannel
        self.lastActivityAt = lastActivityAt
    }
}

// MARK: - SessionResumeResult

/// Outcome of a session resume attempt.
enum SessionResumeResult: Sendable {
    /// Successfully resumed an existing session.
    case resumed(sessionId: String, deviceId: UUID, metadata: ResumeMetadata)
    /// Created a new session because the previous one could not be resumed.
    case newSession(sessionId: String, deviceId: UUID, reason: ResumeFailureReason)
    /// Resume failed and no fallback session could be created.
    case failed(error: SessionResumeError)
}

// MARK: - SessionResumeError

/// Errors that can occur during session resume.
enum SessionResumeError: Error, LocalizedError, Sendable {
    /// No conversation found with the given ID.
    case conversationNotFound(String)
    /// Failed to acquire a new lease for the session.
    case leaseAcquisitionFailed(String)
    /// An unexpected internal error occurred.
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .conversationNotFound(let id):
            return "대화를 찾을 수 없습니다: \(id)"
        case .leaseAcquisitionFailed(let reason):
            return "세션 할당 실패: \(reason)"
        case .internalError(let reason):
            return "내부 오류: \(reason)"
        }
    }

    /// User-facing guidance message for resume failure.
    var userGuidance: String {
        switch self {
        case .conversationNotFound:
            return "이전 대화를 찾을 수 없어 새 대화를 시작합니다."
        case .leaseAcquisitionFailed:
            return "현재 이용 가능한 디바이스가 없습니다. 잠시 후 다시 시도해 주세요."
        case .internalError:
            return "일시적인 오류가 발생했습니다. 새 대화를 시작해 주세요."
        }
    }
}
