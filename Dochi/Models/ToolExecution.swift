import Foundation

/// Represents a live tool execution during the current turn.
/// Tracks status, timing, and results for UI display.
@MainActor
@Observable
final class ToolExecution: Identifiable, Sendable {
    let id: UUID
    let toolName: String
    let toolCallId: String
    let displayName: String
    let category: ToolCategory
    let inputSummary: String
    private(set) var status: ToolExecutionStatus
    let startedAt: Date
    private(set) var completedAt: Date?
    private(set) var resultSummary: String?
    private(set) var resultFull: String?
    let loopIndex: Int

    init(
        id: UUID = UUID(),
        toolName: String,
        toolCallId: String,
        displayName: String,
        category: ToolCategory = .safe,
        inputSummary: String,
        loopIndex: Int
    ) {
        self.id = id
        self.toolName = toolName
        self.toolCallId = toolCallId
        self.displayName = displayName
        self.category = category
        self.inputSummary = inputSummary
        self.status = .running
        self.startedAt = Date()
        self.loopIndex = loopIndex
    }

    /// Mark this execution as successfully completed.
    func complete(resultSummary: String, resultFull: String) {
        self.status = .success
        self.completedAt = Date()
        self.resultSummary = resultSummary
        self.resultFull = resultFull
    }

    /// Mark this execution as failed.
    func fail(errorSummary: String, errorFull: String) {
        self.status = .error
        self.completedAt = Date()
        self.resultSummary = errorSummary
        self.resultFull = errorFull
    }

    /// Duration in seconds (nil if still running).
    var durationSeconds: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    /// Convert to a Codable archive record for persisting in Message.
    func toRecord() -> ToolExecutionRecord {
        ToolExecutionRecord(
            toolName: toolName,
            displayName: displayName,
            inputSummary: inputSummary,
            isError: status == .error,
            durationSeconds: durationSeconds,
            resultSummary: resultSummary
        )
    }
}

// MARK: - Status

enum ToolExecutionStatus: String, Sendable {
    case running
    case success
    case error
}

// MARK: - ToolExecutionRecord (Codable archive)

/// Lightweight, Codable summary of a tool execution for persistence in Message.
struct ToolExecutionRecord: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(toolName)-\(inputSummary.prefix(20))" }
    let toolName: String
    let displayName: String
    let inputSummary: String
    let isError: Bool
    let durationSeconds: TimeInterval?
    let resultSummary: String?
}

// MARK: - Input Summary Generation

enum ToolExecutionSummary {
    /// Sensitive key patterns that should be masked in summaries.
    private static let sensitiveKeys: Set<String> = [
        "api_key", "apiKey", "password", "secret", "token", "credential", "auth"
    ]

    /// Generate a human-readable input summary from tool arguments.
    /// Extracts key-value pairs, masks sensitive values, and truncates to 80 chars.
    static func generateInputSummary(from arguments: [String: Any]) -> String {
        guard !arguments.isEmpty else { return "" }

        let parts: [String] = arguments.compactMap { key, value in
            let displayValue: String
            if sensitiveKeys.contains(key.lowercased()) || sensitiveKeys.contains(where: { key.lowercased().contains($0) }) {
                displayValue = "****"
            } else if let str = value as? String {
                displayValue = String(str.prefix(30))
            } else if let num = value as? NSNumber {
                displayValue = num.stringValue
            } else if let arr = value as? [Any] {
                displayValue = "[\(arr.count)items]"
            } else if let dict = value as? [String: Any] {
                displayValue = "{\(dict.count)keys}"
            } else {
                displayValue = String(describing: value).prefix(20).description
            }
            return "\(key)=\(displayValue)"
        }

        let joined = parts.joined(separator: ", ")
        if joined.count > 80 {
            return String(joined.prefix(77)) + "..."
        }
        return joined
    }

    /// Generate a result summary from a tool result content string.
    /// Truncates to a readable length.
    static func generateResultSummary(from content: String, isError: Bool) -> String {
        let prefix = isError ? "Error: " : ""
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= 100 {
            return prefix + clean
        }
        return prefix + String(clean.prefix(97)) + "..."
    }
}
