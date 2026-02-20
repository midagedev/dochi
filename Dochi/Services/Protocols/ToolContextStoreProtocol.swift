import Foundation

@MainActor
protocol ToolContextStoreProtocol: Sendable {
    func record(_ event: ToolUsageEvent) async
    func profile(workspaceId: String, agentName: String) async -> ToolContextProfile?
    func userPreference(workspaceId: String) async -> UserToolPreference
    func updateUserPreference(_ preference: UserToolPreference, workspaceId: String) async
    func flushToDisk() async
}
