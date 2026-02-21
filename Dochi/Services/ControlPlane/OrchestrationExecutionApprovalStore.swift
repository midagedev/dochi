import Foundation

enum OrchestrationExecutionApprovalFailureCode: String, Sendable {
    case approvalNotFound = "approval_not_found"
    case approvalExpired = "approval_expired"
    case approvalCodeMismatch = "approval_code_mismatch"
    case approvalLocked = "approval_locked"
    case approvalNotApproved = "approval_not_approved"
    case approvalAlreadyConsumed = "approval_already_consumed"
    case approvalContextMismatch = "approval_context_mismatch"
}

struct OrchestrationExecutionApprovalSnapshot: Sendable {
    enum Status: String, Sendable {
        case pending
        case approved
        case locked
        case expired
        case consumed
    }

    let approvalId: String
    let challengeCode: String
    let command: String
    let repositoryRoot: String?
    let status: Status
    let createdAt: Date
    let expiresAt: Date
    let approvedAt: Date?
    let consumedAt: Date?
    let failedAttemptCount: Int
    let maxAttemptCount: Int
    let lockedUntil: Date?
}

struct OrchestrationExecutionApprovalChallenge: Sendable {
    let snapshot: OrchestrationExecutionApprovalSnapshot
}

struct OrchestrationExecutionApprovalValidation: Sendable {
    let isAllowed: Bool
    let failureCode: OrchestrationExecutionApprovalFailureCode?
    let message: String
    let snapshot: OrchestrationExecutionApprovalSnapshot?

    static func allowed(
        message: String,
        snapshot: OrchestrationExecutionApprovalSnapshot?
    ) -> OrchestrationExecutionApprovalValidation {
        OrchestrationExecutionApprovalValidation(
            isAllowed: true,
            failureCode: nil,
            message: message,
            snapshot: snapshot
        )
    }

    static func denied(
        code: OrchestrationExecutionApprovalFailureCode,
        message: String,
        snapshot: OrchestrationExecutionApprovalSnapshot?
    ) -> OrchestrationExecutionApprovalValidation {
        OrchestrationExecutionApprovalValidation(
            isAllowed: false,
            failureCode: code,
            message: message,
            snapshot: snapshot
        )
    }
}

