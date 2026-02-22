import Foundation

@MainActor
protocol WorkQueueServiceProtocol: AnyObject, Sendable {
    var items: [WorkItem] { get }

    @discardableResult
    func enqueue(_ draft: WorkItemDraft, now: Date) -> WorkItem?

    @discardableResult
    func transitionItem(id: UUID, to status: WorkItemStatus, now: Date) -> WorkItem?

    func recentItems(limit: Int, status: WorkItemStatus?, now: Date) -> [WorkItem]
    func pruneExpiredItems(now: Date)
}

extension WorkQueueServiceProtocol {
    @discardableResult
    func enqueue(_ draft: WorkItemDraft, now: Date = Date()) -> WorkItem? {
        enqueue(draft, now: now)
    }

    @discardableResult
    func transitionItem(id: UUID, to status: WorkItemStatus, now: Date = Date()) -> WorkItem? {
        transitionItem(id: id, to: status, now: now)
    }

    func recentItems(limit: Int = 50, status: WorkItemStatus? = nil, now: Date = Date()) -> [WorkItem] {
        recentItems(limit: limit, status: status, now: now)
    }

    func pruneExpiredItems(now: Date = Date()) {
        pruneExpiredItems(now: now)
    }
}
