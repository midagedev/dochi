import Foundation

// MARK: - MemoryPipelineProtocol

/// Processes memory candidates through classification, deduplication, approval, and storage.
///
/// Pipeline stages (spec 05, section 5):
/// 1. Extract candidate from conversation/tool result
/// 2. Classify into target layer (personal/workspace/agent/drop)
/// 3. Check for duplicates/conflicts against existing memory
/// 4. Apply approval policy (auto/requireApproval)
/// 5. Store via ContextService
/// 6. Emit audit event
@MainActor
protocol MemoryPipelineProtocol {
    /// Submit a single candidate for async processing (classification + storage).
    func submitCandidate(_ candidate: MemoryCandidate) async

    /// Classify a candidate into its target layer.
    func classifyCandidate(_ candidate: MemoryCandidate) -> MemoryClassification

    /// Classify, deduplicate, and store a candidate. Throws on storage failure.
    func processAndStore(_ candidate: MemoryCandidate) async throws

    /// Number of candidates in the retry queue.
    func pendingCount() -> Int

    /// Batch: process conversation end — extract candidates and run full pipeline.
    func processConversationEnd(
        messages: [Message],
        sessionId: String,
        sessionContext: SessionContext,
        settings: AppSettings
    ) async -> MemoryPipelineResult

    /// Batch: process tool result — extract candidates and run full pipeline.
    func processToolResult(
        toolName: String,
        result: String,
        sessionId: String,
        sessionContext: SessionContext,
        settings: AppSettings
    ) async -> MemoryPipelineResult

    /// Regenerate projections for all layers.
    func regenerateProjections(
        workspaceId: UUID,
        agentName: String,
        userId: String?
    ) -> [MemoryTargetLayer: MemoryProjection]

    /// Current cached projections.
    var currentProjections: [MemoryTargetLayer: MemoryProjection] { get }

    /// All audit events recorded during this session.
    var auditLog: [MemoryAuditEvent] { get }
}
