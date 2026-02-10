import SwiftUI

struct AppToolbar: View {
    @EnvironmentObject var viewModel: DochiViewModel

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            connectionToggle

            if viewModel.isConnected {
                if isWakeWordActive {
                    WakeWordIndicator(wakeWord: viewModel.settings.wakeWord)
                } else {
                    Text(stateLabel)
                        .compact(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Agent / Model / Workspace quick chips
            agentModelWorkspace

            Spacer(minLength: 8)

            if let error = currentError { Text(error).compact(AppFont.caption).foregroundStyle(.red).lineLimit(1).minimumScaleFactor(0.8) }

            Spacer()

            if let _ = viewModel.actualContextUsage { contextUsageIndicator }

            if viewModel.isConnected { autoEndToggle }

            if isResponding { voiceIndicator }

            if !viewModel.builtInToolService.activeAlarms.isEmpty { inlineAlarms }
        }
        .padding(.horizontal)
        .padding(.vertical, verticalPadding)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.border).frame(height: 1) }
        .frame(height: barHeight)
    }

    // MARK: - Subviews

    private var connectionToggle: some View {
        Button { viewModel.toggleConnection() } label: {
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(connectionLabel).compact(AppFont.caption)
            }
        }
        .buttonStyle(.borderless)
    }

    private var autoEndToggle: some View {
        Button { viewModel.autoEndSession.toggle() } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: viewModel.autoEndSession ? "timer" : "timer.circle")
                    .font(.caption)
                Text("자동종료").compact(AppFont.caption)
            }
            .foregroundStyle(viewModel.autoEndSession ? .primary : .tertiary)
        }
        .buttonStyle(.borderless)
        .help(viewModel.autoEndSession ? "자동종료 켜짐: 무응답 시 대화 종료" : "자동종료 꺼짐: 무응답 시 계속 듣기")
    }

    private var voiceIndicator: some View {
        HStack(spacing: AppSpacing.xs) {
            AudioBarsView()
            Text("응답 중").compact(AppFont.caption).foregroundStyle(.blue)
        }
        .frame(height: 16)
    }

    // MARK: - Helpers

    private var agentModelWorkspace: some View {
            HStack(spacing: AppSpacing.s) {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill").foregroundStyle(.blue)
                    Text(viewModel.settings.activeAgentName).compact(AppFont.caption).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())

                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile").foregroundStyle(.purple)
                    Text("\(viewModel.settings.llmProvider.displayName)/\(viewModel.settings.llmModel)")
                        .compact(AppFont.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())

                if let supabase = viewModel.supabaseServiceForView, case .signedIn(_, _) = supabase.authState, let ws = supabase.selectedWorkspace {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill").foregroundStyle(.teal)
                        Text(ws.name).compact(AppFont.caption).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
    }

    private var connectionColor: Color {
        switch viewModel.supertonicService.state {
        case .unloaded: return .red
        case .loading: return .yellow
        case .ready:
            switch viewModel.state {
            case .idle: return .green
            case .listening: return .orange
            case .processing: return .blue
            case .executingTool: return .cyan
            case .speaking: return .purple
            }
        case .synthesizing: return .blue
        case .playing: return .purple
        }
    }

    private var connectionLabel: String {
        switch viewModel.supertonicService.state {
        case .unloaded: return "연결"
        case .loading: return "로딩 중..."
        case .ready, .synthesizing, .playing: return "연결됨"
        }
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle: return "대기 중"
        case .listening: return "듣는 중..."
        case .processing: return "응답 생성 중..."
        case .executingTool(let name): return "\(name) 실행 중..."
        case .speaking: return "음성 재생 중..."
        }
    }

    private var currentError: String? {
        viewModel.errorMessage ?? viewModel.llmService.error ?? viewModel.supertonicService.error
    }

    private var isWakeWordActive: Bool {
        viewModel.speechService.state == .waitingForWakeWord
    }

    private var isResponding: Bool {
        switch viewModel.state {
        case .processing, .executingTool, .speaking: return true
        case .idle, .listening: return false
        }
    }

    private var contextUsageIndicator: some View {
        let info = viewModel.actualContextUsage!
        return HStack(spacing: AppSpacing.xs) {
            Image(systemName: "gauge")
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(info.percent < 0.8 ? Color.blue.opacity(0.6) : (info.percent < 1.0 ? Color.orange.opacity(0.7) : Color.red.opacity(0.7)))
                    .frame(width: max(0, CGFloat(info.percent)) * 90)
            }
            .frame(width: 90, height: 8)
            Text("\(Int(info.percent * 100))%")
                .compact(AppFont.caption.monospacedDigit())
                .foregroundStyle(info.percent < 0.8 ? Color.secondary : (info.percent < 1.0 ? Color.orange : Color.red))
        }
        .accessibilityIdentifier("indicator.contextUsage")
    }

    private var inlineAlarms: some View {
        HStack(spacing: 6) {
            Image(systemName: "alarm.fill").foregroundStyle(.orange).font(.caption)
            ForEach(viewModel.builtInToolService.activeAlarms) { alarm in
                HStack(spacing: 4) {
                    Text(alarm.label).compact(AppFont.caption)
                    Text(remainingText(alarm.fireDate))
                        .compact(AppFont.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.orange.opacity(0.1), in: Capsule())
            }
        }
    }

    private func remainingText(_ fireDate: Date) -> String {
        let remaining = max(0, Int(fireDate.timeIntervalSinceNow))
        if remaining >= 3600 {
            let h = remaining / 3600
            let m = (remaining % 3600) / 60
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", remaining % 60))"
        } else if remaining >= 60 {
            let m = remaining / 60
            let s = remaining % 60
            return "\(m):\(String(format: "%02d", s))"
        } else {
            return "\(remaining)초"
        }
    }

    private var verticalPadding: CGFloat { AppSpacing.xs }
    private var barHeight: CGFloat { 34 }
}