actor OrchestrationExecutionApprovalStore {
    private struct Entry: Sendable {
        enum Status: Sendable {
            case pending
            case approved
            case locked
            case expired
            case consumed
        }

        let approvalId: String
        let challengeCode: String
        let command: String
        let repositoryRoot: String?
        var status: Status
        let createdAt: Date
        let expiresAt: Date
        var approvedAt: Date?
        var consumedAt: Date?
        var failedAttemptCount: Int
        var lockedUntil: Date?
    }

    private let defaultTTLSeconds: Int
    private let minTTLSeconds: Int
    private let maxTTLSeconds: Int
    private let maxApproveAttempts: Int
    private let lockoutSeconds: Int
    private var entries: [String: Entry] = [:]

    init(
        defaultTTLSeconds: Int = 120,
        minTTLSeconds: Int = 30,
        maxTTLSeconds: Int = 900,
        maxApproveAttempts: Int = 5,
        lockoutSeconds: Int = 120
    ) {
        self.defaultTTLSeconds = max(1, defaultTTLSeconds)
        self.minTTLSeconds = max(1, minTTLSeconds)
        self.maxTTLSeconds = max(self.minTTLSeconds, maxTTLSeconds)
        self.maxApproveAttempts = max(1, maxApproveAttempts)
        self.lockoutSeconds = max(1, lockoutSeconds)
    }

    func create(
        command: String,
        repositoryRoot: String?,
        ttlSeconds: Int?,
        now: Date = Date()
    ) -> OrchestrationExecutionApprovalChallenge {
        pruneExpired(now: now)
        pruneTerminalEntries(now: now)

        let effectiveTTL = clampTTL(ttlSeconds)
        let approvalId = UUID().uuidString
        let challengeCode = Self.makeChallengeCode()
        let normalizedCommand = normalizeCommand(command)
        let normalizedRoot = normalizeRepositoryRoot(repositoryRoot)

        let entry = Entry(
            approvalId: approvalId,
            challengeCode: challengeCode,
            command: normalizedCommand,
            repositoryRoot: normalizedRoot,
            status: .pending,
            createdAt: now,
            expiresAt: now.addingTimeInterval(TimeInterval(effectiveTTL)),
            approvedAt: nil,
            consumedAt: nil,
            failedAttemptCount: 0,
            lockedUntil: nil
        )
        entries[approvalId] = entry

        return OrchestrationExecutionApprovalChallenge(snapshot: snapshot(from: entry))
    }

    func approve(
        approvalId: String,
        challengeCode: String,
        now: Date = Date()
    ) -> OrchestrationExecutionApprovalValidation {
        mutateAndResolve(
            approvalId: approvalId,
            now: now,
            expectedCommand: nil,
            expectedRepositoryRoot: nil,
            challengeCode: challengeCode,
            consume: false
        )
    }

    func consumeExecution(
        approvalId: String,
        command: String,
        repositoryRoot: String?,
        now: Date = Date()
    ) -> OrchestrationExecutionApprovalValidation {
        mutateAndResolve(
            approvalId: approvalId,
            now: now,
            expectedCommand: command,
            expectedRepositoryRoot: repositoryRoot,
            challengeCode: nil,
            consume: true
        )
    }

    func snapshot(
        approvalId: String,
        now: Date = Date()
    ) -> OrchestrationExecutionApprovalSnapshot? {
        pruneExpired(now: now)
        guard let entry = entries[approvalId] else { return nil }
        return snapshot(from: entry)
    }

    private func mutateAndResolve(
        approvalId rawApprovalId: String,
        now: Date,
        expectedCommand: String?,
        expectedRepositoryRoot: String?,
        challengeCode: String?,
        consume: Bool
    ) -> OrchestrationExecutionApprovalValidation {
        pruneExpired(now: now)

        let approvalId = rawApprovalId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !approvalId.isEmpty, var entry = entries[approvalId] else {
            return .denied(
                code: .approvalNotFound,
                message: "승인 요청을 찾을 수 없습니다.",
                snapshot: nil
            )
        }

        if entry.expiresAt <= now, entry.status == .pending || entry.status == .approved || entry.status == .locked {
            entry.status = .expired
            entry.lockedUntil = nil
            entries[approvalId] = entry
        }

        if entry.status == .locked,
           let lockedUntil = entry.lockedUntil,
           lockedUntil <= now {
            entry.status = .pending
            entry.failedAttemptCount = 0
            entry.lockedUntil = nil
            entries[approvalId] = entry
        }

        switch entry.status {
        case .locked:
            return .denied(
                code: .approvalLocked,
                message: lockoutMessage(from: entry, now: now),
                snapshot: snapshot(from: entry)
            )
        case .expired:
            return .denied(
                code: .approvalExpired,
                message: "승인 요청이 만료되었습니다.",
                snapshot: snapshot(from: entry)
            )
        case .consumed:
            return .denied(
                code: .approvalAlreadyConsumed,
                message: "이미 사용된 승인 요청입니다.",
                snapshot: snapshot(from: entry)
            )
        case .pending:
            break
        case .approved:
            break
        }

        if let challengeCode {
            let normalizedCode = challengeCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedCode == entry.challengeCode else {
                entry.failedAttemptCount += 1
                if entry.failedAttemptCount >= maxApproveAttempts {
                    entry.status = .locked
                    entry.lockedUntil = min(
                        entry.expiresAt,
                        now.addingTimeInterval(TimeInterval(lockoutSeconds))
                    )
                    entries[approvalId] = entry
                    return .denied(
                        code: .approvalLocked,
                        message: lockoutMessage(from: entry, now: now),
                        snapshot: snapshot(from: entry)
                    )
                }
                entries[approvalId] = entry
                return .denied(
                    code: .approvalCodeMismatch,
                    message: "승인 코드가 일치하지 않습니다. 남은 시도 횟수: \(maxApproveAttempts - entry.failedAttemptCount)",
                    snapshot: snapshot(from: entry)
                )
            }
            entry.status = .approved
            entry.approvedAt = now
            entry.failedAttemptCount = 0
            entry.lockedUntil = nil
            entries[approvalId] = entry
            return .allowed(
                message: "승인되었습니다.",
                snapshot: snapshot(from: entry)
            )
        }

        if let expectedCommand {
            let normalizedCommand = normalizeCommand(expectedCommand)
            let normalizedRoot = normalizeRepositoryRoot(expectedRepositoryRoot)
            guard normalizedCommand == entry.command, normalizedRoot == entry.repositoryRoot else {
                return .denied(
                    code: .approvalContextMismatch,
                    message: "승인 요청의 실행 컨텍스트가 다릅니다.",
                    snapshot: snapshot(from: entry)
                )
            }
        }

        guard entry.status == .approved else {
            return .denied(
                code: .approvalNotApproved,
                message: "아직 승인되지 않은 요청입니다.",
                snapshot: snapshot(from: entry)
            )
        }

        if consume {
            entry.status = .consumed
            entry.consumedAt = now
            entries[approvalId] = entry
            return .allowed(
                message: "승인 요청이 사용되었습니다.",
                snapshot: snapshot(from: entry)
            )
        }

        return .allowed(
            message: "승인 상태입니다.",
            snapshot: snapshot(from: entry)
        )
    }

    private func pruneExpired(now: Date) {
        guard !entries.isEmpty else { return }
        var updated = entries
        for key in updated.keys {
            guard var entry = updated[key] else { continue }
            if (entry.status == .pending || entry.status == .approved || entry.status == .locked),
               entry.expiresAt <= now {
                entry.status = .expired
                entry.lockedUntil = nil
                updated[key] = entry
            }
        }
        entries = updated
    }

    private func pruneTerminalEntries(now: Date) {
        let retentionSeconds: TimeInterval = 86_400
        entries = entries.filter { _, entry in
            let terminalAt: Date
            switch entry.status {
            case .pending, .approved, .locked:
                return true
            case .expired:
                terminalAt = entry.expiresAt
            case .consumed:
                terminalAt = entry.consumedAt ?? entry.expiresAt
            }
            return now.timeIntervalSince(terminalAt) < retentionSeconds
        }
    }

    private func clampTTL(_ ttlSeconds: Int?) -> Int {
        guard let ttlSeconds else { return defaultTTLSeconds }
        return min(max(ttlSeconds, minTTLSeconds), maxTTLSeconds)
    }

    private func snapshot(from entry: Entry) -> OrchestrationExecutionApprovalSnapshot {
        let status: OrchestrationExecutionApprovalSnapshot.Status
        switch entry.status {
        case .pending:
            status = .pending
        case .approved:
            status = .approved
        case .locked:
            status = .locked
        case .expired:
            status = .expired
        case .consumed:
            status = .consumed
        }

        return OrchestrationExecutionApprovalSnapshot(
            approvalId: entry.approvalId,
            challengeCode: entry.challengeCode,
            command: entry.command,
            repositoryRoot: entry.repositoryRoot,
            status: status,
            createdAt: entry.createdAt,
            expiresAt: entry.expiresAt,
            approvedAt: entry.approvedAt,
            consumedAt: entry.consumedAt,
            failedAttemptCount: entry.failedAttemptCount,
            maxAttemptCount: maxApproveAttempts,
            lockedUntil: entry.lockedUntil
        )
    }

    private func normalizeCommand(_ command: String) -> String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeRepositoryRoot(_ repositoryRoot: String?) -> String? {
        guard let repositoryRoot else { return nil }
        let trimmed = repositoryRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func makeChallengeCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private func lockoutMessage(from entry: Entry, now _: Date) -> String {
        if let lockedUntil = entry.lockedUntil {
            return "승인 코드 입력 시도 횟수를 초과했습니다. \(isoTimestamp(lockedUntil)) 이후 다시 시도하세요."
        }
        return "승인 코드 입력 시도 횟수를 초과했습니다. 잠시 후 다시 시도하세요."
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
