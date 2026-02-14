import Foundation

struct ShellPermissionConfig: Codable, Sendable, Equatable {
    /// Commands/patterns that are always blocked (e.g., "rm -rf /", "sudo")
    var blockedCommands: [String]

    /// Commands/patterns that require user confirmation (e.g., "rm", "mv", "kill")
    var confirmCommands: [String]

    /// Commands/patterns that are always allowed without confirmation (e.g., "ls", "cat", "git status")
    var allowedCommands: [String]

    static var `default`: ShellPermissionConfig {
        ShellPermissionConfig(
            blockedCommands: [
                "rm -rf /",
                "rm -rf /*",
                "sudo ",
                "shutdown",
                "reboot",
                "mkfs",
                "dd if=",
                ":(){:|:&};:",
                "chmod -R 777 /",
                "mv /* ",
                "> /dev/sda",
            ],
            confirmCommands: [
                "rm ",
                "mv ",
                "kill ",
                "killall ",
                "pkill ",
                "chmod ",
                "chown ",
            ],
            allowedCommands: [
                "ls",
                "cat ",
                "head ",
                "tail ",
                "echo ",
                "pwd",
                "whoami",
                "date",
                "cal",
                "df ",
                "du ",
                "wc ",
                "grep ",
                "find ",
                "which ",
                "git status",
                "git log",
                "git diff",
                "git branch",
            ]
        )
    }

    /// Check if a command matches any pattern in a list.
    /// Matching is case-insensitive and uses prefix/contains matching.
    func matchResult(for command: String) -> ShellPermissionResult {
        let lowered = command.lowercased()

        for pattern in blockedCommands {
            if lowered.contains(pattern.lowercased()) {
                return .blocked(pattern: pattern)
            }
        }

        for pattern in confirmCommands {
            if lowered.hasPrefix(pattern.lowercased()) || lowered.contains(pattern.lowercased()) {
                return .confirm(pattern: pattern)
            }
        }

        for pattern in allowedCommands {
            if lowered.hasPrefix(pattern.lowercased()) || lowered.contains(pattern.lowercased()) {
                return .allowed
            }
        }

        return .defaultCategory
    }
}

enum ShellPermissionResult: Equatable {
    /// Command matched a blocked pattern — reject immediately
    case blocked(pattern: String)
    /// Command matched a confirm pattern — requires user confirmation
    case confirm(pattern: String)
    /// Command matched an allowed pattern — execute without confirmation
    case allowed
    /// No pattern matched — fall through to default restricted category behavior
    case defaultCategory
}
