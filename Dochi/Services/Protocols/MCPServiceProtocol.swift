import Foundation

@MainActor
protocol MCPServiceProtocol {
    // Server management
    func addServer(config: MCPServerConfig)
    func removeServer(id: UUID)
    func connect(serverId: UUID) async throws
    func disconnect(serverId: UUID)
    func disconnectAll()

    /// Atomically replaces a server config (disconnect old -> remove -> add new -> reconnect if enabled).
    func updateServer(config: MCPServerConfig) async throws

    // Query
    func listServers() -> [MCPServerConfig]
    func getServer(id: UUID) -> MCPServerConfig?

    // Tools
    func listTools() -> [MCPToolInfo]
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult

    // Profile lifecycle
    func activateProfile(_ profile: MCPServerProfile) async
    func deactivateProfile(_ profile: MCPServerProfile)

    // Health monitoring
    func serverStatus(for serverId: UUID) -> MCPServerStatus
    func healthReport(for profile: MCPServerProfile) -> MCPProfileHealthReport

    // Fallback
    func fallbackMessage(for toolName: String) -> String
}
