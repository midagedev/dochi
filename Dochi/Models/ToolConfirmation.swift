import Foundation

/// Represents a pending sensitive tool confirmation request (local tool path).
@MainActor
struct ToolConfirmation {
    let toolName: String
    let toolDescription: String
    let continuation: CheckedContinuation<Bool, Never>
}

/// Represents a pending SDK tool approval request with scope selection.
/// Used for the runtime bridge path where tools require approval.required flow.
@MainActor
struct SDKToolApproval {
    let params: ApprovalRequestParams
    let continuation: CheckedContinuation<(approved: Bool, scope: ApprovalScope), Never>
}
