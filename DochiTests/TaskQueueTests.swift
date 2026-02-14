import XCTest
@testable import Dochi

@MainActor
final class TaskQueueTests: XCTestCase {
    private var manager: TaskQueueManager!

    override func setUp() {
        super.setUp()
        manager = TaskQueueManager(deviceId: "test-device", capabilities: ["llm", "tts", "tools"])
    }

    // MARK: - DochiTaskType

    func testTaskTypeDisplayNames() {
        XCTAssertEqual(DochiTaskType.llmQuery.displayName, "LLM 쿼리")
        XCTAssertEqual(DochiTaskType.toolExecution.displayName, "도구 실행")
        XCTAssertEqual(DochiTaskType.ttsPlayback.displayName, "TTS 재생")
        XCTAssertEqual(DochiTaskType.notification.displayName, "알림")
        XCTAssertEqual(DochiTaskType.workflowStep.displayName, "워크플로우 단계")
        XCTAssertEqual(DochiTaskType.custom.displayName, "사용자 정의")
    }

    func testTaskTypeCodable() throws {
        for type in DochiTaskType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(DochiTaskType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    // MARK: - DochiTaskPriority

    func testPrioritySortOrder() {
        XCTAssertLessThan(DochiTaskPriority.urgent, DochiTaskPriority.high)
        XCTAssertLessThan(DochiTaskPriority.high, DochiTaskPriority.normal)
        XCTAssertLessThan(DochiTaskPriority.normal, DochiTaskPriority.low)
    }

    func testPriorityCodable() throws {
        for p in DochiTaskPriority.allCases {
            let data = try JSONEncoder().encode(p)
            let decoded = try JSONDecoder().decode(DochiTaskPriority.self, from: data)
            XCTAssertEqual(decoded, p)
        }
    }

    // MARK: - DochiTask Model

    func testTaskInitDefaults() {
        let task = DochiTask(type: .llmQuery)
        XCTAssertEqual(task.type, .llmQuery)
        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.priority, .normal)
        XCTAssertTrue(task.requiredCapabilities.isEmpty)
        XCTAssertNil(task.assignedDeviceId)
        XCTAssertNil(task.result)
        XCTAssertNil(task.errorMessage)
        XCTAssertNil(task.deadline)
        XCTAssertEqual(task.retryCount, 0)
    }

    func testTaskPayloadParsing() {
        let task = DochiTask(type: .custom, payloadJSON: "{\"query\":\"hello\",\"count\":42}")
        let payload = task.payload
        XCTAssertEqual(payload["query"] as? String, "hello")
        XCTAssertEqual(payload["count"] as? Int, 42)
    }

    func testTaskPayloadInvalidJSON() {
        let task = DochiTask(type: .custom, payloadJSON: "not json")
        XCTAssertTrue(task.payload.isEmpty)
    }

    func testTaskCodableRoundtrip() throws {
        let task = DochiTask(
            type: .toolExecution,
            payloadJSON: "{\"tool\":\"test\"}",
            requiredCapabilities: ["llm", "mcp"],
            priority: .high,
            deadline: Date().addingTimeInterval(3600)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(task)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DochiTask.self, from: data)

        XCTAssertEqual(decoded.id, task.id)
        XCTAssertEqual(decoded.type, .toolExecution)
        XCTAssertEqual(decoded.priority, .high)
        XCTAssertEqual(decoded.requiredCapabilities, ["llm", "mcp"])
        XCTAssertNotNil(decoded.deadline)
    }

    // MARK: - Enqueue

    func testEnqueue() {
        let task = manager.enqueue(type: .llmQuery, payloadJSON: "{\"q\":\"test\"}")
        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(manager.allTasks().count, 1)
    }

    func testEnqueueMultiple() {
        manager.enqueue(type: .llmQuery)
        manager.enqueue(type: .ttsPlayback)
        manager.enqueue(type: .notification)
        XCTAssertEqual(manager.allTasks().count, 3)
    }

    // MARK: - Pending Tasks

    func testPendingTasksSortedByPriority() {
        manager.enqueue(type: .custom, priority: .low)
        manager.enqueue(type: .custom, priority: .urgent)
        manager.enqueue(type: .custom, priority: .normal)

        let pending = manager.pendingTasks()
        XCTAssertEqual(pending.count, 3)
        XCTAssertEqual(pending[0].priority, .urgent)
        XCTAssertEqual(pending[1].priority, .normal)
        XCTAssertEqual(pending[2].priority, .low)
    }

    // MARK: - Assignment

    func testAssignTask() {
        let task = manager.enqueue(type: .llmQuery, requiredCapabilities: ["llm"])
        let result = manager.assign(taskId: task.id, deviceId: "dev-1", deviceCapabilities: ["llm", "tts"])
        XCTAssertTrue(result)

        let updated = manager.task(id: task.id)!
        XCTAssertEqual(updated.status, .assigned)
        XCTAssertEqual(updated.assignedDeviceId, "dev-1")
    }

    func testAssignTaskMissingCapability() {
        let task = manager.enqueue(type: .toolExecution, requiredCapabilities: ["mcp", "internet"])
        let result = manager.assign(taskId: task.id, deviceId: "dev-1", deviceCapabilities: ["llm", "tts"])
        XCTAssertFalse(result)
        XCTAssertEqual(manager.task(id: task.id)!.status, .pending)
    }

    func testAssignAlreadyAssigned() {
        let task = manager.enqueue(type: .llmQuery)
        _ = manager.assign(taskId: task.id, deviceId: "dev-1", deviceCapabilities: [])
        let result = manager.assign(taskId: task.id, deviceId: "dev-2", deviceCapabilities: [])
        XCTAssertFalse(result) // Can't reassign
    }

    func testAssignNonExistent() {
        let result = manager.assign(taskId: UUID(), deviceId: "dev-1", deviceCapabilities: [])
        XCTAssertFalse(result)
    }

    // MARK: - Claim Next

    func testClaimNext() {
        manager.enqueue(type: .llmQuery, requiredCapabilities: ["llm"])
        let claimed = manager.claimNext()
        XCTAssertNotNil(claimed)
        XCTAssertEqual(claimed?.status, .assigned)
        XCTAssertEqual(claimed?.assignedDeviceId, "test-device")
    }

    func testClaimNextSkipsUnmatched() {
        manager.enqueue(type: .custom, requiredCapabilities: ["internet"]) // not in local capabilities
        manager.enqueue(type: .llmQuery, requiredCapabilities: ["llm"])
        let claimed = manager.claimNext()
        XCTAssertNotNil(claimed)
        XCTAssertEqual(claimed?.type, .llmQuery)
    }

    func testClaimNextNoPending() {
        let claimed = manager.claimNext()
        XCTAssertNil(claimed)
    }

    func testClaimNextPriorityOrder() {
        manager.enqueue(type: .custom, requiredCapabilities: [], priority: .low)
        manager.enqueue(type: .custom, requiredCapabilities: [], priority: .urgent)
        let claimed = manager.claimNext()
        XCTAssertEqual(claimed?.priority, .urgent)
    }

    // MARK: - Status Updates

    func testMarkRunning() {
        let task = manager.enqueue(type: .llmQuery)
        _ = manager.assign(taskId: task.id, deviceId: "dev", deviceCapabilities: [])
        let result = manager.markRunning(taskId: task.id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.task(id: task.id)!.status, .running)
    }

    func testMarkRunningNotAssigned() {
        let task = manager.enqueue(type: .llmQuery)
        let result = manager.markRunning(taskId: task.id)
        XCTAssertFalse(result) // pending, not assigned
    }

    func testMarkCompleted() {
        let task = manager.enqueue(type: .llmQuery)
        _ = manager.assign(taskId: task.id, deviceId: "dev", deviceCapabilities: [])
        _ = manager.markRunning(taskId: task.id)
        let result = manager.markCompleted(taskId: task.id, result: "done!")
        XCTAssertTrue(result)

        let updated = manager.task(id: task.id)!
        XCTAssertEqual(updated.status, .completed)
        XCTAssertEqual(updated.result, "done!")
    }

    func testMarkCompletedFromAssigned() {
        let task = manager.enqueue(type: .llmQuery)
        _ = manager.assign(taskId: task.id, deviceId: "dev", deviceCapabilities: [])
        let result = manager.markCompleted(taskId: task.id, result: "done")
        XCTAssertTrue(result) // Can complete directly from assigned
    }

    func testMarkFailed() {
        let task = manager.enqueue(type: .llmQuery)
        _ = manager.assign(taskId: task.id, deviceId: "dev", deviceCapabilities: [])
        _ = manager.markRunning(taskId: task.id)
        let result = manager.markFailed(taskId: task.id, error: "timeout")
        XCTAssertTrue(result)

        let updated = manager.task(id: task.id)!
        // Should be re-enqueued for retry (retryCount < maxRetries)
        XCTAssertEqual(updated.status, .pending)
        XCTAssertEqual(updated.retryCount, 1)
        XCTAssertNil(updated.assignedDeviceId)
    }

    func testMarkFailedPermanentlyAfterMaxRetries() {
        let task = manager.enqueue(type: .llmQuery)

        for i in 0..<3 {
            _ = manager.assign(taskId: task.id, deviceId: "dev", deviceCapabilities: [])
            _ = manager.markRunning(taskId: task.id)
            _ = manager.markFailed(taskId: task.id, error: "retry \(i)")
        }

        let updated = manager.task(id: task.id)!
        XCTAssertEqual(updated.status, .failed)
        XCTAssertEqual(updated.retryCount, 3)
    }

    func testCancel() {
        let task = manager.enqueue(type: .llmQuery)
        let result = manager.cancel(taskId: task.id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.task(id: task.id)!.status, .cancelled)
    }

    func testCancelCompletedFails() {
        let task = manager.enqueue(type: .llmQuery)
        _ = manager.assign(taskId: task.id, deviceId: "dev", deviceCapabilities: [])
        _ = manager.markCompleted(taskId: task.id, result: "ok")
        let result = manager.cancel(taskId: task.id)
        XCTAssertFalse(result)
    }

    // MARK: - Cleanup

    func testCleanupRemovesOld() {
        let task = manager.enqueue(type: .llmQuery)
        _ = manager.assign(taskId: task.id, deviceId: "dev", deviceCapabilities: [])
        _ = manager.markCompleted(taskId: task.id, result: "ok")

        // Move updatedAt to the past
        var t = manager.tasks[task.id]!
        t.updatedAt = Date().addingTimeInterval(-100000)
        manager.tasks[task.id] = t

        manager.cleanup(olderThan: 86400)
        XCTAssertNil(manager.task(id: task.id))
    }

    func testCleanupKeepsRecent() {
        let task = manager.enqueue(type: .llmQuery)
        _ = manager.assign(taskId: task.id, deviceId: "dev", deviceCapabilities: [])
        _ = manager.markCompleted(taskId: task.id, result: "ok")

        manager.cleanup(olderThan: 86400)
        XCTAssertNotNil(manager.task(id: task.id)) // Still recent
    }

    func testCleanupKeepsPending() {
        let task = manager.enqueue(type: .llmQuery)
        var t = manager.tasks[task.id]!
        t.updatedAt = Date().addingTimeInterval(-100000)
        manager.tasks[task.id] = t

        manager.cleanup(olderThan: 86400)
        XCTAssertNotNil(manager.task(id: task.id)) // Pending tasks not cleaned
    }

    // MARK: - Deadlines

    func testCheckDeadlinesExpired() {
        let task = manager.enqueue(
            type: .llmQuery,
            deadline: Date().addingTimeInterval(-60) // Already past
        )
        manager.checkDeadlines()
        let updated = manager.task(id: task.id)!
        // Should be re-enqueued (retryCount < maxRetries), but marked pending with error
        XCTAssertEqual(updated.errorMessage, "기한 초과")
    }

    func testCheckDeadlinesNotExpired() {
        let task = manager.enqueue(
            type: .llmQuery,
            deadline: Date().addingTimeInterval(3600) // 1 hour from now
        )
        manager.checkDeadlines()
        XCTAssertEqual(manager.task(id: task.id)!.status, .pending)
        XCTAssertNil(manager.task(id: task.id)!.errorMessage)
    }

    // MARK: - Tasks For Device

    func testTasksForDevice() {
        let t1 = manager.enqueue(type: .llmQuery)
        let t2 = manager.enqueue(type: .ttsPlayback)
        _ = manager.assign(taskId: t1.id, deviceId: "dev-a", deviceCapabilities: [])
        _ = manager.assign(taskId: t2.id, deviceId: "dev-b", deviceCapabilities: [])

        let forA = manager.tasksForDevice(deviceId: "dev-a")
        XCTAssertEqual(forA.count, 1)
        XCTAssertEqual(forA[0].id, t1.id)
    }
}
