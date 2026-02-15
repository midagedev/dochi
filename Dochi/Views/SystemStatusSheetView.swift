import SwiftUI

/// 3-tab system status sheet showing LLM exchange history, heartbeat, and cloud sync.
struct SystemStatusSheetView: View {
    let metricsCollector: MetricsCollector
    let settings: AppSettings
    var heartbeatService: HeartbeatService?
    var supabaseService: SupabaseServiceProtocol?
    var syncEngine: SyncEngine?
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case llm = "LLM"
        case heartbeat = "하트비트"
        case cloud = "클라우드"
    }

    @State private var selectedTab: Tab = .llm

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("시스템 상태")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()
                .padding(.top, 8)

            // Tab content
            Group {
                switch selectedTab {
                case .llm:
                    LLMExchangeTabView(metricsCollector: metricsCollector, settings: settings)
                case .heartbeat:
                    HeartbeatTabView(heartbeatService: heartbeatService, settings: settings)
                case .cloud:
                    CloudSyncTabView(supabaseService: supabaseService, syncEngine: syncEngine)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - LLM Exchange Tab

private struct LLMExchangeTabView: View {
    let metricsCollector: MetricsCollector
    let settings: AppSettings

    private var summary: SessionMetricsSummary {
        metricsCollector.sessionSummary
    }

    var body: some View {
        if metricsCollector.recentMetrics.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                // Session summary
                summarySection

                Divider()

                // Exchange list
                List {
                    ForEach(Array(metricsCollector.recentMetrics.reversed().enumerated()), id: \.offset) { _, metrics in
                        exchangeRow(metrics)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("아직 LLM 교환 기록이 없습니다")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("대화를 시작하면 여기에 사용 현황이 표시됩니다.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summarySection: some View {
        HStack(spacing: 20) {
            summaryItem("교환 수", "\(summary.totalExchanges)")
            summaryItem("입력 토큰", formatTokens(summary.totalInputTokens))
            summaryItem("출력 토큰", formatTokens(summary.totalOutputTokens))
            summaryItem("평균 응답", String(format: "%.1f초", summary.averageLatency))
            if summary.fallbackCount > 0 {
                summaryItem("폴백", "\(summary.fallbackCount)회")
            }
        }
        .padding()
        .background(.secondary.opacity(0.04))
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func exchangeRow(_ metrics: ExchangeMetrics) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(metrics.model)
                        .font(.system(size: 12, weight: .medium))
                    if metrics.wasFallback {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                Text(metrics.provider)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(metrics.totalTokensDisplay + " 토큰")
                    .font(.system(size: 11, design: .monospaced))
                Text(String(format: "%.1f초", metrics.totalLatency))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(metrics.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

// MARK: - Heartbeat Tab

private struct HeartbeatTabView: View {
    let heartbeatService: HeartbeatService?
    let settings: AppSettings

    var body: some View {
        if let heartbeat = heartbeatService, settings.heartbeatEnabled {
            heartbeatContent(heartbeat)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("하트비트가 비활성화되어 있습니다")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("설정 → 프로액티브 에이전트에서 활성화할 수 있습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heartbeatContent(_ heartbeat: HeartbeatService) -> some View {
        VStack(spacing: 0) {
            // Status header
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(heartbeat.consecutiveErrors > 0 ? .red : .green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("하트비트 활성")
                        .font(.system(size: 13, weight: .medium))
                    Text("간격: \(settings.heartbeatIntervalMinutes)분")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let lastTick = heartbeat.lastTickDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("마지막 틱")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(lastTick, style: .relative)
                            .font(.system(size: 11))
                    }
                }
            }
            .padding()
            .background(.secondary.opacity(0.04))

            Divider()

            // Tick history
            if heartbeat.tickHistory.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("아직 틱 기록이 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("첫 번째 틱은 \(settings.heartbeatIntervalMinutes)분 후에 실행됩니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(Array(heartbeat.tickHistory.reversed().enumerated()), id: \.offset) { _, tick in
                        tickRow(tick)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func tickRow(_ tick: HeartbeatTickResult) -> some View {
        HStack {
            Circle()
                .fill(tick.error != nil ? .red : (tick.notificationSent ? .orange : .green))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(tick.checksPerformed.joined(separator: ", "))
                    .font(.system(size: 11))
                if let error = tick.error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                } else if tick.notificationSent {
                    Text("알림 발송 (\(tick.itemsFound)건)")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Text(tick.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Cloud Sync Tab

private struct CloudSyncTabView: View {
    let supabaseService: SupabaseServiceProtocol?
    var syncEngine: SyncEngine?

    @State private var showConflictSheet = false

    var body: some View {
        if let service = supabaseService, service.authState.isSignedIn {
            syncContent(service)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("클라우드 동기화가 연결되지 않았습니다")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("설정 → 클라우드에서 로그인하면 동기화가 시작됩니다.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncContent(_ service: SupabaseServiceProtocol) -> some View {
        VStack(spacing: 0) {
            // 상태 헤더
            statusHeader(service)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // 동기화 대상 요약
                    if let engine = syncEngine {
                        syncTargetSummary(engine)
                    }

                    // 충돌 섹션
                    if let engine = syncEngine, !engine.syncConflicts.isEmpty {
                        conflictSection(engine)
                    }

                    // 동기화 히스토리
                    if let engine = syncEngine {
                        historySection(engine)
                    }

                    // 동기화 버튼
                    syncButtons(service)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showConflictSheet) {
            if let engine = syncEngine {
                SyncConflictListView(
                    conflicts: engine.syncConflicts,
                    onResolve: { id, resolution in
                        engine.resolveConflict(id: id, resolution: resolution)
                    },
                    onResolveAll: { resolution in
                        engine.resolveAllConflicts(resolution: resolution)
                    }
                )
            }
        }
    }

    private func statusHeader(_ service: SupabaseServiceProtocol) -> some View {
        HStack(spacing: 12) {
            if let engine = syncEngine {
                Image(systemName: engine.syncState.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(syncStateColor(engine.syncState))
            } else {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                if case .signedIn(_, let email) = service.authState {
                    HStack(spacing: 6) {
                        Text("로그인됨")
                            .font(.system(size: 13, weight: .medium))
                        if let engine = syncEngine {
                            Text(engine.syncState.displayText)
                                .font(.system(size: 11))
                                .foregroundStyle(syncStateColor(engine.syncState))
                        }
                    }
                    if let email {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let engine = syncEngine, let lastSync = engine.lastSuccessfulSync {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("마지막 동기화")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(lastSync, style: .relative)
                        .font(.system(size: 11))
                }
            }
        }
        .padding()
        .background(.secondary.opacity(0.04))
    }

    private func syncTargetSummary(_ engine: SyncEngine) -> some View {
        let counts = engine.entityCounts()
        return VStack(alignment: .leading, spacing: 6) {
            Text("동기화 대상")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ForEach(SyncEntityType.allCases, id: \.self) { type in
                    HStack(spacing: 4) {
                        Image(systemName: type.iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(type.displayName) \(counts[type] ?? 0)건")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func conflictSection(_ engine: SyncEngine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
                Text("충돌 \(engine.syncConflicts.count)건")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("해결하기") {
                    showConflictSheet = true
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            ForEach(engine.syncConflicts.prefix(3)) { conflict in
                HStack(spacing: 6) {
                    Image(systemName: conflict.entityType.iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(conflict.entityTitle)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                }
            }

            if engine.syncConflicts.count > 3 {
                Text("외 \(engine.syncConflicts.count - 3)건...")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func historySection(_ engine: SyncEngine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("동기화 히스토리")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if engine.syncHistory.isEmpty {
                Text("아직 동기화 기록이 없습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(engine.syncHistory.prefix(10)) { entry in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(entry.success ? .green : .red)
                            .frame(width: 5, height: 5)
                        Image(systemName: entry.direction == .incoming ? "arrow.down" : "arrow.up")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(entry.entityTitle)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(entry.timestamp, style: .time)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func syncButtons(_ service: SupabaseServiceProtocol) -> some View {
        HStack(spacing: 12) {
            if let engine = syncEngine {
                Button {
                    Task { await engine.sync() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("수동 동기화")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(engine.syncState == .syncing)

                Button {
                    Task { await engine.fullSync() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.icloud")
                        Text("전체 동기화")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(engine.syncState == .syncing)
            } else {
                Button {
                    Task {
                        try? await service.syncContext()
                        try? await service.syncConversations()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("수동 동기화")
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    private func syncStateColor(_ state: SyncState) -> Color {
        switch state {
        case .idle: .green
        case .syncing: .blue
        case .conflict: .orange
        case .error: .red
        case .offline: .gray
        case .disabled: .gray
        }
    }
}
