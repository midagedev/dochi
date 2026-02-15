import Foundation

// MARK: - SubscriptionPlan

struct SubscriptionPlan: Codable, Sendable, Identifiable {
    let id: UUID
    var providerName: String
    var planName: String
    var monthlyTokenLimit: Int?  // nil = 무제한
    var resetDayOfMonth: Int     // 매월 N일 리셋
    var monthlyCostUSD: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        providerName: String,
        planName: String,
        monthlyTokenLimit: Int? = nil,
        resetDayOfMonth: Int = 1,
        monthlyCostUSD: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.planName = planName
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
    let riskLevel: WasteRiskLevel

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

    var estimatedUnusedPercent: Double {
        guard let limit = subscription.monthlyTokenLimit, limit > 0 else { return 0 }
        let remaining = max(0, limit - usedTokens)
        return (Double(remaining) / Double(limit)) * 100
    }
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

    var displayName: String {
        switch self {
        case .research: return "자료 조사"
        case .memoryCleanup: return "메모리 정리"
        case .documentSummary: return "문서 요약"
        case .kanbanCleanup: return "칸반 정리"
        }
    }

    var icon: String {
        switch self {
        case .research: return "magnifyingglass"
        case .memoryCleanup: return "brain.head.profile"
        case .documentSummary: return "doc.text"
        case .kanbanCleanup: return "rectangle.3.group"
        }
    }
}

// MARK: - AutoTaskRecord

struct AutoTaskRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let taskType: AutoTaskType
    let subscriptionId: UUID
    let executedAt: Date
    let tokensUsed: Int
    let summary: String

    init(
        id: UUID = UUID(),
        taskType: AutoTaskType,
        subscriptionId: UUID,
        executedAt: Date = Date(),
        tokensUsed: Int = 0,
        summary: String = ""
    ) {
        self.id = id
        self.taskType = taskType
        self.subscriptionId = subscriptionId
        self.executedAt = executedAt
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
