import Foundation

@MainActor
protocol BuiltInToolProtocol {
    var name: String { get }
    var category: ToolCategory { get }
    var description: String { get }
    var inputSchema: [String: Any] { get }
    var isBaseline: Bool { get }
    func execute(arguments: [String: Any]) async -> ToolResult
}

enum ToolCategory: String, Sendable {
    case safe
    case sensitive
    case restricted
}
