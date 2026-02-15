import Foundation
@testable import Dochi

@MainActor
final class MockSchedulerService: SchedulerServiceProtocol {
    var schedules: [ScheduleEntry] = []
    var executionHistory: [ScheduleExecutionRecord] = []
    var currentExecution: ScheduleExecutionRecord?

    var addCallCount = 0
    var updateCallCount = 0
    var removeCallCount = 0
    var loadCallCount = 0
    var saveCallCount = 0
    var startCallCount = 0
    var stopCallCount = 0
    var restartCallCount = 0

    private var executionHandler: (@MainActor (ScheduleEntry) async -> Void)?

    func addSchedule(_ entry: ScheduleEntry) {
        addCallCount += 1
        var newEntry = entry
        newEntry.nextRunAt = nextRunDate(for: entry.cronExpression, after: Date())
        schedules.append(newEntry)
    }

    func updateSchedule(_ entry: ScheduleEntry) {
        updateCallCount += 1
        if let index = schedules.firstIndex(where: { $0.id == entry.id }) {
            schedules[index] = entry
        }
    }

    func removeSchedule(id: UUID) {
        removeCallCount += 1
        schedules.removeAll { $0.id == id }
    }

    func loadSchedules() {
        loadCallCount += 1
    }

    func saveSchedules() {
        saveCallCount += 1
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func restart() {
        restartCallCount += 1
    }

    func nextRunDate(for cronExpression: String, after date: Date) -> Date? {
        guard let cron = CronExpression.parse(cronExpression) else { return nil }
        return cron.nextDate(after: date)
    }

    func setExecutionHandler(_ handler: @escaping @MainActor (ScheduleEntry) async -> Void) {
        self.executionHandler = handler
    }
}
