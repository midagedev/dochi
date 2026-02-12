import Foundation

/// Handler called before executing a sensitive tool. Receives (toolName, toolDescription).
/// Returns `true` to allow execution, `false` to deny.
typealias ToolConfirmationHandler = @MainActor (String, String) async -> Bool

@MainActor
protocol BuiltInToolServiceProtocol {
    /// Called before executing sensitive tools to get user confirmation.
    var confirmationHandler: ToolConfirmationHandler? { get set }

    func availableToolSchemas(for permissions: [String]) -> [[String: Any]]
    func execute(name: String, arguments: [String: Any]) async -> ToolResult
    func enableTools(names: [String])
    func enableToolsTTL(minutes: Int)
    func resetRegistry()
}
