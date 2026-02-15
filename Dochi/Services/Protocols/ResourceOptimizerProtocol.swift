import Foundation

@MainActor
protocol ResourceOptimizerProtocol: Sendable {
    // MARK: - Subscription CRUD
    var subscriptions: [SubscriptionPlan] { get }
    func addSubscription(_ plan: SubscriptionPlan) async
    func updateSubscription(_ plan: SubscriptionPlan) async
    func deleteSubscription(id: UUID) async

    // MARK: - Utilization
    func utilization(for subscription: SubscriptionPlan) async -> ResourceUtilization
    func allUtilizations() async -> [ResourceUtilization]

    // MARK: - Risk Assessment
    func calculateRiskLevel(usageRatio: Double, remainingRatio: Double) -> WasteRiskLevel

    // MARK: - Auto Tasks
    var autoTaskRecords: [AutoTaskRecord] { get }
    func queueAutoTask(type: AutoTaskType, subscriptionId: UUID) async
}
