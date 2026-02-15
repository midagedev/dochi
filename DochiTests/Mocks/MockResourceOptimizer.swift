import Foundation
@testable import Dochi

@MainActor
final class MockResourceOptimizer: ResourceOptimizerProtocol {
    var subscriptions: [SubscriptionPlan] = []
    var autoTaskRecords: [AutoTaskRecord] = []

    var addSubscriptionCallCount = 0
    var updateSubscriptionCallCount = 0
    var deleteSubscriptionCallCount = 0
    var queueAutoTaskCallCount = 0

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

    func calculateRiskLevel(usageRatio: Double, remainingRatio: Double) -> WasteRiskLevel {
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

    func queueAutoTask(type: AutoTaskType, subscriptionId: UUID) async {
        queueAutoTaskCallCount += 1
        autoTaskRecords.append(AutoTaskRecord(
            taskType: type,
            subscriptionId: subscriptionId
        ))
    }
}
