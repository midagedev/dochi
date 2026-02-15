import SwiftUI

// MARK: - ShortcutsSettingsView

struct ShortcutsSettingsView: View {
    @State private var executionLogs: [ShortcutExecutionLog] = []

    var body: some View {
        Form {
            shortcutsStatusSection
            actionsSection
            executionLogSection
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadLogs()
        }
    }

    // MARK: - Shortcuts Status Section

    @ViewBuilder
    private var shortcutsStatusSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                Text("Apple Shortcuts 연동이 활성화되어 있습니다")
                    .font(.system(size: 13))
            }

            Text("도치의 기능을 macOS 단축어 앱과 Siri에서 사용할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    openShortcutsApp()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.3x3.square")
                            .font(.system(size: 11))
                        Text("단축어 앱 열기")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openSiriSettings()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.circle")
                            .font(.system(size: 11))
                        Text("Siri 설정 열기")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } header: {
            SettingsSectionHeader(
                title: "Shortcuts 연동",
                helpContent: "AppIntents 프레임워크를 통해 도치의 기능이 macOS 단축어 앱에 자동으로 등록됩니다. Siri에게 등록된 문구를 말하면 바로 실행할 수 있습니다."
            )
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            ShortcutActionCard(
                icon: "bubble.left.and.bubble.right",
                iconColor: .blue,
                title: "도치에게 물어보기",
                description: "자유로운 질문에 AI가 답변합니다",
                siriPhrase: "\"도치에게 물어보기\""
            )

            ShortcutActionCard(
                icon: "note.text",
                iconColor: .orange,
                title: "도치 메모 추가",
                description: "메모리에 메모를 저장합니다",
                siriPhrase: "\"도치 메모 추가\""
            )

            ShortcutActionCard(
                icon: "rectangle.3.group",
                iconColor: .purple,
                title: "도치 칸반 카드 생성",
                description: "칸반 보드에 새 카드를 추가합니다",
                siriPhrase: "\"도치 칸반 카드 생성\""
            )

            ShortcutActionCard(
                icon: "sun.max",
                iconColor: .yellow,
                title: "도치 오늘 브리핑",
                description: "오늘의 일정과 할 일을 요약합니다",
                siriPhrase: "\"도치 오늘 브리핑\""
            )
        } header: {
            SettingsSectionHeader(
                title: "사용 가능한 액션",
                helpContent: "아래 4가지 액션을 단축어 앱에서 조합하거나, Siri 문구로 바로 실행할 수 있습니다."
            )
        }
    }

    // MARK: - Execution Log Section

    @ViewBuilder
    private var executionLogSection: some View {
        Section {
            if executionLogs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text("아직 실행 기록이 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("단축어나 Siri로 도치 액션을 실행하면 여기에 기록됩니다")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(executionLogs.prefix(10)) { log in
                    ShortcutExecutionLogRow(log: log)
                }
            }
        } header: {
            HStack {
                SettingsSectionHeader(
                    title: "최근 실행 기록",
                    helpContent: "Shortcuts 또는 Siri를 통해 실행된 도치 액션의 기록입니다. 최대 50건까지 저장되며, 여기에는 최근 10건이 표시됩니다."
                )
                Spacer()
                if !executionLogs.isEmpty {
                    Button {
                        loadLogs()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("새로고침")
                }
            }
        }
    }

    // MARK: - Actions

    private func openShortcutsApp() {
        NSWorkspace.shared.open(URL(string: "shortcuts://")!)
    }

    private func openSiriSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.Siri")!)
    }

    private func loadLogs() {
        Task { @MainActor in
            executionLogs = DochiShortcutService.shared.loadExecutionLogs()
        }
    }
}

// MARK: - ShortcutActionCard

struct ShortcutActionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let siriPhrase: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "mic.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                    Text("Siri: \(siriPhrase)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.blue.opacity(0.8))
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ShortcutExecutionLogRow

struct ShortcutExecutionLogRow: View {
    let log: ShortcutExecutionLog

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }

    var body: some View {
        HStack(spacing: 8) {
            // Success/failure badge
            Image(systemName: log.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(log.success ? .green : .red)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(log.actionName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(log.resultSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let error = log.errorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(timeFormatter.string(from: log.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
