import Foundation
import os

// MARK: - AuditLogRetentionConfig

/// 운영 데이터 보존 정책 설정.
/// - 감사 로그: 30일
/// - 세션 진단 로그: 7일 (로컬)
struct AuditLogRetentionConfig: Sendable, Codable, Equatable {
    /// 감사 로그 보존 기간 (일).
    let auditRetentionDays: Int

    /// 세션 진단 로그 보존 기간 (일).
    let diagnosticRetentionDays: Int

    /// 기본 보존 정책.
    static let `default` = AuditLogRetentionConfig(
        auditRetentionDays: 30,
        diagnosticRetentionDays: 7
    )

    /// 감사 로그 보존 기간 cutoff 날짜.
    var auditCutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -auditRetentionDays, to: Date()) ?? Date()
    }

    /// 진단 로그 보존 기간 cutoff 날짜.
    var diagnosticCutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -diagnosticRetentionDays, to: Date()) ?? Date()
    }
}

// MARK: - DiagnosticLogEntry

/// 세션 진단 로그 항목.
struct DiagnosticLogEntry: Sendable, Codable, Identifiable {
    let id: UUID
    let sessionId: String
    let timestamp: Date
    let level: DiagnosticLevel
    let message: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        sessionId: String,
        timestamp: Date = Date(),
        level: DiagnosticLevel = .info,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.metadata = metadata
    }
}

/// 진단 로그 레벨.
enum DiagnosticLevel: String, Sendable, Codable, CaseIterable {
    case debug
    case info
    case warning
    case error
}

// MARK: - DiagnosticLogManager

/// 세션 진단 로그 관리 — 로컬 저장 및 보존 정책 기반 정리.
@MainActor
@Observable
final class DiagnosticLogManager {
    private(set) var entries: [DiagnosticLogEntry] = []
    let retentionConfig: AuditLogRetentionConfig

    private static let maxEntries = 10_000

    init(retentionConfig: AuditLogRetentionConfig = .default) {
        self.retentionConfig = retentionConfig
    }

    // MARK: - Logging

    /// 진단 로그를 기록한다.
    func log(sessionId: String, level: DiagnosticLevel, message: String, metadata: [String: String] = [:]) {
        let entry = DiagnosticLogEntry(
            sessionId: sessionId,
            level: level,
            message: message,
            metadata: metadata
        )
        entries.append(entry)

        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }

        Log.runtime.debug("Diagnostic [\(level.rawValue, privacy: .public)] session=\(sessionId, privacy: .public): \(message, privacy: .public)")
    }

    // MARK: - Query

    /// 특정 세션의 진단 로그를 조회한다.
    func entries(for sessionId: String) -> [DiagnosticLogEntry] {
        entries.filter { $0.sessionId == sessionId }
    }

    /// 지정 레벨 이상의 로그를 조회한다.
    func entries(minLevel: DiagnosticLevel) -> [DiagnosticLogEntry] {
        let levelOrder: [DiagnosticLevel] = [.debug, .info, .warning, .error]
        guard let minIndex = levelOrder.firstIndex(of: minLevel) else { return entries }
        let validLevels = Set(levelOrder[minIndex...])
        return entries.filter { validLevels.contains($0.level) }
    }

    // MARK: - Retention

    /// 보존 정책에 따라 오래된 진단 로그를 정리한다.
    @discardableResult
    func purgeExpired() -> Int {
        let cutoff = retentionConfig.diagnosticCutoffDate
        let before = entries.count
        entries.removeAll { $0.timestamp < cutoff }
        let purged = before - entries.count
        if purged > 0 {
            Log.runtime.info("Diagnostic log purge: \(purged) entries removed (cutoff=\(cutoff))")
        }
        return purged
    }

    /// 전체 진단 로그를 초기화한다.
    func clear() {
        entries.removeAll()
        Log.runtime.info("Diagnostic log cleared")
    }
}
