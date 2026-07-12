import Foundation

/// Risk tier of a tool, used to label tool runs surfaced from Hermes.
enum ToolCategory: String, Sendable {
    case safe
    case sensitive
    case restricted
}
