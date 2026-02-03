import Foundation
import MCP

/// MCP 서비스 - 여러 MCP 서버 관리 및 도구 실행
/// 현재는 HTTP 기반 MCP 서버만 지원
@MainActor
final class MCPService: ObservableObject {
    @Published private(set) var connectedServers: [UUID: String] = [:]
    @Published private(set) var error: String?

    private var connections: [UUID: MCPConnection] = [:]

    var availableTools: [MCPToolInfo] {
        connections.values.flatMap { $0.tools }
    }

    func connect(config: MCPServerConfig) async throws {
        guard config.isEnabled else { return }

        // 이미 연결된 경우 스킵
        if connections[config.id] != nil {
            return
        }

        let client = Client(name: "Dochi", version: "1.0.0")

        // HTTP 기반 서버만 지원 (command가 URL인 경우)
        guard let url = URL(string: config.command),
              url.scheme == "http" || url.scheme == "https" else {
            throw MCPServiceError.unsupportedTransport("Only HTTP-based MCP servers are currently supported")
        }

        let transport = HTTPClientTransport(endpoint: url)

        do {
            let result = try await client.connect(transport: transport)
            print("[MCP] Connected to \(config.name)")

            // 도구 목록 가져오기
            var tools: [MCPToolInfo] = []
            if result.capabilities.tools != nil {
                let (toolList, _) = try await client.listTools()
                tools = toolList.map { tool in
                    MCPToolInfo(
                        id: "\(config.id):\(tool.name)",
                        name: tool.name,
                        description: tool.description,
                        inputSchema: convertValueToDict(tool.inputSchema)
                    )
                }
                print("[MCP] Available tools from \(config.name): \(tools.map { $0.name })")
            }

            let connection = MCPConnection(
                config: config,
                client: client,
                tools: tools
            )

            connections[config.id] = connection
            connectedServers[config.id] = config.name
            error = nil
        } catch {
            self.error = "Failed to connect to \(config.name): \(error.localizedDescription)"
            throw error
        }
    }

    func disconnect(serverId: UUID) async {
        guard let connection = connections[serverId] else { return }

        await connection.client.disconnect()
        connections.removeValue(forKey: serverId)
        connectedServers.removeValue(forKey: serverId)
        print("[MCP] Disconnected from \(connection.config.name)")
    }

    func disconnectAll() async {
        for serverId in connections.keys {
            await disconnect(serverId: serverId)
        }
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        // 도구를 가진 연결 찾기
        guard let connection = connections.values.first(where: { conn in
            conn.tools.contains { $0.name == name }
        }) else {
            throw MCPServiceError.toolNotFound(name)
        }

        // arguments를 MCP.Value로 변환
        let mcpArguments = try convertToMCPValue(arguments)

        let (content, isError) = try await connection.client.callTool(
            name: name,
            arguments: mcpArguments
        )

        // content를 문자열로 변환
        let resultText = content.map { block -> String in
            switch block {
            case .text(let text):
                return text
            case .image(let data, let mimeType, _):
                return "[Image: \(mimeType), \(data.count) bytes]"
            case .audio(let data, let mimeType):
                return "[Audio: \(mimeType), \(data.count) bytes]"
            case .resource(let uri, let mimeType, let text):
                return text ?? "[Resource: \(uri), \(mimeType ?? "unknown")]"
            }
        }.joined(separator: "\n")

        return MCPToolResult(content: resultText, isError: isError ?? false)
    }

    // MARK: - Helpers

    private func convertValueToDict(_ value: Value) -> [String: Any]? {
        guard case .object(let dict) = value else { return nil }
        var result: [String: Any] = [:]
        for (key, val) in dict {
            result[key] = convertValueToAny(val)
        }
        return result
    }

    private func convertValueToAny(_ value: Value) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .int(let i):
            return i
        case .double(let d):
            return d
        case .string(let s):
            return s
        case .data(_, let data):
            return data
        case .array(let arr):
            return arr.map { convertValueToAny($0) }
        case .object(let obj):
            var dict: [String: Any] = [:]
            for (k, v) in obj {
                dict[k] = convertValueToAny(v)
            }
            return dict
        }
    }

    private func convertToMCPValue(_ dict: [String: Any]) throws -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, value) in dict {
            result[key] = try toValue(value)
        }
        return result
    }

    private func toValue(_ value: Any) throws -> Value {
        switch value {
        case is NSNull:
            return .null
        case let b as Bool:
            return .bool(b)
        case let n as Int:
            return .int(n)
        case let n as Double:
            return .double(n)
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(try arr.map { try toValue($0) })
        case let dict as [String: Any]:
            var obj: [String: Value] = [:]
            for (k, v) in dict {
                obj[k] = try toValue(v)
            }
            return .object(obj)
        default:
            throw MCPServiceError.invalidArgument("Cannot convert \(type(of: value)) to Value")
        }
    }
}

// MARK: - Supporting Types

private struct MCPConnection: Sendable {
    let config: MCPServerConfig
    let client: Client
    let tools: [MCPToolInfo]
}

// MARK: - Errors

enum MCPServiceError: LocalizedError {
    case toolNotFound(String)
    case invalidArgument(String)
    case unsupportedTransport(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool '\(name)' not found in any connected MCP server"
        case .invalidArgument(let message):
            return "Invalid argument: \(message)"
        case .unsupportedTransport(let message):
            return message
        }
    }
}
