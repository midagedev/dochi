import SwiftUI
import OSLog

struct LogViewerView: View {
    @State private var viewModel = LogViewerViewModel()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logTable
            Divider()
            statusBar
        }
        .frame(minWidth: 800, minHeight: 400)
        .onAppear {
            viewModel.fetchLogs()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("카테고리", selection: $viewModel.selectedCategory) {
                Text("전체 카테고리").tag(nil as String?)
                Divider()
                ForEach(Log.allCategories, id: \.self) { cat in
                    Text(cat).tag(cat as String?)
                }
            }
            .frame(width: 160)

            Picker("레벨", selection: $viewModel.selectedLevel) {
                Text("전체 레벨").tag(nil as OSLogEntryLog.Level?)
                Divider()
                Text("debug").tag(OSLogEntryLog.Level.debug as OSLogEntryLog.Level?)
                Text("info").tag(OSLogEntryLog.Level.info as OSLogEntryLog.Level?)
                Text("notice").tag(OSLogEntryLog.Level.notice as OSLogEntryLog.Level?)
                Text("error").tag(OSLogEntryLog.Level.error as OSLogEntryLog.Level?)
                Text("fault").tag(OSLogEntryLog.Level.fault as OSLogEntryLog.Level?)
            }
            .frame(width: 130)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("검색...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Toggle("실시간", isOn: $viewModel.isAutoRefresh)
                .toggleStyle(.checkbox)

            Button {
                viewModel.fetchLogs()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("새로고침")

            Button {
                viewModel.copyEntries()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("필터된 로그 복사")
            .disabled(viewModel.filteredEntries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Log Table

    private var logTable: some View {
        Table(viewModel.filteredEntries) {
            TableColumn("시간") { entry in
                Text(Self.timeFormatter.string(from: entry.date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 100, max: 120)

            TableColumn("카테고리") { entry in
                Text(entry.category)
                    .font(.system(size: 11, design: .monospaced))
                    .fontWeight(.medium)
            }
            .width(min: 60, ideal: 80, max: 100)

            TableColumn("레벨") { entry in
                Text(entry.levelLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(colorForLevel(entry.level))
            }
            .width(min: 50, ideal: 60, max: 80)

            TableColumn("메시지") { entry in
                Text(entry.composedMessage)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("항목 \(viewModel.filteredEntries.count)개")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if let lastRefresh = viewModel.lastRefreshDate {
                Text("마지막 갱신: \(Self.timeFormatter.string(from: lastRefresh))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func colorForLevel(_ level: OSLogEntryLog.Level) -> Color {
        switch level {
        case .debug: .gray
        case .info: .primary
        case .notice: .blue
        case .error: .orange
        case .fault: .red
        default: .primary
        }
    }
}
