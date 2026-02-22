import Foundation

// MARK: - SubscriptionUsageSource

enum SubscriptionUsageSource: String, Codable, CaseIterable, Sendable {
    case externalToolLogs = "external_tool_logs"
    case dochiUsageStore = "dochi_usage_store"

    var displayName: String {
        switch self {
        case .externalToolLogs:
            return "외부 구독 로그"
        case .dochiUsageStore:
            return "도치 종량제"
        }
    }

    var detailText: String {
        switch self {
        case .externalToolLogs:
            return "Claude/Codex 로컬 세션 로그에서 집계"
        case .dochiUsageStore:
            return "Dochi UsageStore 기반 집계"
        }
    }

    var axisSectionTitle: String {
        switch self {
        case .externalToolLogs:
            return "외부 로그/API 기반"
        case .dochiUsageStore:
            return "Dochi UsageStore 기반"
        }
    }
}

// MARK: - SubscriptionPlan

struct SubscriptionPlan: Codable, Sendable, Identifiable {
    let id: UUID
    var providerName: String
    var planName: String
    var usageSource: SubscriptionUsageSource
    var monthlyTokenLimit: Int?  // nil = 무제한
    var resetDayOfMonth: Int     // 매월 N일 리셋
    var monthlyCostUSD: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        providerName: String,
        planName: String,
        usageSource: SubscriptionUsageSource = .dochiUsageStore,
        monthlyTokenLimit: Int? = nil,
        resetDayOfMonth: Int = 1,
        monthlyCostUSD: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.planName = planName
        self.usageSource = usageSource
        self.monthlyTokenLimit = monthlyTokenLimit
        self.resetDayOfMonth = resetDayOfMonth
        self.monthlyCostUSD = monthlyCostUSD
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        providerName = try container.decode(String.self, forKey: .providerName)
        planName = try container.decode(String.self, forKey: .planName)
        usageSource = try container.decodeIfPresent(SubscriptionUsageSource.self, forKey: .usageSource) ?? .dochiUsageStore
        monthlyTokenLimit = try container.decodeIfPresent(Int.self, forKey: .monthlyTokenLimit)
        resetDayOfMonth = try container.decodeIfPresent(Int.self, forKey: .resetDayOfMonth) ?? 1
        monthlyCostUSD = try container.decodeIfPresent(Double.self, forKey: .monthlyCostUSD) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - ResourceUtilization

struct ResourceUtilization: Sendable {
    let subscription: SubscriptionPlan
    let usedTokens: Int
    let daysInPeriod: Int
    let daysRemaining: Int
    let velocityTokensPerDay: Double
    let projectedUsageRatio: Double
    let reserveBufferRatio: Double
    let riskLevel: WasteRiskLevel

    init(
        subscription: SubscriptionPlan,
        usedTokens: Int,
        daysInPeriod: Int,
        daysRemaining: Int,
        velocityTokensPerDay: Double = 0,
        projectedUsageRatio: Double? = nil,
        reserveBufferRatio: Double = 0.08,
        riskLevel: WasteRiskLevel
    ) {
        self.subscription = subscription
        self.usedTokens = usedTokens
        self.daysInPeriod = daysInPeriod
        self.daysRemaining = daysRemaining
        self.velocityTokensPerDay = velocityTokensPerDay
        self.reserveBufferRatio = reserveBufferRatio

        let baseUsageRatio: Double
        if let limit = subscription.monthlyTokenLimit, limit > 0 {
            baseUsageRatio = Double(usedTokens) / Double(limit)
        } else {
            baseUsageRatio = 0
        }
        self.projectedUsageRatio = projectedUsageRatio ?? baseUsageRatio
        self.riskLevel = riskLevel
    }

    var usageRatio: Double {
        guard let limit = subscription.monthlyTokenLimit, limit > 0 else { return 0 }
        return Double(usedTokens) / Double(limit)
    }

    var periodRatio: Double {
        guard daysInPeriod > 0 else { return 0 }
        return Double(daysInPeriod - daysRemaining) / Double(daysInPeriod)
    }

    var remainingRatio: Double {
        guard daysInPeriod > 0 else { return 0 }
        return Double(daysRemaining) / Double(daysInPeriod)
    }

    var currentUnusedPercent: Double {
        guard let limit = subscription.monthlyTokenLimit, limit > 0 else { return 0 }
        let remaining = max(0, limit - usedTokens)
        return (Double(remaining) / Double(limit)) * 100
    }

    var projectedRemainingPercent: Double {
        max(0, (1.0 - projectedUsageRatio) * 100)
    }
}

// MARK: - Monitoring Snapshot

struct SubscriptionMonitoringSnapshot: Sendable, Equatable {
    let subscriptionID: UUID
    let source: SubscriptionUsageSource
    let provider: String
    let statusCode: String
    let statusMessage: String?
    let lastCollectedAt: Date?

    init(
        subscriptionID: UUID,
        source: SubscriptionUsageSource,
        provider: String,
        statusCode: String,
        statusMessage: String? = nil,
        lastCollectedAt: Date? = nil
    ) {
        self.subscriptionID = subscriptionID
        self.source = source
        self.provider = provider
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.lastCollectedAt = lastCollectedAt
    }

