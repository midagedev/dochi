import SwiftUI

/// 개별 터미널 세션 뷰: 출력 ScrollView + 입력 라인
struct TerminalSessionView: View {
    let session: TerminalSession
    var fontSize: CGFloat = 14
    @Binding var inputText: String
    var onSubmit: (String) -> Void
    var onHistoryUp: () -> Void
    var onHistoryDown: () -> Void
    var onInterrupt: () -> Void

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(session.outputLines) { line in
                            outputLineView(line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: session.outputLines.count) { _, _ in
                    if let lastId = session.outputLines.last?.id {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            // Input line
            inputLine
        }
    }

    // MARK: - Output Line

    @ViewBuilder
    private func outputLineView(_ line: TerminalOutputLine) -> some View {
        Text(line.text)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(colorForType(line.type))
            .italic(line.type == .system)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorForType(_ type: OutputType) -> Color {
        switch type {
        case .stdout:
            return Color.primary
        case .stderr:
            return Color.red
        case .system:
            return Color.secondary
        case .llmCommand:
            return Color.purple
        case .llmPrompt:
            return Color.purple.opacity(0.7)
        }
    }

    // MARK: - Input Line

    @ViewBuilder
    private var inputLine: some View {
        HStack(spacing: 6) {
            Text(session.isRunning ? ">" : "[종료]")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(session.isRunning ? Color.green : Color.red)

            TextField("명령 입력...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, design: .monospaced))
                .focused($isInputFocused)
                .disabled(!session.isRunning)
                .onSubmit {
                    let command = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !command.isEmpty {
                        onSubmit(command)
                    }
                }
                .onKeyPress(.upArrow) {
                    onHistoryUp()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onHistoryDown()
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    // Ctrl+C to interrupt
                    if press.modifiers.contains(.control) && press.characters == "c" {
                        onInterrupt()
                        return .handled
                    }
                    return .ignored
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            isInputFocused = true
        }
    }
}
