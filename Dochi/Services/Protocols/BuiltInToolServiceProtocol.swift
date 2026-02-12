import Foundation

@MainActor
protocol BuiltInToolServiceProtocol {
    func availableToolSchemas(for permissions: [String]) -> [[String: Any]]
    func execute(name: String, arguments: [String: Any]) async -> ToolResult
    func enableTools(names: [String])
    func enableToolsTTL(minutes: Int)
    func resetRegistry()
}
