import Foundation

// MARK: - Task Types

enum DochiTaskType: String, Codable, Sendable, CaseIterable {
    case llmQuery = "llm_query"
    case toolExecution = "tool_execution"
    case ttsPlayback = "tts_playback"
    case notification = "notification"
    case workflowStep = "workflow_step"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .llmQuery: "LLM 쿼리"
        case .toolExecution: "도구 실행"
        case .ttsPlayback: "TTS 재생"
        case .notification: "알림"
        case .workflowStep: "워크플로우 단계"
        case .custom: "사용자 정의"
        }
    }
}

enum DochiTaskPriority: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case normal
    case high
    case urgent

    var sortOrder: Int {
        switch self {
        case .urgent: 0
        case .high: 1
        case .normal: 2
        case .low: 3
        }
    }

    static func < (lhs: DochiTaskPriority, rhs: DochiTaskPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

enum DochiTaskStatus: String, Codable, Sendable {
    case pending
    case assigned
    case running
    case completed
    case failed
    case cancelled
}

// MARK: - Task Model

struct DochiTask: Codable, Identifiable, Sendable {
    let id: UUID
    var type: DochiTaskType
    var payloadJSON: String        // JSON-encoded payload
    var requiredCapabilities: [String]
    var priority: DochiTaskPriority
    var status: DochiTaskStatus
    var assignedDeviceId: String?
    var result: String?
    var errorMessage: String?
    let createdAt: Date
    var updatedAt: Date
    var deadline: Date?
    var retryCount: Int

    init(
        id: UUID = UUID(),
        type: DochiTaskType,
        payloadJSON: String = "{}",
        requiredCapabilities: [String] = [],
        priority: DochiTaskPriority = .normal,
        status: DochiTaskStatus = .pending,
        assignedDeviceId: String? = nil,
        result: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deadline: Date? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.type = type
        self.payloadJSON = payloadJSON
        self.requiredCapabilities = requiredCapabilities
        self.priority = priority
        self.status = status
        self.assignedDeviceId = assignedDeviceId
        self.result = result
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deadline = deadline
        self.retryCount = retryCount
    }

    var payload: [String: Any] {
        guard let data = payloadJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

// MARK: - Task Queue Manager

@MainActor
final class TaskQueueManager {
    static let shared = TaskQueueManager()

    var tasks: [UUID: DochiTask] = [:]
    private let maxRetries = 3

    /// Local device capabilities.
    var localCapabilities: [String] = ["llm", "tts", "tools"]
    var localDeviceId: String = ""

    private init() {}

    /// Testable initializer.
    init(deviceId: String, capabilities: [String] = []) {
        self.localDeviceId = deviceId
        self.localCapabilities = capabilities
    }

    // MARK: - Task CRUD

    @discardableResult
    func enqueue(
        type: DochiTaskType,
        payloadJSON: String = "{}",
        requiredCapabilities: [String] = [],
        priority: DochiTaskPriority = .normal,
        deadline: Date? = nil
    ) -> DochiTask {
        let task = DochiTask(
            type: type,
            payloadJSON: payloadJSON,
            requiredCapabilities: requiredCapabilities,
            priority: priority,
            deadline: deadline
        )
        tasks[task.id] = task
        Log.app.info("Task enqueued: \(task.type.rawValue) [\(task.id.uuidString.prefix(8))]")
        return task
    }

    func task(id: UUID) -> DochiTask? {
        tasks[id]
    }

    func pendingTasks() -> [DochiTask] {
        tasks.values
            .filter { $0.status == .pending }
            .sorted { $0.priority < $1.priority }
    }

    func tasksForDevice(deviceId: String) -> [DochiTask] {
        tasks.values
            .filter { $0.assignedDeviceId == deviceId && ($0.status == .assigned || $0.status == .running) }
            .sorted { $0.priority < $1.priority }
    }

    func allTasks(limit: Int = 50) -> [DochiTask] {
        Array(tasks.values.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    // MARK: - Task Assignment

    /// Assigns a pending task to a device if capabilities match.
    func assign(taskId: UUID, deviceId: String, deviceCapabilities: [String]) -> Bool {
        guard var task = tasks[taskId], task.status == .pending else { return false }

        // Check capabilities
        for cap in task.requiredCapabilities {
            guard deviceCapabilities.contains(cap) else {
                Log.app.debug("Device \(deviceId) missing capability: \(cap)")
                return false
            }
        }

        task.status = .assigned
        task.assignedDeviceId = deviceId
        task.updatedAt = Date()
        tasks[taskId] = task
        Log.app.info("Task assigned: [\(taskId.uuidString.prefix(8))] → \(deviceId)")
        return true
    }

    /// Claims the next available task for the local device.
    func claimNext() -> DochiTask? {
        let pending = pendingTasks()
        for task in pending {
            if assign(taskId: task.id, deviceId: localDeviceId, deviceCapabilities: localCapabilities) {
                return tasks[task.id]
            }
        }
        return nil
    }

    // MARK: - Task Status Updates

    func markRunning(taskId: UUID) -> Bool {
        guard var task = tasks[taskId], task.status == .assigned else { return false }
        task.status = .running
        task.updatedAt = Date()
        tasks[taskId] = task
        return true
    }

    func markCompleted(taskId: UUID, result: String) -> Bool {
        guard var task = tasks[taskId],
              task.status == .running || task.status == .assigned else { return false }
        task.status = .completed
        task.result = result
        task.updatedAt = Date()
        tasks[taskId] = task
        Log.app.info("Task completed: [\(taskId.uuidString.prefix(8))]")
        return true
    }

    func markFailed(taskId: UUID, error: String) -> Bool {
        guard var task = tasks[taskId],
              task.status == .running || task.status == .assigned else { return false }
        task.retryCount += 1
        task.errorMessage = error
        task.updatedAt = Date()

        if task.retryCount < self.maxRetries {
            // Re-enqueue for retry
            task.status = .pending
            task.assignedDeviceId = nil
            tasks[taskId] = task
            Log.app.warning("Task failed, retry \(task.retryCount)/\(self.maxRetries): [\(taskId.uuidString.prefix(8))]")
        } else {
            task.status = .failed
            tasks[taskId] = task
            Log.app.error("Task permanently failed: [\(taskId.uuidString.prefix(8))]")
        }
        return true
    }

    func cancel(taskId: UUID) -> Bool {
        guard var task = tasks[taskId],
              task.status != .completed && task.status != .failed else { return false }
        task.status = .cancelled
        task.updatedAt = Date()
        tasks[taskId] = task
        Log.app.info("Task cancelled: [\(taskId.uuidString.prefix(8))]")
        return true
    }

    // MARK: - Cleanup

    /// Removes completed, failed, and cancelled tasks older than the given interval.
    func cleanup(olderThan interval: TimeInterval = 86400) {
        let cutoff = Date().addingTimeInterval(-interval)
        let toRemove = tasks.values.filter {
            ($0.status == .completed || $0.status == .failed || $0.status == .cancelled)
                && $0.updatedAt < cutoff
        }
        for task in toRemove {
            tasks.removeValue(forKey: task.id)
        }
        if !toRemove.isEmpty {
            Log.app.debug("Cleaned up \(toRemove.count) old tasks")
        }
    }

    /// Checks for expired tasks (past deadline) and marks them failed.
    func checkDeadlines() {
        let now = Date()
        for (id, task) in tasks where task.status == .pending || task.status == .assigned || task.status == .running {
            if let deadline = task.deadline, deadline < now {
                _ = markFailed(taskId: id, error: "기한 초과")
            }
        }
    }
}
