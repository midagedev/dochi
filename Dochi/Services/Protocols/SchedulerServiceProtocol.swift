import Foundation

/// Protocol for schedule-based automation service (J-3)
@MainActor
protocol SchedulerServiceProtocol: AnyObject {
    /// All registered schedules
    var schedules: [ScheduleEntry] { get }

    /// Recent execution history
    var executionHistory: [ScheduleExecutionRecord] { get }

    /// Currently running execution (for banner display)
    var currentExecution: ScheduleExecutionRecord? { get }

    /// Add a new schedule
    func addSchedule(_ entry: ScheduleEntry)

    /// Update an existing schedule
    func updateSchedule(_ entry: ScheduleEntry)

    /// Remove a schedule by ID
    func removeSchedule(id: UUID)

    /// Load schedules from disk
    func loadSchedules()

    /// Save schedules to disk
    func saveSchedules()

    /// Start the scheduler timer
    func start()

    /// Stop the scheduler timer
    func stop()

    /// Restart the scheduler
    func restart()

    /// Calculate next run date for a cron expression
    func nextRunDate(for cronExpression: String, after date: Date) -> Date?

    /// Set the handler called when a schedule fires
    func setExecutionHandler(_ handler: @escaping @MainActor (ScheduleEntry) async -> Void)
}
