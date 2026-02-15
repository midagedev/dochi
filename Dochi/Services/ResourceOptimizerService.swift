import Foundation
import os

/// 구독형 AI 서비스의 유휴 토큰을 감지하고 자동 작업에 배분하는 서비스.
@MainActor
@Observable
final class ResourceOptimizerService: ResourceOptimizerProtocol {
    // MARK: - State

    private(set) var subscriptions: [SubscriptionPlan] = []
    private(set) var autoTaskRecords: [AutoTaskRecord] = []

    // MARK: - Dependencies

    private let baseURL: URL
    private let usageStore: UsageStoreProtocol?

    // MARK: - Init

    init(baseURL: URL? = nil, usageStore: UsageStoreProtocol? = nil) {
        let appSupport = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
        self.baseURL = appSupport
        self.usageStore = usageStore
        loadFromDisk()
    }

    // MARK: - File Path

    private var filePath: URL {
        baseURL.appendingPathComponent("subscriptions.json")
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(SubscriptionsFile.self, from: data)
            subscriptions = file.subscriptions
            autoTaskRecords = file.autoTaskRecords
            Log.storage.debug("Loaded \(self.subscriptions.count) subscriptions")
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError {
                Log.storage.debug("No subscriptions file found, starting fresh")
            } else {
                Log.storage.warning("Failed to load subscriptions: \(error.localizedDescription)")
            }
        }
    }

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let file = SubscriptionsFile(subscriptions: subscriptions, autoTaskRecords: autoTaskRecords)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: filePath, options: .atomic)
            Log.storage.debug("Saved \(self.subscriptions.count) subscriptions")
        } catch {
            Log.storage.error("Failed to save subscriptions: \(error.localizedDescription)")
        }
    }

    // MARK: - Subscription CRUD

    func addSubscription(_ plan: SubscriptionPlan) async {
        subscriptions.append(plan)
        saveToDisk()
    }

    func updateSubscription(_ plan: SubscriptionPlan) async {
        if let index = subscriptions.firstIndex(where: { $0.id == plan.id }) {
            subscriptions[index] = plan
            saveToDisk()
        }
    }

    func deleteSubscription(id: UUID) async {
        subscriptions.removeAll { $0.id == id }
        autoTaskRecords.removeAll { $0.subscriptionId == id }
        saveToDisk()
    }

    // MARK: - Utilization

    func utilization(for subscription: SubscriptionPlan) async -> ResourceUtilization {
        let calendar = Calendar.current
        let now = Date()

        // 리셋일 기준 현재 기간 계산
        let resetDay = min(subscription.resetDayOfMonth, 28)
        var periodStart = calendar.date(bySetting: .day, value: resetDay, of: now) ?? now
        if periodStart > now {
            periodStart = calendar.date(byAdding: .month, value: -1, to: periodStart) ?? periodStart
        }
        let periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? now

        let daysInPeriod = max(1, calendar.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 30)
        let daysRemaining = max(0, calendar.dateComponents([.day], from: now, to: periodEnd).day ?? 0)

        // 현재 기간 사용 토큰 조회
        let usedTokens = await tokensUsedByProvider(subscription.providerName, since: periodStart)

        let usageRatio = subscription.monthlyTokenLimit.map { limit -> Double in
            guard limit > 0 else { return 0 }
            return Double(usedTokens) / Double(limit)
        } ?? 0

        let remainingRatio = Double(daysRemaining) / Double(daysInPeriod)

        let riskLevel = calculateRiskLevel(usageRatio: usageRatio, remainingRatio: remainingRatio)

        return ResourceUtilization(
            subscription: subscription,
            usedTokens: usedTokens,
            daysInPeriod: daysInPeriod,
            daysRemaining: daysRemaining,
            riskLevel: riskLevel
        )
    }

    func allUtilizations() async -> [ResourceUtilization] {
        var results: [ResourceUtilization] = []
        for sub in subscriptions {
            let util = await utilization(for: sub)
            results.append(util)
        }
        return results
    }

    // MARK: - Risk Assessment

    func calculateRiskLevel(usageRatio: Double, remainingRatio: Double) -> WasteRiskLevel {
        // 낭비 위험: 사용률 < 50% && 잔여 기간 < 15%
        if usageRatio < 0.5 && remainingRatio < 0.15 {
            return .wasteRisk
        }
        // 주의: 사용률 < 30% && 잔여 기간 < 30%
        if usageRatio < 0.3 && remainingRatio < 0.3 {
            return .caution
        }
        // 여유: 사용률 < 50% && 잔여 기간 > 50%
        if usageRatio < 0.5 && remainingRatio > 0.5 {
            return .comfortable
        }
        return .normal
    }

    // MARK: - Auto Tasks

    func queueAutoTask(type: AutoTaskType, subscriptionId: UUID) async {
        let record = AutoTaskRecord(
            taskType: type,
            subscriptionId: subscriptionId
        )
        autoTaskRecords.append(record)
        // FIFO: 최대 100건
        if autoTaskRecords.count > 100 {
            autoTaskRecords = Array(autoTaskRecords.suffix(100))
        }
        saveToDisk()
        Log.app.info("Queued auto task: \(type.displayName) for subscription \(subscriptionId)")
    }

    // MARK: - Token Usage Query

    private func tokensUsedByProvider(_ providerName: String, since startDate: Date) async -> Int {
        guard let store = usageStore else { return 0 }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let startStr = dayFormatter.string(from: startDate)
        let providerLower = providerName.lowercased()

        // 현재 월과 이전 월 (리셋일에 따라 월 경계를 넘을 수 있음)
        let months = await store.allMonths()
        var totalTokens = 0

        for month in months {
            let records = await store.dailyRecords(for: month)
            for day in records {
                guard day.date >= startStr else { continue }
                for entry in day.entries {
                    if entry.provider.lowercased() == providerLower {
                        totalTokens += entry.inputTokens + entry.outputTokens
                    }
                }
            }
        }

        return totalTokens
    }
}
