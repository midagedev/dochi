import Foundation

@MainActor
protocol ToolContextStoreProtocol: Sendable {
    func record(_ event: ToolUsageEvent) async
    func profile(workspaceId: String, agentName: String) async -> ToolContextProfile?
    func userPreference(workspaceId: String) async -> UserToolPreference
    func rankingContext(workspaceId: String, agentName: String) -> ToolRankingContext
    func updateUserPreference(_ preference: UserToolPreference, workspaceId: String) async
    func flushToDisk() async
}

extension ToolContextStoreProtocol {
    func rankingContext(workspaceId _: String, agentName _: String) -> ToolRankingContext {
        .empty
    }
}
