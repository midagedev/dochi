import XCTest
@testable import Dochi

@MainActor
final class SchedulerTests: XCTestCase {

    // MARK: - CronExpression Parsing

    func testParseDailyCron() {
        let cron = CronExpression.parse("0 9 * * *")
        XCTAssertNotNil(cron)
        XCTAssertEqual(cron?.minute, .value(0))
        XCTAssertEqual(cron?.hour, .value(9))
        XCTAssertEqual(cron?.dayOfMonth, .any)
        XCTAssertEqual(cron?.month, .any)
        XCTAssertEqual(cron?.dayOfWeek, .any)
    }

    func testParseWeeklyCron() {
        let cron = CronExpression.parse("0 17 * * 5")
        XCTAssertNotNil(cron)
        XCTAssertEqual(cron?.minute, .value(0))
        XCTAssertEqual(cron?.hour, .value(17))
        XCTAssertEqual(cron?.dayOfWeek, .value(5)) // Friday
    }

    func testParseMonthlyCron() {
        let cron = CronExpression.parse("30 10 15 * *")
        XCTAssertNotNil(cron)
        XCTAssertEqual(cron?.minute, .value(30))
        XCTAssertEqual(cron?.hour, .value(10))
        XCTAssertEqual(cron?.dayOfMonth, .value(15))
    }

    func testParseListCron() {
        let cron = CronExpression.parse("0 9 * * 1,3,5")
        XCTAssertNotNil(cron)
        XCTAssertEqual(cron?.dayOfWeek, .list([1, 3, 5]))
    }

    func testParseInvalidCron() {
        XCTAssertNil(CronExpression.parse("invalid"))
        XCTAssertNil(CronExpression.parse(""))
        XCTAssertNil(CronExpression.parse("0 25 * * *")) // hour 25 out of range
        XCTAssertNil(CronExpression.parse("60 0 * * *")) // minute 60 out of range
        XCTAssertNil(CronExpression.parse("0 0 32 * *")) // day 32 out of range
        XCTAssertNil(CronExpression.parse("0 0 * 13 *")) // month 13 out of range
        XCTAssertNil(CronExpression.parse("0 0 * * 7")) // weekday 7 out of range
    }

    func testParseFiveFields() {
        XCTAssertNil(CronExpression.parse("0 9 * *")) // Only 4 fields
        XCTAssertNil(CronExpression.parse("0 9 * * * *")) // 6 fields
    }

    // MARK: - CronField Matching

    func testCronFieldAnyMatches() {
        XCTAssertTrue(CronExpression.CronField.any.matches(0))
        XCTAssertTrue(CronExpression.CronField.any.matches(59))
    }

    func testCronFieldValueMatches() {
        XCTAssertTrue(CronExpression.CronField.value(5).matches(5))
        XCTAssertFalse(CronExpression.CronField.value(5).matches(6))
    }

    func testCronFieldListMatches() {
        XCTAssertTrue(CronExpression.CronField.list([1, 3, 5]).matches(3))
        XCTAssertFalse(CronExpression.CronField.list([1, 3, 5]).matches(2))
    }

    // MARK: - NextDate Calculation

    func testNextDateDaily() {
        let cron = CronExpression.parse("0 9 * * *")!
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        // Set a known date: 2026-02-15 08:00
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 15
        components.hour = 8
        components.minute = 0
        components.second = 0
        let date = calendar.date(from: components)!

        let next = cron.nextDate(after: date, calendar: calendar)
        XCTAssertNotNil(next)

        let nextComps = calendar.dateComponents([.hour, .minute, .day], from: next!)
        XCTAssertEqual(nextComps.hour, 9)
        XCTAssertEqual(nextComps.minute, 0)
        XCTAssertEqual(nextComps.day, 15) // Same day since it's before 09:00
    }

    func testNextDateDailyAfterTime() {
        let cron = CronExpression.parse("0 9 * * *")!
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        // Set a known date: 2026-02-15 10:00 (after 09:00)
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 15
        components.hour = 10
        components.minute = 0
        components.second = 0
        let date = calendar.date(from: components)!

        let next = cron.nextDate(after: date, calendar: calendar)
        XCTAssertNotNil(next)

        let nextComps = calendar.dateComponents([.day], from: next!)
        XCTAssertEqual(nextComps.day, 16) // Next day
    }

