import Foundation
@testable import Dochi

@MainActor
final class MockResourceOptimizer: ResourceOptimizerProtocol {
    var subscriptions: [SubscriptionPlan] = []
    var autoTaskRecords: [AutoTaskRecord] = []
    var monitoringSnapshotsByID: [UUID: SubscriptionMonitoringSnapshot] = [:]
    var bootstrapCallCount = 0
    var bootstrapResult = 0

    var addSubscriptionCallCount = 0
    var updateSubscriptionCallCount = 0
    var deleteSubscriptionCallCount = 0
    var queueAutoTaskCallCount = 0
    var evaluateAndQueueAutoTasksCallCount = 0

    var lastEvaluatedTypes: [AutoTaskType] = []
    var lastOnlyWasteRisk: Bool?
    var lastGitInsights: [GitRepositoryInsight]?
    var evaluateAndQueueAutoTasksResult = 0

    func addSubscription(_ plan: SubscriptionPlan) async {
        addSubscriptionCallCount += 1
        subscriptions.append(plan)
    }

    func updateSubscription(_ plan: SubscriptionPlan) async {
        updateSubscriptionCallCount += 1
        if let index = subscriptions.firstIndex(where: { $0.id == plan.id }) {
            subscriptions[index] = plan
        }
    }

    func deleteSubscription(id: UUID) async {
        deleteSubscriptionCallCount += 1
        subscriptions.removeAll { $0.id == id }
    }

    func bootstrapDefaultExternalSubscriptionsIfNeeded() async -> Int {
        bootstrapCallCount += 1
        return bootstrapResult
    }

    func utilization(for subscription: SubscriptionPlan) async -> ResourceUtilization {
        ResourceUtilization(
            subscription: subscription,
            usedTokens: 50000,
            daysInPeriod: 30,
            daysRemaining: 15,
            riskLevel: calculateRiskLevel(usageRatio: 0.5, remainingRatio: 0.5)
        )
    }

    func allUtilizations() async -> [ResourceUtilization] {
        var results: [ResourceUtilization] = []
        for sub in subscriptions {
            results.append(await utilization(for: sub))
        }
        return results
    }

    func monitoringSnapshot(for subscription: SubscriptionPlan) async -> SubscriptionMonitoringSnapshot {
        if let existing = monitoringSnapshotsByID[subscription.id] {
            return existing
        }
        return SubscriptionMonitoringSnapshot(
            subscriptionID: subscription.id,
            source: subscription.usageSource,
            provider: subscription.providerName,
            statusCode: subscription.usageSource == .externalToolLogs ? "ok_log_scan" : "ok_store",
            statusMessage: nil,
            lastCollectedAt: Date()
        )
    }

    func calculateRiskLevel(
        usageRatio: Double,
        remainingRatio: Double,
        projectedUsageRatio: Double?,
        reserveBufferRatio: Double
    ) -> WasteRiskLevel {
        if usageRatio < 0.5 && remainingRatio < 0.15 {
            return .wasteRisk
        }
        if usageRatio < 0.3 && remainingRatio < 0.3 {
            return .caution
        }
        if usageRatio < 0.5 && remainingRatio > 0.5 {
            return .comfortable
        }
        return .normal
    }

    func queueAutoTask(
        type: AutoTaskType,
        subscriptionId: UUID,
        dedupeKey: String?,
        summary: String
    ) async {
        queueAutoTaskCallCount += 1
        autoTaskRecords.append(AutoTaskRecord(
            taskType: type,
            subscriptionId: subscriptionId,
            dedupeKey: dedupeKey,
            summary: summary
        ))
    }

    func evaluateAndQueueAutoTasks(
        enabledTypes: [AutoTaskType],
        onlyWasteRisk: Bool,
        gitInsights: [GitRepositoryInsight]?
    ) async -> Int {
        evaluateAndQueueAutoTasksCallCount += 1
        lastEvaluatedTypes = enabledTypes
        lastOnlyWasteRisk = onlyWasteRisk
        lastGitInsights = gitInsights
        return evaluateAndQueueAutoTasksResult
    }
}
