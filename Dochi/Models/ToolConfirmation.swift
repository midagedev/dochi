import Foundation

/// Represents a pending sensitive tool confirmation request.
@MainActor
struct ToolConfirmation {
    let toolName: String
    let toolDescription: String
    let continuation: CheckedContinuation<Bool, Never>
}
