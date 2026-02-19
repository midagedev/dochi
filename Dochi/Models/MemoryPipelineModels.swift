import Foundation

// MARK: - DeduplicationResult

/// 중복 검사 결과
struct DeduplicationResult: Sendable {
    let classification: MemoryClassification
    let originalContent: String
    let isDuplicate: Bool
    let isConflict: Bool
    let conflictingContent: String?
    let similarity: Double

    init(
        classification: MemoryClassification,
        originalContent: String,
        isDuplicate: Bool = false,
        isConflict: Bool = false,
        conflictingContent: String? = nil,
        similarity: Double = 0.0
    ) {
        self.classification = classification
        self.originalContent = originalContent
        self.isDuplicate = isDuplicate
        self.isConflict = isConflict
        self.conflictingContent = conflictingContent
        self.similarity = similarity
    }
}

// MARK: - RetryEntry

/// 재시도 큐 항목
struct RetryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let content: String
    let targetLayer: MemoryTargetLayer
    let workspaceId: String
    let agentName: String
    let userId: String?
    let attemptCount: Int
    let lastAttemptAt: Date
    let createdAt: Date
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        content: String,
        targetLayer: MemoryTargetLayer,
        workspaceId: String,
        agentName: String,
        userId: String?,
        attemptCount: Int = 0,
        lastAttemptAt: Date = Date(),
        createdAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.content = content
        self.targetLayer = targetLayer
        self.workspaceId = workspaceId
        self.agentName = agentName
        self.userId = userId
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.createdAt = createdAt
        self.errorMessage = errorMessage
    }

    /// 다음 재시도 시각 (지수 백오프: 2^attempt * 5초, 최대 5분)
    var nextRetryAt: Date {
        let delay = min(pow(2.0, Double(attemptCount)) * 5.0, 300.0)
        return lastAttemptAt.addingTimeInterval(delay)
    }

    var isExhausted: Bool {
        attemptCount >= RetryEntry.maxAttempts
    }

    static let maxAttempts = 5
}

// MARK: - ConflictEntry

/// 충돌이 감지된 메모리 후보. 승인 대기 큐에 보관된다.
struct ConflictEntry: Sendable, Identifiable {
    let id: UUID
    let candidateId: String
    let content: String
    let conflictingContent: String
    let targetLayer: MemoryTargetLayer
    let workspaceId: String
    let agentId: String?
    let userId: String?
    let similarity: Double
    let detectedAt: Date

    init(
        id: UUID = UUID(),
        candidateId: String,
        content: String,
        conflictingContent: String,
        targetLayer: MemoryTargetLayer,
        workspaceId: String,
        agentId: String? = nil,
        userId: String? = nil,
        similarity: Double,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.candidateId = candidateId
        self.content = content
        self.conflictingContent = conflictingContent
        self.targetLayer = targetLayer
        self.workspaceId = workspaceId
        self.agentId = agentId
        self.userId = userId
        self.similarity = similarity
        self.detectedAt = detectedAt
    }
}

// MARK: - MemoryPipelineResult

/// 파이프라인 실행 결과
struct MemoryPipelineResult: Sendable, Equatable {
    let candidatesExtracted: Int
    let candidatesClassified: Int
    let candidatesDropped: Int
    let duplicatesSkipped: Int
    let conflictsDetected: Int
    let candidatesStored: Int
    let retryQueued: Int

    static let empty = MemoryPipelineResult(
        candidatesExtracted: 0,
        candidatesClassified: 0,
        candidatesDropped: 0,
        duplicatesSkipped: 0,
        conflictsDetected: 0,
        candidatesStored: 0,
        retryQueued: 0
    )
}
