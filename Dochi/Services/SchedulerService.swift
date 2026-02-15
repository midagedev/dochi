import Foundation
import os

/// Schedule-based automation service (J-3)
/// Manages cron-like schedules that trigger agent actions automatically.
@MainActor
@Observable
final class SchedulerService: SchedulerServiceProtocol {

    // MARK: - State

    private(set) var schedules: [ScheduleEntry] = []
    private(set) var executionHistory: [ScheduleExecutionRecord] = []
    private(set) var currentExecution: ScheduleExecutionRecord?

    // MARK: - Configuration

    private let settings: AppSettings
    private var executionHandler: (@MainActor (ScheduleEntry) async throws -> Void)?
    private var timerTask: Task<Void, Never>?
    private let fileManager = FileManager.default
    private let baseURL: URL

    private static let maxHistoryCount = 100
    private static let timerIntervalSeconds = 60

    private var schedulesFileURL: URL {
        baseURL.appendingPathComponent("schedules.json")
    }

    private var historyFileURL: URL {
        baseURL.appendingPathComponent("schedule_history.json")
    }

    // MARK: - Init

    init(settings: AppSettings, baseURL: URL? = nil) {
        self.settings = settings
        self.baseURL = baseURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi")
    }

    /// Clear current execution banner
    func clearCurrentExecution() {
        currentExecution = nil
    }

    // MARK: - CRUD

    func addSchedule(_ entry: ScheduleEntry) {
        var newEntry = entry
        newEntry.nextRunAt = nextRunDate(for: entry.cronExpression, after: Date())
        schedules.append(newEntry)
        saveSchedules()
        Log.app.info("Schedule added: \(entry.name)")
    }

    func updateSchedule(_ entry: ScheduleEntry) {
        guard let index = schedules.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.nextRunAt = nextRunDate(for: entry.cronExpression, after: Date())
        schedules[index] = updated
        saveSchedules()
        Log.app.info("Schedule updated: \(entry.name)")
    }

    func removeSchedule(id: UUID) {
        schedules.removeAll { $0.id == id }
        saveSchedules()
        Log.app.info("Schedule removed: \(id)")
    }

    // MARK: - Persistence

    func loadSchedules() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Load schedules
        do {
            let data = try Data(contentsOf: schedulesFileURL)
            self.schedules = try decoder.decode([ScheduleEntry].self, from: data)
            Log.app.info("Loaded \(self.schedules.count) schedule(s)")
        } catch {
            Log.app.error("Failed to load schedules: \(error.localizedDescription)")
        }

        // Load history
        do {
            let data = try Data(contentsOf: historyFileURL)
            self.executionHistory = try decoder.decode([ScheduleExecutionRecord].self, from: data)
            Log.app.info("Loaded \(self.executionHistory.count) execution history record(s)")
        } catch {
            Log.app.error("Failed to load execution history: \(error.localizedDescription)")
        }

        // Recalculate next run dates
        for i in schedules.indices {
            schedules[i].nextRunAt = nextRunDate(for: schedules[i].cronExpression, after: Date())
        }
    }

    func saveSchedules() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let dir = schedulesFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

            let schedulesData = try encoder.encode(schedules)
            try schedulesData.write(to: schedulesFileURL)

            let historyData = try encoder.encode(executionHistory)
            try historyData.write(to: historyFileURL)
        } catch {
            Log.app.error("Failed to save schedules: \(error.localizedDescription)")
        }
    }

    // MARK: - Timer

    func start() {
        stop()
        guard settings.automationEnabled else { return }

        loadSchedules()

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SchedulerService.timerIntervalSeconds))
                guard !Task.isCancelled else { break }
                await self?.tick()
            }
        }

        Log.app.info("Scheduler started")
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        Log.app.info("Scheduler stopped")
    }

    func restart() {
        stop()
        start()
    }

    func setExecutionHandler(_ handler: @escaping @MainActor (ScheduleEntry) async throws -> Void) {
        self.executionHandler = handler
    }

    // MARK: - Cron Calculation

    func nextRunDate(for cronExpression: String, after date: Date) -> Date? {
        guard let cron = CronExpression.parse(cronExpression) else { return nil }
        return cron.nextDate(after: date)
    }

    // MARK: - Tick

    private func tick() async {
        let now = Date()

        for i in schedules.indices {
            let schedule = schedules[i]
            guard schedule.isEnabled,
                  let nextRun = schedule.nextRunAt,
                  nextRun <= now else { continue }

            await executeSchedule(schedule)

            // Update next run date
            schedules[i].lastRunAt = now
            schedules[i].nextRunAt = nextRunDate(for: schedule.cronExpression, after: now)
        }

        saveSchedules()
    }

    private func executeSchedule(_ schedule: ScheduleEntry) async {
        var record = ScheduleExecutionRecord(
            scheduleId: schedule.id,
            scheduleName: schedule.name
        )
        currentExecution = record

        Log.app.info("Executing schedule: \(schedule.name)")

        if let handler = executionHandler {
            do {
                try await handler(schedule)
                record.status = .success
            } catch {
                record.status = .failure
                record.errorMessage = error.localizedDescription
                Log.app.error("Schedule \(schedule.name) execution failed: \(error.localizedDescription)")
            }
        } else {
            Log.app.warning("No execution handler set for scheduler")
            record.status = .failure
            record.errorMessage = "실행 핸들러가 설정되지 않았습니다"
        }

        record.completedAt = Date()
        currentExecution = record

        // Add to history (FIFO)
        executionHistory.insert(record, at: 0)
        if executionHistory.count > SchedulerService.maxHistoryCount {
            executionHistory = Array(executionHistory.prefix(SchedulerService.maxHistoryCount))
        }

        // Auto-hide banner after 3 seconds for success
        if record.status == .success {
            Task {
                try? await Task.sleep(for: .seconds(3))
                if currentExecution?.id == record.id {
                    currentExecution = nil
                }
            }
        }

        Log.app.info("Schedule \(schedule.name) completed with status: \(record.status.rawValue)")
    }
}
