import Foundation

@MainActor
protocol ResourceOptimizerProtocol: Sendable {
    // MARK: - Subscription CRUD
    var subscriptions: [SubscriptionPlan] { get }
    func addSubscription(_ plan: SubscriptionPlan) async
    func updateSubscription(_ plan: SubscriptionPlan) async
    func deleteSubscription(id: UUID) async
    func bootstrapDefaultExternalSubscriptionsIfNeeded() async -> Int

    // MARK: - Utilization
    func utilization(for subscription: SubscriptionPlan) async -> ResourceUtilization
    func allUtilizations() async -> [ResourceUtilization]
    func monitoringSnapshot(for subscription: SubscriptionPlan) async -> SubscriptionMonitoringSnapshot
    func monitoringSnapshots(for subscriptions: [SubscriptionPlan]) async -> [UUID: SubscriptionMonitoringSnapshot]

    // MARK: - Risk Assessment
    func calculateRiskLevel(
        usageRatio: Double,
        remainingRatio: Double,
        projectedUsageRatio: Double?,
        reserveBufferRatio: Double
    ) -> WasteRiskLevel

    // MARK: - Auto Tasks
    var autoTaskRecords: [AutoTaskRecord] { get }
    func queueAutoTask(
        type: AutoTaskType,
        subscriptionId: UUID,
        dedupeKey: String?,
        summary: String
    ) async
    func evaluateAndQueueAutoTasks(
        enabledTypes: [AutoTaskType],
        onlyWasteRisk: Bool,
        gitInsights: [GitRepositoryInsight]?
    ) async -> Int
}

extension ResourceOptimizerProtocol {
    func calculateRiskLevel(usageRatio: Double, remainingRatio: Double) -> WasteRiskLevel {
        calculateRiskLevel(
            usageRatio: usageRatio,
            remainingRatio: remainingRatio,
            projectedUsageRatio: nil,
            reserveBufferRatio: 0.08
        )
    }

    func queueAutoTask(type: AutoTaskType, subscriptionId: UUID) async {
        await queueAutoTask(
            type: type,
            subscriptionId: subscriptionId,
            dedupeKey: nil,
            summary: ""
        )
    }

    func evaluateAndQueueAutoTasks(enabledTypes: [AutoTaskType], onlyWasteRisk: Bool) async -> Int {
        await evaluateAndQueueAutoTasks(
            enabledTypes: enabledTypes,
            onlyWasteRisk: onlyWasteRisk,
            gitInsights: nil
        )
    }

    func bootstrapDefaultExternalSubscriptionsIfNeeded() async -> Int { 0 }

    func monitoringSnapshots(for subscriptions: [SubscriptionPlan]) async -> [UUID: SubscriptionMonitoringSnapshot] {
        var result: [UUID: SubscriptionMonitoringSnapshot] = [:]
        for subscription in subscriptions {
            result[subscription.id] = await monitoringSnapshot(for: subscription)
        }
        return result
    }
}