    var statusPresentation: MonitoringStatusPresentation {
        switch statusCode {
        case "ok_api":
            return MonitoringStatusPresentation(
                label: "API 정상",
                detail: statusMessage,
                tone: .success
            )
        case "ok_cli":
            return MonitoringStatusPresentation(
                label: "CLI 대체 수집",
                detail: statusMessage ?? "API 실패 시 CLI 통계로 수집했습니다.",
                tone: .info
            )
        case "ok_log_scan":
            return MonitoringStatusPresentation(
                label: "로그 스캔 정상",
                detail: statusMessage,
                tone: .success
            )
        case "ok_store":
            return MonitoringStatusPresentation(
                label: "UsageStore 정상",
                detail: statusMessage,
                tone: .success
            )
        case "not_logged_in":
            return MonitoringStatusPresentation(
                label: "로그인 필요",
                detail: statusMessage ?? "Gemini 인증이 필요합니다. 터미널에서 gemini 인증을 완료하세요.",
                tone: .warning
            )
        case "unsupported_auth_type":
            return MonitoringStatusPresentation(
                label: "인증 타입 미지원",
                detail: statusMessage ?? "api-key/vertex-ai 인증은 현재 사용량 모니터링에서 지원하지 않습니다.",
                tone: .warning
            )
        case "api_error":
            return MonitoringStatusPresentation(
                label: "API 수집 실패",
                detail: statusMessage ?? "API 응답을 확인할 수 없습니다. 네트워크/인증 상태를 점검하세요.",
                tone: .error
            )
        case "cli_error":
            return MonitoringStatusPresentation(
                label: "CLI 수집 실패",
                detail: statusMessage ?? "Gemini CLI 경로/권한/로그인 상태를 점검하세요.",
                tone: .error
            )
        case "parse_error":
            return MonitoringStatusPresentation(
                label: "응답 해석 실패",
                detail: statusMessage ?? "모니터링 응답 포맷이 예상과 달라 해석에 실패했습니다.",
                tone: .error
            )
        case "unsupported_provider":
            return MonitoringStatusPresentation(
                label: "프로바이더 미지원",
                detail: statusMessage ?? "현재 프로바이더는 외부 로그/API 모니터링 대상이 아닙니다.",
                tone: .neutral
            )
        case "no_data":
            return MonitoringStatusPresentation(
                label: "데이터 없음",
                detail: statusMessage ?? "해당 프로바이더의 UsageStore 기록이 아직 없습니다.",
                tone: .neutral
            )
        default:
            return MonitoringStatusPresentation(
                label: statusCode,
                detail: statusMessage,
                tone: .neutral
            )
        }
    }
}

struct MonitoringStatusPresentation: Sendable, Equatable {
    let label: String
    let detail: String?
    let tone: MonitoringStatusTone
}

enum MonitoringStatusTone: Sendable, Equatable {
    case success
    case info
    case warning
    case error
    case neutral
}

// MARK: - WasteRiskLevel

enum WasteRiskLevel: String, Codable, Sendable {
    case comfortable  // 여유: 사용률 < 50% && 잔여 기간 > 50%
    case caution      // 주의: 사용률 < 30% && 잔여 기간 < 30%
    case wasteRisk    // 낭비 위험: 사용률 < 50% && 잔여 기간 < 15%
    case normal       // 정상 사용 패턴

    var displayName: String {
        switch self {
        case .comfortable: return "여유"
        case .caution: return "주의"
        case .wasteRisk: return "낭비 위험"
        case .normal: return "정상"
        }
    }
}

// MARK: - AutoTaskType

enum AutoTaskType: String, Codable, CaseIterable, Sendable {
    case research = "research"
    case memoryCleanup = "memory_cleanup"
    case documentSummary = "document_summary"
    case kanbanCleanup = "kanban_cleanup"
    case gitScanReview = "git_scan_review"

    var displayName: String {
        switch self {
        case .research: return "자료 조사"
        case .memoryCleanup: return "메모리 정리"
        case .documentSummary: return "문서 요약"
        case .kanbanCleanup: return "칸반 정리"
        case .gitScanReview: return "Git 스캔 리뷰"
        }
    }

    var icon: String {
        switch self {
        case .research: return "magnifyingglass"
        case .memoryCleanup: return "brain.head.profile"
        case .documentSummary: return "doc.text"
        case .kanbanCleanup: return "rectangle.3.group"
        case .gitScanReview: return "point.3.connected.trianglepath.dotted"
        }
    }
}

// MARK: - AutoTaskRecord

struct AutoTaskRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let taskType: AutoTaskType
    let subscriptionId: UUID
    let executedAt: Date
    let dedupeKey: String?
    let tokensUsed: Int
    let summary: String

    init(
        id: UUID = UUID(),
        taskType: AutoTaskType,
        subscriptionId: UUID,
        executedAt: Date = Date(),
        dedupeKey: String? = nil,
        tokensUsed: Int = 0,
        summary: String = ""
    ) {
        self.id = id
        self.taskType = taskType
        self.subscriptionId = subscriptionId
        self.executedAt = executedAt
        self.dedupeKey = dedupeKey
        self.tokensUsed = tokensUsed
        self.summary = summary
    }
}

// MARK: - SubscriptionsFile

struct SubscriptionsFile: Codable, Sendable {
    var subscriptions: [SubscriptionPlan]
    var autoTaskRecords: [AutoTaskRecord]

    init(subscriptions: [SubscriptionPlan] = [], autoTaskRecords: [AutoTaskRecord] = []) {
        self.subscriptions = subscriptions
        self.autoTaskRecords = autoTaskRecords
    }
}
