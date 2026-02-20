import Foundation

/// Represents a pending sensitive tool confirmation request (local tool path).
@MainActor
struct ToolConfirmation {
    let toolName: String
    let toolDescription: String
    let continuation: CheckedContinuation<Bool, Never>
}
