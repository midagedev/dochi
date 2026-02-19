import Foundation
import CryptoKit
import os

// MARK: - ContextSnapshotBuilder

/// Assembles a ContextSnapshot from the 4-layer context hierarchy.
///
/// Assembly order (spec §05):
/// 1. Global base instructions
/// 2. Agent system.md (persona)
/// 3. Workspace memory summary + hot facts
/// 4. Agent memory summary + hot facts
/// 5. Personal memory (current user only)
/// 6. Channel/runtime metadata (appended to system layer)
///
/// Boundary rules:
/// - Personal context is injected only when userId matches
/// - Workspace boundary is never crossed (all layers scoped to workspaceId)
/// - Token budget is enforced; excess content is truncated with a note
@MainActor
final class ContextSnapshotBuilder: ContextSnapshotBuilderProtocol {

    private let contextService: any ContextServiceProtocol

    /// Default token budget (approximate). Korean text ~2 chars/token.
    static let defaultTokenBudget = 16_000

    /// Per-layer budget ratios (of total budget).
    static let layerBudgetRatios: [ContextLayerName: Double] = [
        .system: 0.35,
        .workspace: 0.25,
        .agent: 0.20,
        .personal: 0.20,
    ]

    init(contextService: any ContextServiceProtocol) {
        self.contextService = contextService
    }

    // MARK: - Build

    /// Build a snapshot for the given session context.
    ///
    /// - Parameters:
    ///   - workspaceId: The workspace UUID.
    ///   - agentId: The agent name/ID.
    ///   - userId: The current user ID. Personal memory is only included if non-nil and non-empty.
    ///   - channelMetadata: Optional runtime situational metadata (e.g., channel type, device).
    ///   - tokenBudget: Maximum token budget for all layers combined.
    /// - Returns: A fully assembled ContextSnapshot.
    func build(
        workspaceId: UUID,
        agentId: String,
        userId: String?,
        channelMetadata: String? = nil,
        tokenBudget: Int = defaultTokenBudget
    ) -> ContextSnapshot {
        let budgetChars = tokenBudget * 2  // ~2 chars/token for Korean

        // 1. Load raw content for each layer
        let systemRaw = loadSystemLayer(workspaceId: workspaceId, agentId: agentId, channelMetadata: channelMetadata)
        let workspaceRaw = contextService.loadWorkspaceMemory(workspaceId: workspaceId) ?? ""
        let agentRaw = contextService.loadAgentMemory(workspaceId: workspaceId, agentName: agentId) ?? ""
        let personalRaw: String
        if let userId, !userId.isEmpty {
            personalRaw = contextService.loadUserMemory(userId: userId) ?? ""
        } else {
            personalRaw = ""
        }

        // 2. Apply token budget to each layer
        let systemLayer = applyBudget(
            name: .system,
            content: systemRaw,
            budgetChars: Int(Double(budgetChars) * Self.layerBudgetRatios[.system]!)
        )
        let workspaceLayer = applyBudget(
            name: .workspace,
            content: workspaceRaw,
            budgetChars: Int(Double(budgetChars) * Self.layerBudgetRatios[.workspace]!)
        )
        let agentLayer = applyBudget(
            name: .agent,
            content: agentRaw,
            budgetChars: Int(Double(budgetChars) * Self.layerBudgetRatios[.agent]!)
        )
        let personalLayer = applyBudget(
            name: .personal,
            content: personalRaw,
            budgetChars: Int(Double(budgetChars) * Self.layerBudgetRatios[.personal]!)
        )

        let layers = ContextLayers(
            systemLayer: systemLayer,
            workspaceLayer: workspaceLayer,
            agentLayer: agentLayer,
            personalLayer: personalLayer
        )

        // 3. Compute token estimate from actual content
        let totalChars = layers.totalCharCount
        let tokenEstimate = max(totalChars / 2, 1)

        // 4. Compute source revision hash
        let sourceRevision = computeRevision(layers: layers)

        let snapshotId = UUID().uuidString

        let snapshot = ContextSnapshot(
            id: snapshotId,
            workspaceId: workspaceId.uuidString,
            agentId: agentId,
            userId: userId ?? "",
            layers: layers,
            tokenEstimate: tokenEstimate,
            createdAt: Date(),
            sourceRevision: sourceRevision
        )

        Log.runtime.info("Context snapshot built: \(snapshotId), tokens≈\(tokenEstimate), layers=\(layers.ordered.filter { !$0.content.isEmpty }.count)")

        return snapshot
    }

    // MARK: - Validation

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
    ) -> [String] {
        var violations: [String] = []

        // Workspace boundary check
        if snapshot.workspaceId != expectedWorkspaceId {
            violations.append("Workspace boundary violation: snapshot workspace '\(snapshot.workspaceId)' != expected '\(expectedWorkspaceId)'")
        }

        // Personal memory boundary: only the matching user should have personal content
        if !snapshot.layers.personalLayer.content.isEmpty {
            if let expectedUser = expectedUserId, !expectedUser.isEmpty {
                if snapshot.userId != expectedUser {
                    violations.append("Personal memory boundary violation: snapshot user '\(snapshot.userId)' != requesting user '\(expectedUser)'")
                }
            } else {
                violations.append("Personal memory present but no user ID provided")
            }
        }

        return violations
    }

    // MARK: - Private

    /// Load and combine system layer content.
    private func loadSystemLayer(workspaceId: UUID, agentId: String, channelMetadata: String?) -> String {
        var parts: [String] = []

        // Global base instructions
        if let base = contextService.loadBaseSystemPrompt(), !base.isEmpty {
            parts.append(base)
        }

        // Agent persona (system.md)
        if let persona = contextService.loadAgentPersona(workspaceId: workspaceId, agentName: agentId), !persona.isEmpty {
            parts.append(persona)
        }

        // Channel/runtime metadata
        if let meta = channelMetadata, !meta.isEmpty {
            parts.append(meta)
        }

        return parts.joined(separator: "\n\n")
    }

    /// Apply character budget to a layer, truncating with a note if needed.
    private func applyBudget(name: ContextLayerName, content: String, budgetChars: Int) -> ContextLayer {
        let originalCount = content.count

        if originalCount <= budgetChars {
            return ContextLayer(name: name, content: content, truncated: false, originalCharCount: originalCount)
        }

        // Truncate and add note
        let truncatedContent = String(content.prefix(budgetChars))
        let note = "\n\n[... \(name.rawValue) 컨텍스트 축약됨: 원본 \(originalCount)자 중 \(budgetChars)자만 포함]"

        return ContextLayer(
            name: name,
            content: truncatedContent + note,
            truncated: true,
            originalCharCount: originalCount
        )
    }

    /// Compute a revision hash from all layer contents for cache invalidation.
    private func computeRevision(layers: ContextLayers) -> String {
        var hasher = SHA256()
        for layer in layers.ordered {
            hasher.update(data: Data(layer.content.utf8))
        }
        let digest = hasher.finalize()
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
