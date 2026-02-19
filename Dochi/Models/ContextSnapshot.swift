import Foundation

// MARK: - ContextSnapshot

/// A point-in-time capture of all context layers for a session run.
///
/// The 4-layer context model (spec §05):
/// 1. System layer: global base instructions + agent persona
/// 2. Workspace layer: shared workspace memory (hot facts + summary)
/// 3. Agent layer: agent-specific memory
/// 4. Personal layer: per-user private memory
struct ContextSnapshot: Codable, Sendable, Identifiable {
    let id: String
    let workspaceId: String
    let agentId: String
    let userId: String
    let layers: ContextLayers
    let tokenEstimate: Int
    let createdAt: Date
    /// Revision hash of source files at snapshot time (for invalidation).
    let sourceRevision: String

    /// The string reference passed to the runtime for lazy loading.
    var snapshotRef: String { id }
}

// MARK: - ContextLayers

/// The 4 context layers assembled in injection order.
struct ContextLayers: Codable, Sendable {
    /// Layer 1: Global base system prompt + agent persona/system.md
    let systemLayer: ContextLayer
    /// Layer 2: Workspace memory summary + hot facts
    let workspaceLayer: ContextLayer
    /// Layer 3: Agent memory summary + hot facts
    let agentLayer: ContextLayer
    /// Layer 4: Personal user memory (only for matching userId)
    let personalLayer: ContextLayer

    /// All layers in injection order.
    var ordered: [ContextLayer] {
        [systemLayer, workspaceLayer, agentLayer, personalLayer]
    }

    /// Combined text of all layers.
    var combinedText: String {
        ordered
            .filter { !$0.content.isEmpty }
            .map(\.content)
            .joined(separator: "\n\n")
    }

    /// Total character count across all layers.
    var totalCharCount: Int {
        ordered.reduce(0) { $0 + $1.content.count }
    }
}

// MARK: - ContextLayer

/// A single context layer with metadata.
struct ContextLayer: Codable, Sendable {
    let name: ContextLayerName
    let content: String
    /// Whether content was truncated due to token budget.
    let truncated: Bool
    /// Original character count before any truncation.
    let originalCharCount: Int

    init(name: ContextLayerName, content: String, truncated: Bool = false, originalCharCount: Int? = nil) {
        self.name = name
        self.content = content
        self.truncated = truncated
        self.originalCharCount = originalCharCount ?? content.count
    }
}

// MARK: - ContextLayerName

/// Names for the 4 context layers.
enum ContextLayerName: String, Codable, Sendable {
    case system
    case workspace
    case agent
    case personal
}

// MARK: - ContextSnapshotMetadata

/// Lightweight metadata for a snapshot, used for listing/display without full content.
struct ContextSnapshotMetadata: Codable, Sendable {
    let snapshotRef: String
    let workspaceId: String
    let agentId: String
    let userId: String
    let tokenEstimate: Int
    let layerSummary: [String: Int]  // layerName → charCount
    let createdAt: Date
}
