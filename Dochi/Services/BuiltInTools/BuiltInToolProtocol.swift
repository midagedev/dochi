import Foundation

/// 내장 도구 모듈 프로토콜
@MainActor
protocol BuiltInTool {
    /// 이 모듈이 제공하는 도구 목록
    nonisolated var tools: [MCPToolInfo] { get }

    /// 도구 실행
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult
}
