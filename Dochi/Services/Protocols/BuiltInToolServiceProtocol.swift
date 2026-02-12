import Foundation

@MainActor
protocol BuiltInToolServiceProtocol {
    func availableTools(for permissions: [String]) -> [[String: Any]]
    func execute(name: String, arguments: [String: Any]) async -> ToolResult
    func resetRegistry()
}
