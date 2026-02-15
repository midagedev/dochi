import SwiftUI

// MARK: - AutomationSettingsView

struct AutomationSettingsView: View {
    var settings: AppSettings
    var schedulerService: SchedulerServiceProtocol?

    @State private var showEditSheet = false
    @State private var showTemplateSheet = false
    @State private var editingSchedule: ScheduleEntry?
    @State private var selectedHistoryRecord: ScheduleExecutionRecord?

    var body: some View {
        Form {
            // Master toggle
            Section {
                Toggle("자동화 활성화", isOn: Binding(
                    get: { settings.automationEnabled },
                    set: { settings.automationEnabled = $0 }
                ))

                Text("크론식 스케줄로 에이전트를 자동 실행합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(
                    title: "자동화",
                    helpContent: "스케줄을 등록하면 지정된 시간에 자동으로 에이전트가 실행됩니다. \"매일 아침 9시 브리핑\", \"매주 금요일 주간 리포트\" 등을 설정할 수 있습니다."
                )
            }

            // Schedule list
            if settings.automationEnabled {
                if let service = schedulerService {
                    if service.schedules.isEmpty {
                        // Empty state
                        Section("스케줄") {
                            VStack(spacing: 12) {
                                Text("등록된 자동화 일정이 없습니다")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("템플릿에서 빠르게 시작하거나 직접 만들어보세요")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)

                                HStack(spacing: 12) {
                                    Button("템플릿에서 추가") {
                                        showTemplateSheet = true
                                    }
                                    .buttonStyle(.bordered)

                                    Button("직접 만들기") {
                                        editingSchedule = nil
                                        showEditSheet = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                    } else {
                        // Schedule list
                        Section("스케줄") {
                            ForEach(service.schedules) { schedule in
                                ScheduleRowView(
                                    schedule: schedule,
                                    onToggle: { isEnabled in
                                        var updated = schedule
                                        updated.isEnabled = isEnabled
                                        service.updateSchedule(updated)
                                    },
                                    onEdit: {
                                        editingSchedule = schedule
                                        showEditSheet = true
                                    }
                                )
                            }

                            HStack(spacing: 12) {
                                Button {
                                    editingSchedule = nil
                                    showEditSheet = true
                                } label: {
                                    Label("새 스케줄 추가", systemImage: "plus")
                                }

                                Button {
                                    showTemplateSheet = true
                                } label: {
                                    Label("템플릿에서 추가", systemImage: "doc.on.doc")
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    // Execution history
                    if !service.executionHistory.isEmpty {
                        Section("실행 이력") {
                            ForEach(service.executionHistory.prefix(20)) { record in
                                ScheduleHistoryRowView(
                                    record: record,
                                    isExpanded: selectedHistoryRecord?.id == record.id,
                                    onTap: {
                                        if selectedHistoryRecord?.id == record.id {
                                            selectedHistoryRecord = nil
                                        } else {
                                            selectedHistoryRecord = record
                                        }
                                    }
                                )
                            }
                        }
                    }
                } else {
                    Section {
                        Text("스케줄러 서비스가 초기화되지 않았습니다")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showEditSheet) {
            if let schedulerService {
                ScheduleEditSheet(
                    schedulerService: schedulerService,
                    editingSchedule: editingSchedule
                )
            }
        }
        .sheet(isPresented: $showTemplateSheet) {
            if let schedulerService {
                ScheduleTemplateSheet(schedulerService: schedulerService) { template in
                    showTemplateSheet = false
                    editingSchedule = ScheduleEntry(
                        name: template.name,
                        icon: template.icon,
                        cronExpression: template.cronExpression,
                        prompt: template.prompt
                    )
                    showEditSheet = true
                }
            }
        }
    }
}

// MARK: - ScheduleRowView

struct ScheduleRowView: View {
    let schedule: ScheduleEntry
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            scheduleIconView
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.name)
                    .font(.system(size: 13, weight: .medium))

                Text(schedule.repeatSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var scheduleIconView: some View {
        if schedule.icon.allSatisfy({ $0.isASCII }) && schedule.icon.count > 1 {
            Image(systemName: schedule.icon)
                .font(.title3)
        } else {
            Text(schedule.icon)
                .font(.title3)
        }
    }
}

// MARK: - ScheduleHistoryRowView

struct ScheduleHistoryRowView: View {
    let record: ScheduleExecutionRecord
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.caption)

                Text(record.scheduleName)
                    .font(.system(size: 12))

                Spacer()

                if let duration = record.duration {
                    Text(String(format: "%.1f초", duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(record.startedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            if isExpanded, let error = record.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 24)
            }
        }
    }

    private var statusIcon: String {
        switch record.status {
        case .running: return "clock"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .running: return .blue
        case .success: return .green
        case .failure: return .red
        }
    }
}
