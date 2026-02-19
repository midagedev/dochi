import Foundation

// MARK: - MemoryCandidate

/// A candidate memory entry extracted from conversation or tool results,
/// pending classification and storage.
struct MemoryCandidate: Codable, Sendable, Identifiable {
    let id: String
    let content: String
    let source: MemoryCandidateSource
    let timestamp: Date
    let sessionId: String
    let workspaceId: String
    let agentId: String?
    let userId: String?

    init(
        id: String = UUID().uuidString,
        content: String,
        source: MemoryCandidateSource,
        timestamp: Date = Date(),
        sessionId: String,
        workspaceId: String,
        agentId: String? = nil,
        userId: String? = nil
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.workspaceId = workspaceId
        self.agentId = agentId
        self.userId = userId
    }
}

// MARK: - MemoryCandidateSource

/// Where the memory candidate originated.
enum MemoryCandidateSource: String, Codable, Sendable {
    case conversation
    case toolResult
    case userExplicit
}

// MARK: - MemoryTargetLayer

/// Which memory layer a candidate should be stored in.
enum MemoryTargetLayer: String, Codable, Sendable {
    case personal
    case workspace
    case agent
    case drop
}

// MARK: - MemoryClassification

/// Result of classifying a memory candidate into a target layer.
struct MemoryClassification: Codable, Sendable {
    let candidateId: String
    let targetLayer: MemoryTargetLayer
    let confidence: Double
    let reason: String
}

// MARK: - MemoryProjection

/// A compressed representation of memory for a given layer.
///
/// Contains a summary of the full memory log and a list of hot facts
/// (frequently referenced or recently added items).
struct MemoryProjection: Codable, Sendable {
    let layer: MemoryTargetLayer
    let summary: String
    let hotFacts: [String]
    let generatedAt: Date
    let sourceCharCount: Int
}
