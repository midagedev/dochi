import SwiftUI

struct ReminderListItem: Equatable {
    let title: String
    let dueDateText: String?
    let isCompleted: Bool
}

enum ReminderListParser {
    static func parse(content: String) -> [ReminderListItem] {
        if content.contains("목록에 미리알림이 없습니다") {
            return []
        }

        let lines = content
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        let reminderLines: ArraySlice<String>
        if let first = lines.first, first.contains("목록:") {
            reminderLines = lines.dropFirst()
        } else {
            reminderLines = ArraySlice(lines)
        }

        return reminderLines.compactMap(parseLine(_:))
    }

    private static func parseLine(_ rawLine: String) -> ReminderListItem? {
        var text = rawLine
        let completedPrefix = "[완료] "
        let isCompleted = text.hasPrefix(completedPrefix)
        if isCompleted {
            text.removeFirst(completedPrefix.count)
        }

        var title = text
        var dueDateText: String?

        if text.hasSuffix(")"), let dueStart = text.range(of: " (마감: ", options: .backwards) {
            title = String(text[..<dueStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = dueStart.upperBound
            let end = text.index(before: text.endIndex)
            dueDateText = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !title.isEmpty else { return nil }
        return ReminderListItem(title: title, dueDateText: dueDateText, isCompleted: isCompleted)
    }
}

struct RemindersWorkspaceView: View {
    @State private var listName = "미리알림"
    @State private var showCompleted = false
    @State private var reminders: [ReminderListItem] = []
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var completingReminderTitle: String?
    @State private var messageText: String?
    @State private var errorText: String?

    @State private var newReminderTitle = ""
    @State private var newReminderDueDate = ""
    @State private var newReminderNotes = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorText {
                inlineBanner(message: errorText, color: .red, iconName: "exclamationmark.triangle.fill")
            } else if let messageText {
                inlineBanner(message: messageText, color: .secondary, iconName: "info.circle")
            }

            remindersList

            Divider()

            createReminderForm
        }
        .onAppear {
            Task { await refreshReminders() }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Label("미리알림", systemImage: "checklist")
                .font(.system(size: 15, weight: .semibold))

            TextField("목록 이름", text: $listName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 180)

            Toggle("완료 포함", isOn: $showCompleted)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button("새로고침") {
                Task { await refreshReminders() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var remindersList: some View {
        if isLoading && reminders.isEmpty {
            VStack {
                Spacer()
                ProgressView("미리알림 불러오는 중...")
                    .controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if reminders.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "checklist")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text("표시할 미리알림이 없습니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("우측 하단에서 새 미리알림을 추가할 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(reminders.enumerated()), id: \.offset) { _, reminder in
                    HStack(spacing: 8) {
                        Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(reminder.isCompleted ? .green : .secondary)
                            .font(.system(size: 12))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                                .font(.system(size: 13, weight: .medium))
                                .strikethrough(reminder.isCompleted)
                            if let dueDateText = reminder.dueDateText {
                                Text("마감: \(dueDateText)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if !reminder.isCompleted {
                            Button {
                                Task { await completeReminder(title: reminder.title) }
                            } label: {
                                Text("완료")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(completingReminderTitle == reminder.title)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private var createReminderForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("새 미리알림")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("제목", text: $newReminderTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                TextField("마감일 (선택)", text: $newReminderDueDate)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 220)
            }

            HStack(spacing: 8) {
                TextField("메모 (선택)", text: $newReminderNotes)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("추가") {
                    Task { await createReminder() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isCreating || newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func inlineBanner(message: String, color: Color, iconName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(color)
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer()
            Button {
                messageText = nil
                errorText = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
    }

    @MainActor
    private func refreshReminders() async {
        let normalizedList = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedList.isEmpty {
            listName = "미리알림"
        }

        isLoading = true
        defer { isLoading = false }

        let result = await ListRemindersTool().execute(arguments: [
            "list_name": listName,
            "show_completed": showCompleted,
        ])
        if result.isError {
            reminders = []
            errorText = result.content
            messageText = nil
            return
        }

        reminders = ReminderListParser.parse(content: result.content)
        errorText = nil
        if reminders.isEmpty {
            messageText = "'\(listName)' 목록에 미리알림이 없습니다."
        } else {
            messageText = nil
        }
    }

    @MainActor
    private func createReminder() async {
        let title = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isCreating = true
        defer { isCreating = false }

        var arguments: [String: Any] = [
            "title": title,
            "list_name": listName,
        ]
        let dueDate = newReminderDueDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dueDate.isEmpty {
            arguments["due_date"] = dueDate
        }
        let notes = newReminderNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            arguments["notes"] = notes
        }

        let result = await CreateReminderTool().execute(arguments: arguments)
        if result.isError {
            errorText = result.content
            messageText = nil
            return
        }

        newReminderTitle = ""
        newReminderDueDate = ""
        newReminderNotes = ""
        errorText = nil
        messageText = result.content
        await refreshReminders()
    }

    @MainActor
    private func completeReminder(title: String) async {
        completingReminderTitle = title
        defer { completingReminderTitle = nil }

        let result = await CompleteReminderTool().execute(arguments: [
            "title": title,
        ])
        if result.isError {
            errorText = result.content
            messageText = nil
            return
        }

        errorText = nil
        messageText = result.content
        await refreshReminders()
    }
}
