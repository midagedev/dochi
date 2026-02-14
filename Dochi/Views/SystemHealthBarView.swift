import SwiftUI

/// Always-visible bar at the top of the chat area showing system health indicators.
struct SystemHealthBarView: View {
    let settings: AppSettings
    let metricsCollector: MetricsCollector
    var heartbeatService: HeartbeatService?
    var supabaseService: SupabaseServiceProtocol?
    let onTap: () -> Void

    private var sessionSummary: SessionMetricsSummary {
        metricsCollector.sessionSummary
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 0) {
                // 1. Current model
                indicator {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(settings.llmModel)
                            .lineLimit(1)
                    }
                }

                divider

                // 2. Cloud sync status
                if let supabase = supabaseService, supabase.authState.isSignedIn {
                    indicator {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(syncStatusColor(for: supabase))
                                .frame(width: 6, height: 6)
                            Text("동기화")
                        }
                    }

                    divider
                }

                // 3. Heartbeat status
                if let heartbeat = heartbeatService, settings.heartbeatEnabled {
                    indicator {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(heartbeatColor(for: heartbeat))
                            if let lastTick = heartbeat.lastTickDate {
                                Text(lastTick, style: .relative)
                            } else {
                                Text("대기")
                            }
                        }
                    }

                    divider
                }

                // 4. Session token usage
                indicator {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        if sessionSummary.totalExchanges > 0 {
                            Text("\(formatTokens(sessionSummary.totalInputTokens + sessionSummary.totalOutputTokens)) 토큰")
                        } else {
                            Text("0 토큰")
                        }
                    }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
        .help("시스템 상태 (⌘⇧S)")
    }

    // MARK: - Helpers

    private func indicator<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 14)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private func syncStatusColor(for service: SupabaseServiceProtocol) -> Color {
        switch service.authState {
        case .signedIn: return .green
        case .signedOut: return .red
        case .signingIn: return .yellow
        }
    }

    private func heartbeatColor(for service: HeartbeatService) -> Color {
        if service.consecutiveErrors > 0 {
            return .red
        }
        guard let lastTick = service.lastTickDate else {
            return .secondary
        }
        let elapsed = Date().timeIntervalSince(lastTick)
        let expectedInterval = Double(settings.heartbeatIntervalMinutes * 60)
        if elapsed < expectedInterval * 1.5 {
            return .green
        } else {
            return .orange
        }
    }
}
