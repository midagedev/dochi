import Foundation

@MainActor
protocol MCPServiceProtocol {
    // Server management
    func addServer(config: MCPServerConfig)
    func removeServer(id: UUID)
    func connect(serverId: UUID) async throws
    func disconnect(serverId: UUID)
    func disconnectAll()

    // Query
    func listServers() -> [MCPServerConfig]
    func getServer(id: UUID) -> MCPServerConfig?

    // Tools
    func listTools() -> [MCPToolInfo]
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult
}
