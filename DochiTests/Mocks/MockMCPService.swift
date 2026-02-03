import Foundation
@testable import Dochi

@MainActor
final class MockMCPService: MCPServiceProtocol {
    var tools: [MCPToolInfo] = []
    var servers: [UUID: String] = [:]
    var toolCallResults: [String: MCPToolResult] = [:]
    var toolCallHistory: [(name: String, arguments: [String: Any])] = []
    var shouldThrowOnConnect: Error?
    var shouldThrowOnCallTool: Error?

    var availableTools: [MCPToolInfo] {
        tools
    }

    var connectedServers: [UUID: String] {
        servers
    }

    func connect(config: MCPServerConfig) async throws {
        if let error = shouldThrowOnConnect {
            throw error
        }
        servers[config.id] = config.name
    }

    func disconnect(serverId: UUID) async {
        servers.removeValue(forKey: serverId)
    }

    func disconnectAll() async {
        servers.removeAll()
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        toolCallHistory.append((name: name, arguments: arguments))

        if let error = shouldThrowOnCallTool {
            throw error
        }

        if let result = toolCallResults[name] {
            return result
        }

        return MCPToolResult(content: "Mock result for \(name)", isError: false)
    }

    // MARK: - Test Helpers

    func addTool(name: String, description: String? = nil, inputSchema: [String: Any]? = nil) {
        let tool = MCPToolInfo(
            id: UUID().uuidString,
            name: name,
            description: description,
            inputSchema: inputSchema
        )
        tools.append(tool)
    }

    func setToolResult(_ name: String, content: String, isError: Bool = false) {
        toolCallResults[name] = MCPToolResult(content: content, isError: isError)
    }

    func reset() {
        tools.removeAll()
        servers.removeAll()
        toolCallResults.removeAll()
        toolCallHistory.removeAll()
        shouldThrowOnConnect = nil
        shouldThrowOnCallTool = nil
    }
}