    func testNextDateWeekly() {
        let cron = CronExpression.parse("0 17 * * 5")! // Friday at 17:00
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        // 2026-02-15 is a Sunday
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 15
        components.hour = 0
        components.minute = 0
        components.second = 0
        let date = calendar.date(from: components)!

        let next = cron.nextDate(after: date, calendar: calendar)
        XCTAssertNotNil(next)

        let nextComps = calendar.dateComponents([.weekday, .hour, .minute], from: next!)
        XCTAssertEqual(nextComps.weekday, 6) // Calendar weekday for Friday is 6
        XCTAssertEqual(nextComps.hour, 17)
        XCTAssertEqual(nextComps.minute, 0)
    }

    func testNextDateMonthly() {
        let cron = CronExpression.parse("0 10 1 * *")! // 1st of month at 10:00
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 15
        components.hour = 0
        components.minute = 0
        components.second = 0
        let date = calendar.date(from: components)!

        let next = cron.nextDate(after: date, calendar: calendar)
        XCTAssertNotNil(next)

        let nextComps = calendar.dateComponents([.month, .day, .hour], from: next!)
        XCTAssertEqual(nextComps.month, 3) // March
        XCTAssertEqual(nextComps.day, 1)
        XCTAssertEqual(nextComps.hour, 10)
    }

    // MARK: - Human Readable

    func testHumanReadableDaily() {
        let cron = CronExpression.parse("0 9 * * *")!
        XCTAssertEqual(cron.humanReadable, "매일 09:00")
    }

    func testHumanReadableWeekly() {
        let cron = CronExpression.parse("0 17 * * 5")!
        XCTAssertEqual(cron.humanReadable, "매주 금요일 17:00")
    }

    func testHumanReadableWeeklyList() {
        let cron = CronExpression.parse("0 9 * * 1,3,5")!
        XCTAssertEqual(cron.humanReadable, "매주 월요일, 수요일, 금요일 09:00")
    }

    func testHumanReadableMonthly() {
        let cron = CronExpression.parse("30 10 15 * *")!
        XCTAssertEqual(cron.humanReadable, "매월 15일 10:30")
    }

    // MARK: - ScheduleEntry Model

    func testScheduleEntryCodableRoundtrip() throws {
        let entry = ScheduleEntry(
            name: "아침 브리핑",
            icon: "☀️",
            cronExpression: "0 9 * * *",
            prompt: "오늘 일정을 요약해줘",
            agentName: "도치",
            isEnabled: true,
            lastRunAt: Date(),
            nextRunAt: Date().addingTimeInterval(3600)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScheduleEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.name, entry.name)
        XCTAssertEqual(decoded.icon, entry.icon)
        XCTAssertEqual(decoded.cronExpression, entry.cronExpression)
        XCTAssertEqual(decoded.prompt, entry.prompt)
        XCTAssertEqual(decoded.agentName, entry.agentName)
        XCTAssertEqual(decoded.isEnabled, entry.isEnabled)
    }

    func testScheduleEntryRepeatSummary() {
        let daily = ScheduleEntry(name: "Test", cronExpression: "0 9 * * *", prompt: "test")
        XCTAssertEqual(daily.repeatSummary, "매일 09:00")

        let invalid = ScheduleEntry(name: "Test", cronExpression: "invalid", prompt: "test")
        XCTAssertEqual(invalid.repeatSummary, "invalid")
    }

    // MARK: - ScheduleExecutionRecord Model

    func testExecutionRecordCodableRoundtrip() throws {
        let record = ScheduleExecutionRecord(
            scheduleId: UUID(),
            scheduleName: "테스트",
            startedAt: Date(),
            completedAt: Date().addingTimeInterval(5),
            status: .success,
            errorMessage: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScheduleExecutionRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.scheduleId, record.scheduleId)
        XCTAssertEqual(decoded.scheduleName, record.scheduleName)
        XCTAssertEqual(decoded.status, record.status)
    }

    func testExecutionRecordDuration() {
        let start = Date()
        let end = start.addingTimeInterval(5.5)
        var record = ScheduleExecutionRecord(
            scheduleId: UUID(),
            scheduleName: "Test",
            startedAt: start
        )
        record.completedAt = end
        XCTAssertEqual(record.duration!, 5.5, accuracy: 0.01)

        let incomplete = ScheduleExecutionRecord(scheduleId: UUID(), scheduleName: "Test")
        XCTAssertNil(incomplete.duration)
    }

    // MARK: - RepeatType

