import SwiftUI

// MARK: - ScheduleEditSheet

struct ScheduleEditSheet: View {
    var schedulerService: SchedulerServiceProtocol
    var editingSchedule: ScheduleEntry?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var icon: String = "clock"
    @State private var repeatType: RepeatType = .daily
    @State private var selectedHour: Int = 9
    @State private var selectedMinute: Int = 0
    @State private var selectedWeekdays: Set<Int> = [1] // Monday
    @State private var selectedDay: Int = 1
    @State private var customCron: String = ""
    @State private var prompt: String = ""
    @State private var agentName: String = "도치"
    @State private var isEnabled: Bool = true

    private var isEditing: Bool { editingSchedule != nil }

    private var cronExpression: String {
        switch repeatType {
        case .daily:
            return "\(selectedMinute) \(selectedHour) * * *"
        case .weekly:
            let days = selectedWeekdays.sorted().map(String.init).joined(separator: ",")
            return "\(selectedMinute) \(selectedHour) * * \(days)"
        case .monthly:
            return "\(selectedMinute) \(selectedHour) \(selectedDay) * *"
        case .custom:
            return customCron
        }
    }

    private var nextRunPreview: String? {
        guard let date = schedulerService.nextRunDate(for: cronExpression, after: Date()) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty &&
        CronExpression.parse(cronExpression) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "스케줄 편집" : "새 스케줄")
                    .font(.headline)
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("이름")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("스케줄 이름", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Repeat type
                    VStack(alignment: .leading, spacing: 8) {
                        Text("반복 유형")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("반복", selection: $repeatType) {
                            Text("매일").tag(RepeatType.daily)
                            Text("매주").tag(RepeatType.weekly)
                            Text("매월").tag(RepeatType.monthly)
                            Text("사용자 정의 (크론식)").tag(RepeatType.custom)
                        }
                        .pickerStyle(.segmented)

                        switch repeatType {
                        case .daily:
                            timePickerSection

                        case .weekly:
                            weekdayPickerSection
                            timePickerSection

                        case .monthly:
                            dayPickerSection
                            timePickerSection

                        case .custom:
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("크론 표현식 (분 시 일 월 요일)", text: $customCron)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))

                                if let next = nextRunPreview {
                                    Text("다음 실행: \(next)")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                } else if !customCron.isEmpty {
                                    Text("유효하지 않은 크론 표현식입니다")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }

                        // Next run preview for non-custom types
                        if repeatType != .custom, let next = nextRunPreview {
                            Text("다음 실행: \(next)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    Divider()

                    // Prompt
                    VStack(alignment: .leading, spacing: 4) {
                        Text("실행할 작업")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $prompt)
                            .font(.system(size: 13))
                            .frame(minHeight: 60, maxHeight: 120)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2))
                            )

                        Text("에이전트에게 보낼 메시지를 입력하세요")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Agent
                    VStack(alignment: .leading, spacing: 4) {
                        Text("에이전트")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("에이전트 이름", text: $agentName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Enable toggle
                    Toggle("활성화", isOn: $isEnabled)

                    Divider()

                    // Delete button for editing mode
                    if isEditing, let schedule = editingSchedule {
                        Button(role: .destructive) {
                            schedulerService.removeSchedule(id: schedule.id)
                            dismiss()
                        } label: {
                            Label("스케줄 삭제", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 420, height: 540)
        .onAppear {
            if let schedule = editingSchedule {
                name = schedule.name
                icon = schedule.icon
                prompt = schedule.prompt
                agentName = schedule.agentName
                isEnabled = schedule.isEnabled
                loadCronFields(from: schedule.cronExpression)
            }
        }
    }

    // MARK: - Pickers

    private var timePickerSection: some View {
        HStack(spacing: 8) {
            Text("시간")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("시", selection: $selectedHour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .frame(width: 70)
            Text(":")
            Picker("분", selection: $selectedMinute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .frame(width: 70)
        }
    }

    private var weekdayPickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("요일")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { day in
                    let dayName = shortWeekday(day)
                    Toggle(dayName, isOn: Binding(
                        get: { selectedWeekdays.contains(day) },
                        set: { isOn in
                            if isOn {
                                selectedWeekdays.insert(day)
                            } else if selectedWeekdays.count > 1 {
                                selectedWeekdays.remove(day)
                            }
                        }
                    ))
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
    }

    private var dayPickerSection: some View {
        HStack(spacing: 8) {
            Text("일자")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("일", selection: $selectedDay) {
                ForEach(1..<32, id: \.self) { d in
                    Text("\(d)일").tag(d)
                }
            }
            .frame(width: 80)
        }
    }

    // MARK: - Helpers

    private func shortWeekday(_ day: Int) -> String {
        switch day {
        case 0: return "일"
        case 1: return "월"
        case 2: return "화"
        case 3: return "수"
        case 4: return "목"
        case 5: return "금"
        case 6: return "토"
        default: return "?"
        }
    }

    private func loadCronFields(from cron: String) {
        guard let parsed = CronExpression.parse(cron) else {
            repeatType = .custom
            customCron = cron
            return
        }

        // Determine type from fields
        switch (parsed.dayOfMonth, parsed.dayOfWeek) {
        case (.any, .any):
            repeatType = .daily
        case (.any, _):
            repeatType = .weekly
            switch parsed.dayOfWeek {
            case .value(let d): selectedWeekdays = [d]
            case .list(let ds): selectedWeekdays = Set(ds)
            case .any: break
            }
        case (_, .any):
            repeatType = .monthly
            if case .value(let d) = parsed.dayOfMonth {
                selectedDay = d
            }
        default:
            repeatType = .custom
            customCron = cron
            return
        }

        if case .value(let h) = parsed.hour { selectedHour = h }
        if case .value(let m) = parsed.minute { selectedMinute = m }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespaces)

        if var existing = editingSchedule {
            existing.name = trimmedName
            existing.icon = icon
            existing.cronExpression = cronExpression
            existing.prompt = trimmedPrompt
            existing.agentName = agentName
            existing.isEnabled = isEnabled
            schedulerService.updateSchedule(existing)
        } else {
            let entry = ScheduleEntry(
                name: trimmedName,
                icon: icon,
                cronExpression: cronExpression,
                prompt: trimmedPrompt,
                agentName: agentName,
                isEnabled: isEnabled
            )
            schedulerService.addSchedule(entry)
        }
    }
}
