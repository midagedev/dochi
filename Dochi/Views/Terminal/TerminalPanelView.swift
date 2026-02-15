import SwiftUI

/// 하단 터미널 패널 컨테이너: 탭 바 + 세션 뷰 + 액션 버튼
struct TerminalPanelView: View {
    var terminalService: TerminalServiceProtocol
    var settings: AppSettings

    @State private var inputText: String = ""

    private var activeSession: TerminalSession? {
        guard let activeId = terminalService.activeSessionId else { return nil }
        return terminalService.sessions.first(where: { $0.id == activeId })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            Divider()

            // Session content
            if let session = activeSession {
                TerminalSessionView(
                    session: session,
                    fontSize: CGFloat(settings.terminalFontSize),
                    inputText: $inputText,
                    onSubmit: { command in
                        terminalService.executeCommand(command, in: session.id)
                        inputText = ""
                    },
                    onHistoryUp: {
                        if let text = terminalService.navigateHistory(sessionId: session.id, direction: -1) {
                            inputText = text
                        }
                    },
                    onHistoryDown: {
                        if let text = terminalService.navigateHistory(sessionId: session.id, direction: 1) {
                            inputText = text
                        }
                    },
                    onInterrupt: {
                        terminalService.interrupt(sessionId: session.id)
                    }
                )
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(terminalService.sessions) { session in
                        tabItem(for: session)
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            // Actions
            HStack(spacing: 4) {
                if terminalService.sessions.count < terminalService.maxSessions {
                    Button {
                        terminalService.createSession(
                            name: nil,
                            shellPath: settings.terminalShellPath
                        )
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("새 세션 (Ctrl+Shift+`)")
                }

                if let activeId = terminalService.activeSessionId {
                    Button {
                        terminalService.clearOutput(for: activeId)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("출력 지우기 (Cmd+L)")
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
        .background(.bar)
    }

    @ViewBuilder
    private func tabItem(for session: TerminalSession) -> some View {
        let isActive = terminalService.activeSessionId == session.id

        HStack(spacing: 4) {
            Circle()
                .fill(session.isRunning ? Color.green : Color.red)
                .frame(width: 6, height: 6)

            Text(session.name)
                .font(.system(size: 11))
                .lineLimit(1)

            Button {
                terminalService.closeSession(id: session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            terminalService.activeSessionId = session.id
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("터미널 세션이 없습니다")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("새 세션 시작") {
                terminalService.createSession(
                    name: nil,
                    shellPath: settings.terminalShellPath
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
