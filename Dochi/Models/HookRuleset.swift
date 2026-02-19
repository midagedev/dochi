import Foundation

/// Declarative ruleset for hook policies.
/// Loaded from a JSON file or uses built-in defaults.
struct HookRuleset: Codable, Sendable {
    let version: String
    let forbiddenPatterns: [ForbiddenPattern]
    let piiPatterns: [PIIPattern]

    static var `default`: HookRuleset {
        HookRuleset(
            version: "1.0",
            forbiddenPatterns: ForbiddenPattern.defaults,
            piiPatterns: PIIPattern.defaults
        )
    }
}

/// A pattern that blocks tool execution when matched.
struct ForbiddenPattern: Codable, Sendable {
    /// Pattern to match against (case-insensitive contains).
    let pattern: String
    /// Which tool names this applies to (empty = all tools).
    let tools: [String]
    /// Why this pattern is forbidden.
    let reason: String

    static var defaults: [ForbiddenPattern] {
        [
            ForbiddenPattern(
                pattern: "rm -rf /",
                tools: ["shell.execute", "terminal.run"],
                reason: "루트 디렉토리 삭제 명령 차단"
            ),
            ForbiddenPattern(
                pattern: "rm -rf /*",
                tools: ["shell.execute", "terminal.run"],
                reason: "루트 디렉토리 삭제 명령 차단"
            ),
            ForbiddenPattern(
                pattern: "sudo ",
                tools: ["shell.execute", "terminal.run"],
                reason: "관리자 권한 명령 차단"
            ),
            ForbiddenPattern(
                pattern: "mkfs",
                tools: ["shell.execute", "terminal.run"],
                reason: "파일시스템 포맷 명령 차단"
            ),
            ForbiddenPattern(
                pattern: "> /dev/sda",
                tools: ["shell.execute", "terminal.run"],
                reason: "디스크 직접 쓰기 차단"
            ),
            ForbiddenPattern(
                pattern: ":(){ :|:&};:",
                tools: ["shell.execute", "terminal.run"],
                reason: "포크 폭탄 차단"
            ),
            ForbiddenPattern(
                pattern: "chmod -R 777 /",
                tools: ["shell.execute", "terminal.run"],
                reason: "광범위 권한 변경 차단"
            ),
            ForbiddenPattern(
                pattern: "shutdown",
                tools: ["shell.execute", "terminal.run"],
                reason: "시스템 종료 명령 차단"
            ),
            ForbiddenPattern(
                pattern: "reboot",
                tools: ["shell.execute", "terminal.run"],
                reason: "시스템 재시작 명령 차단"
            ),
        ]
    }
}

/// A PII pattern for argument masking.
struct PIIPattern: Codable, Sendable {
    /// Human-readable name of the PII type.
    let name: String
    /// Regex pattern to detect PII.
    let regex: String
    /// Replacement string (e.g., "[EMAIL]", "[PHONE]").
    let replacement: String

    static var defaults: [PIIPattern] {
        [
            PIIPattern(
                name: "email",
                regex: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
                replacement: "[EMAIL]"
            ),
            PIIPattern(
                name: "phone_kr",
                regex: "01[0-9]-?\\d{3,4}-?\\d{4}",
                replacement: "[PHONE]"
            ),
            PIIPattern(
                name: "resident_id",
                regex: "\\d{6}-?[1-4]\\d{6}",
                replacement: "[주민번호]"
            ),
            PIIPattern(
                name: "credit_card",
                regex: "\\d{4}[- ]?\\d{4}[- ]?\\d{4}[- ]?\\d{4}",
                replacement: "[카드번호]"
            ),
            PIIPattern(
                name: "api_key",
                regex: "sk-[a-zA-Z0-9]{20,}",
                replacement: "[API_KEY]"
            ),
        ]
    }
}