    func testRepeatTypeCodableRoundtrip() throws {
        for type in RepeatType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(RepeatType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    // MARK: - ScheduleTemplate

    func testBuiltInTemplates() {
        let templates = ScheduleTemplate.builtIn
        XCTAssertEqual(templates.count, 3)

        // All templates should have valid cron expressions
        for template in templates {
            XCTAssertNotNil(CronExpression.parse(template.cronExpression),
                          "Template '\(template.name)' has invalid cron: \(template.cronExpression)")
        }
    }

    // MARK: - SchedulerService File-based CRUD

    func testSchedulerServiceCRUD() async throws {
        let settings = AppSettings()
        settings.automationEnabled = true
        let service = SchedulerService(settings: settings)

        // Use a temp directory for file storage
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let entry1 = ScheduleEntry(
            name: "테스트 1",
            cronExpression: "0 9 * * *",
            prompt: "테스트 프롬프트 1"
        )
        let entry2 = ScheduleEntry(
            name: "테스트 2",
            cronExpression: "0 17 * * 5",
            prompt: "테스트 프롬프트 2"
        )

        // Add
        service.addSchedule(entry1)
        service.addSchedule(entry2)
        XCTAssertEqual(service.schedules.count, 2)

        // Update
        var updated = service.schedules[0]
        updated.name = "수정된 테스트 1"
        service.updateSchedule(updated)
        XCTAssertEqual(service.schedules[0].name, "수정된 테스트 1")

        // Remove
        service.removeSchedule(id: entry2.id)
        XCTAssertEqual(service.schedules.count, 1)
        XCTAssertEqual(service.schedules[0].id, entry1.id)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Execution History FIFO

    func testExecutionHistoryFIFO() {
        var history: [ScheduleExecutionRecord] = []
        let maxCount = 100

        // Add 110 records
        for i in 0..<110 {
            let record = ScheduleExecutionRecord(
                scheduleId: UUID(),
                scheduleName: "Test \(i)",
                status: .success
            )
            history.insert(record, at: 0)
            if history.count > maxCount {
                history = Array(history.prefix(maxCount))
            }
        }

        XCTAssertEqual(history.count, maxCount)
        // Most recent should be first
        XCTAssertEqual(history[0].scheduleName, "Test 109")
    }

    // MARK: - MockSchedulerService

    func testMockSchedulerService() async {
        let mock = MockSchedulerService()

        let entry = ScheduleEntry(
            name: "Mock Test",
            cronExpression: "0 9 * * *",
            prompt: "test"
        )

        mock.addSchedule(entry)
        XCTAssertEqual(mock.addCallCount, 1)
        XCTAssertEqual(mock.schedules.count, 1)

        var updated = mock.schedules[0]
        updated.name = "Updated"
        mock.updateSchedule(updated)
        XCTAssertEqual(mock.updateCallCount, 1)
        XCTAssertEqual(mock.schedules[0].name, "Updated")

        mock.removeSchedule(id: entry.id)
        XCTAssertEqual(mock.removeCallCount, 1)
        XCTAssertEqual(mock.schedules.count, 0)

        mock.start()
        XCTAssertEqual(mock.startCallCount, 1)
        mock.stop()
        XCTAssertEqual(mock.stopCallCount, 1)
        mock.restart()
        XCTAssertEqual(mock.restartCallCount, 1)
    }

    func testMockNextRunDate() {
        let mock = MockSchedulerService()
        let date = Date()
        let next = mock.nextRunDate(for: "0 9 * * *", after: date)
        XCTAssertNotNil(next)
        XCTAssertNil(mock.nextRunDate(for: "invalid", after: date))
    }

    // MARK: - SettingsSection automation

    func testSettingsSectionAutomationExists() {
        let automation = SettingsSection.automation
        XCTAssertEqual(automation.rawValue, "automation")
        XCTAssertEqual(automation.title, "자동화")
        XCTAssertEqual(automation.icon, "clock.badge.checkmark")
        XCTAssertEqual(automation.group, .general)
        XCTAssertTrue(automation.searchKeywords.contains("자동화"))
        XCTAssertTrue(automation.searchKeywords.contains("cron"))
        XCTAssertTrue(automation.searchKeywords.contains("automation"))
    }

    func testSettingsSectionAllCasesCount() {
        // Ensure adding .automation didn't break allCases
        let allCases = SettingsSection.allCases
        XCTAssertTrue(allCases.contains(.automation))
        // Should be at least 18 sections (17 original + 1 new)
        XCTAssertGreaterThanOrEqual(allCases.count, 18)
    }

    func testSettingsSectionSearchMatches() {
        XCTAssertTrue(SettingsSection.automation.matches(query: "스케줄"))
        XCTAssertTrue(SettingsSection.automation.matches(query: "cron"))
        XCTAssertTrue(SettingsSection.automation.matches(query: "자동화"))
        XCTAssertFalse(SettingsSection.automation.matches(query: "음성"))
    }
}
