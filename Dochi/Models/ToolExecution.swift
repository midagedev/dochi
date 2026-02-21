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

    /// Returns true when content represents an error-like tool result.
    static func isErrorResult(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix("오류:")
            || trimmed.localizedCaseInsensitiveContains("error")
            || trimmed.localizedCaseInsensitiveContains("실패")
    }

    /// Returns true when content looks like a tools.* negotiation/control result.
    static func isControlToolNegotiationResult(_ content: String) -> Bool {
        let lines = normalizedNonEmptyLines(from: content)
        guard !lines.isEmpty else { return false }

        return lines.contains(where: { $0.hasPrefix("도구 목록 (") })
            || lines.contains(where: { $0.hasPrefix("도구 활성화 완료:") })
            || lines.contains(where: { $0.hasPrefix("이미 활성화된 도구:") })
            || lines.contains(where: { $0.hasPrefix("찾을 수 없는 도구:") })
            || lines.contains(where: { $0.hasPrefix("활성화 가능한 도구가 없습니다.") })
            || lines.contains(where: { $0.hasPrefix("도구 TTL을 ") })
            || lines.contains(where: { $0.hasPrefix("도구 레지스트리를 기본 상태로 복원") })
            || lines.contains(where: { $0.localizedCaseInsensitiveContains("tools.enable") })
    }

    /// Compact one-line summary for chat bubbles (collapsed tool result view).
    static func generateCompactResultSummary(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "도구 실행 결과" }
        let lines = normalizedNonEmptyLines(from: trimmed)
        guard let first = lines.first else { return "도구 실행 결과" }

        if first.hasPrefix("도구 목록 (") {
            if let totalCount = extractLeadingCount(in: first, prefix: "도구 목록 (", suffix: "개)") {
                return "도구 목록 조회 (\(totalCount)개)"
            }
            return "도구 목록 조회 결과"
        }

        let newlyEnabledCount = countCommaSeparatedItems(in: lines, prefix: "도구 활성화 완료:")
        let alreadyEnabledCount = countCommaSeparatedItems(in: lines, prefix: "이미 활성화된 도구:")
        let invalidCount = countCommaSeparatedItems(in: lines, prefix: "찾을 수 없는 도구:")
        if newlyEnabledCount > 0 || alreadyEnabledCount > 0 || invalidCount > 0 {
            var parts: [String] = []
            if newlyEnabledCount > 0 { parts.append("신규 \(newlyEnabledCount)") }
            if alreadyEnabledCount > 0 { parts.append("이미 \(alreadyEnabledCount)") }
            if invalidCount > 0 { parts.append("미존재 \(invalidCount)") }
            return "도구 활성화 결과 · " + parts.joined(separator: ", ")
        }

        if lines.contains(where: { $0.hasPrefix("활성화 가능한 도구가 없습니다.") }) {
            return "도구 활성화 결과 · 활성화 대상 없음"
        }

        if first.hasPrefix("도구 TTL을 ") {
            return first
        }

        if first.hasPrefix("도구 레지스트리를 기본 상태로 복원") {
            return "도구 레지스트리 초기화 완료"
        }

        return generateResultSummary(from: trimmed, isError: isErrorResult(trimmed))
    }

    private static func normalizedNonEmptyLines(from content: String) -> [String] {
        content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func countCommaSeparatedItems(in lines: [String], prefix: String) -> Int {
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return 0 }
        let payload = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return 0 }
        return payload
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private static func extractLeadingCount(in line: String, prefix: String, suffix: String) -> Int? {
        guard let prefixRange = line.range(of: prefix) else { return nil }
        let remainder = line[prefixRange.upperBound...]
        guard let suffixRange = remainder.range(of: suffix) else { return nil }
        let numberSlice = remainder[..<suffixRange.lowerBound]
        return Int(numberSlice)
    }
}
