import Foundation

/// Handler called before executing a sensitive tool. Receives (toolName, toolDescription).
/// Returns `true` to allow execution, `false` to deny.
typealias ToolConfirmationHandler = @MainActor (String, String) async -> Bool

@MainActor
protocol BuiltInToolServiceProtocol {
    /// Called before executing sensitive tools to get user confirmation.
    var confirmationHandler: ToolConfirmationHandler? { get set }

    /// Human-readable label for the capability selection that produced
    /// the most recently compiled tool schema list.
    var selectedCapabilityLabel: String? { get }

    /// Returns summaries of non-baseline tools (name, description, category) for system prompt.
    var nonBaselineToolSummaries: [(name: String, description: String, category: ToolCategory)] { get }

    /// Returns info about all registered tools for UI display.
    var allToolInfos: [ToolInfo] { get }

    func availableToolSchemas(for permissions: [String]) -> [[String: Any]]
    func availableToolSchemas(for permissions: [String], preferredToolGroups: [String]) -> [[String: Any]]
    func availableToolSchemas(for permissions: [String], preferredToolGroups: [String], intentHint: String?) -> [[String: Any]]
    func execute(name: String, arguments: [String: Any]) async -> ToolResult
    func enableTools(names: [String])
    func enableToolsTTL(minutes: Int)
    func resetRegistry()

    /// Look up tool info by name.
    func toolInfo(named: String) -> ToolInfo?
}

extension BuiltInToolServiceProtocol {
    var selectedCapabilityLabel: String? { nil }

    func availableToolSchemas(for permissions: [String], preferredToolGroups _: [String]) -> [[String: Any]] {
        availableToolSchemas(for: permissions)
    }

    func availableToolSchemas(for permissions: [String], preferredToolGroups: [String], intentHint _: String?) -> [[String: Any]] {
        availableToolSchemas(for: permissions, preferredToolGroups: preferredToolGroups)
    }

    func toolInfo(named name: String) -> ToolInfo? {
        allToolInfos.first { $0.name == name }
    }
}
