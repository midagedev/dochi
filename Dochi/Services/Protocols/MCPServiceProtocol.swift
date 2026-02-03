import Foundation

/// MCP 서버에서 가져온 도구 정보
struct MCPToolInfo: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let description: String?
    let inputSchema: [String: Any]?

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "type": "function",
            "function": [
                "name": name
            ] as [String: Any]
        ]
        var funcDict = dict["function"] as! [String: Any]
        if let desc = description {
            funcDict["description"] = desc
        }
        if let schema = inputSchema {
            funcDict["parameters"] = schema
        }
        dict["function"] = funcDict
        return dict
    }
}

/// MCP 도구 실행 결과
struct MCPToolResult: Sendable {
    let content: String
    let isError: Bool
}

/// MCP 서버 설정
struct MCPServerConfig: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var command: String
    var arguments: [String]
    var environment: [String: String]?
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, command: String, arguments: [String] = [], environment: [String: String]? = nil, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.isEnabled = isEnabled
    }
}

/// MCP 서비스 프로토콜
protocol MCPServiceProtocol: AnyObject, Sendable {
    /// 사용 가능한 모든 도구 목록
    var availableTools: [MCPToolInfo] { get async }

    /// 서버에 연결
    func connect(config: MCPServerConfig) async throws

    /// 서버 연결 해제
    func disconnect(serverId: UUID) async

    /// 모든 서버 연결 해제
    func disconnectAll() async

    /// 도구 실행
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult
}
