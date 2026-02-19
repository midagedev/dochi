import SwiftUI

/// K-2: 프로액티브 제안 설정 뷰
struct ProactiveSuggestionSettingsView: View {
    var settings: AppSettings
    var proactiveSuggestionService: ProactiveSuggestionServiceProtocol?

    @State private var showHistoryPopover = false

    var body: some View {
        Form {
            // MARK: - Master Toggle
            Section {
                Toggle("프로액티브 제안 활성화", isOn: Binding(
                    get: { settings.proactiveSuggestionEnabled },
                    set: { settings.proactiveSuggestionEnabled = $0 }
                ))

                Text("유휴 시간 동안 컨텍스트를 분석하여 유용한 제안을 생성합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(
                    title: "프로액티브 제안",
                    helpContent: "사용자가 일정 시간 비활성 상태이면, 최근 대화와 메모리를 분석하여 도움이 될 수 있는 제안을 자동으로 생성합니다. 제안은 대화 영역에 버블로 표시됩니다."
                )
            }

            // MARK: - Type Toggles
            Section("제안 유형") {
                typeToggle(
                    icon: "newspaper",
                    color: .blue,
                    label: "트렌드",
                    description: "뉴스/트렌드 관련 제안",
                    isOn: Binding(
                        get: { settings.suggestionTypeNewsEnabled },
                        set: { settings.suggestionTypeNewsEnabled = $0 }
                    )
                )

                typeToggle(
                    icon: "text.book.closed",
                    color: .purple,
                    label: "심층 탐구",
                    description: "이전 대화 주제에 대한 심화 설명 제안",
                    isOn: Binding(
                        get: { settings.suggestionTypeDeepDiveEnabled },
                        set: { settings.suggestionTypeDeepDiveEnabled = $0 }
                    )
                )

                typeToggle(
                    icon: "doc.text.magnifyingglass",
                    color: .teal,
                    label: "관련 리서치",
                    description: "관련 자료 조사 제안",
                    isOn: Binding(
                        get: { settings.suggestionTypeResearchEnabled },
                        set: { settings.suggestionTypeResearchEnabled = $0 }
                    )
                )

                typeToggle(
                    icon: "checklist",
                    color: .orange,
                    label: "칸반 점검",
                    description: "칸반 보드 진행 상황 체크 제안",
                    isOn: Binding(
                        get: { settings.suggestionTypeKanbanEnabled },
                        set: { settings.suggestionTypeKanbanEnabled = $0 }
                    )
                )

                typeToggle(
                    icon: "brain",
                    color: .green,
                    label: "메모리 리마인드",
                    description: "저장된 메모리 기반 리마인드 제안",
                    isOn: Binding(
                        get: { settings.suggestionTypeMemoryEnabled },
                        set: { settings.suggestionTypeMemoryEnabled = $0 }
                    )
                )

                typeToggle(
                    icon: "chart.bar",
                    color: .red,
                    label: "비용 리포트",
                    description: "API 사용량 및 비용 관련 제안",
                    isOn: Binding(
                        get: { settings.suggestionTypeCostEnabled },
                        set: { settings.suggestionTypeCostEnabled = $0 }
                    )
                )
            }
            .disabled(!settings.proactiveSuggestionEnabled)

            // MARK: - Timing Settings
            Section("타이밍") {
                HStack {
                    Text("유휴 시간: \(settings.proactiveSuggestionIdleMinutes)분")
                    Slider(
                        value: Binding(
                            get: { Double(settings.proactiveSuggestionIdleMinutes) },
                            set: { settings.proactiveSuggestionIdleMinutes = Int($0.rounded()) }
                        ),
                        in: 5...120,
                        step: 5
                    )
                }

                Text("사용자가 이 시간 동안 비활성이면 제안을 생성합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("쿨다운: \(settings.proactiveSuggestionCooldownMinutes)분")
                    Slider(
                        value: Binding(
                            get: { Double(settings.proactiveSuggestionCooldownMinutes) },
                            set: { settings.proactiveSuggestionCooldownMinutes = Int($0.rounded()) }
                        ),
                        in: 10...240,
                        step: 10
                    )
                }

                Text("제안 후 이 시간 동안 새 제안을 생성하지 않습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper(
                    value: Binding(
                        get: { settings.proactiveDailyCap },
                        set: { settings.proactiveDailyCap = min(max($0, 0), 20) }
                    ),
                    in: 0...20
                ) {
                    Text("일일 제안 한도: \(settings.proactiveDailyCap)개")
                }

                Text("하루 생성 가능한 제안 수를 제한합니다. 0이면 제안을 생성하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("조용한 시간 적용", isOn: Binding(
                    get: { settings.proactiveSuggestionQuietHoursEnabled },
                    set: { settings.proactiveSuggestionQuietHoursEnabled = $0 }
                ))

                if settings.proactiveSuggestionQuietHoursEnabled {
                    Text("하트비트 설정의 조용한 시간(\(settings.heartbeatQuietHoursStart):00~\(settings.heartbeatQuietHoursEnd):00)을 공유합니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.proactiveSuggestionEnabled)

            // MARK: - Notification Settings
            Section("알림") {
                Picker("제안 전달 채널", selection: Binding(
                    get: { NotificationChannel(rawValue: settings.suggestionNotificationChannel) ?? .off },
                    set: { settings.suggestionNotificationChannel = $0.rawValue }
                )) {
                    ForEach(NotificationChannel.allCases, id: \.self) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
                .pickerStyle(.segmented)

                Text("앱만/텔레그램만/둘 다/끄기 중 하나의 정책으로 제안 전달 경로를 단일 제어합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("메뉴바에 제안 표시", isOn: Binding(
                    get: { settings.proactiveSuggestionMenuBarEnabled },
                    set: { settings.proactiveSuggestionMenuBarEnabled = $0 }
                ))

                let channel = NotificationChannel(rawValue: settings.suggestionNotificationChannel) ?? .off
                if channel != .off || settings.proactiveSuggestionMenuBarEnabled {
                    Text("새 제안이 생성되면 선택한 채널 정책과 메뉴바 카드 설정에 따라 노출됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.proactiveSuggestionEnabled)

            Section("유휴자원 연동") {
                HStack {
                    Text("Git 스캔 자동작업")
                    Spacer()
                    Text(gitScanAutomationStatusLabel)
                        .font(.caption)
                        .foregroundStyle(gitScanAutomationStatusColor)
                }

                Text(gitScanAutomationStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Service Status
            if let service = proactiveSuggestionService {
                Section("상태") {
                    HStack {
                        Text("서비스 상태")
                        Spacer()
                        stateIndicator(service.state)
                    }

                    if service.isPaused {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("일시 중지됨")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("제안 기록")
                        Spacer()
                        Text("\(service.suggestionHistory.count)건")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - History
            Section("제안 기록") {
                if let service = proactiveSuggestionService, !service.suggestionHistory.isEmpty {
                    ForEach(service.suggestionHistory) { suggestion in
                        HStack(spacing: 8) {
                            Image(systemName: suggestion.type.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Text(suggestion.type.displayName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)

                                    Text(suggestion.timestamp, style: .relative)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            statusBadge(suggestion.status)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("아직 생성된 제안이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func typeToggle(icon: String, color: Color, label: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading) {
                Toggle(label, isOn: isOn)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stateIndicator(_ state: ProactiveSuggestionState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor(state))
                .frame(width: 8, height: 8)
            Text(stateLabel(state))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stateColor(_ state: ProactiveSuggestionState) -> Color {
        switch state {
        case .disabled: return .gray
        case .idle: return .green
        case .analyzing: return .blue
        case .hasSuggestion: return .yellow
        case .cooldown: return .orange
        case .error: return .red
        }
    }

    private func stateLabel(_ state: ProactiveSuggestionState) -> String {
        switch state {
        case .disabled: return "비활성"
        case .idle: return "대기 중"
        case .analyzing: return "분석 중..."
        case .hasSuggestion: return "제안 표시 중"
        case .cooldown: return "쿨다운"
        case .error(let msg): return "오류: \(msg)"
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: SuggestionStatus) -> some View {
        Text(statusLabel(status))
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusLabel(_ status: SuggestionStatus) -> String {
        switch status {
        case .shown: return "표시됨"
        case .accepted: return "수락"
        case .deferred: return "나중에"
        case .dismissed: return "거절"
        }
    }

    private func statusColor(_ status: SuggestionStatus) -> Color {
        switch status {
        case .shown: return .blue
        case .accepted: return .green
        case .deferred: return .orange
        case .dismissed: return .red
        }
    }

    private var gitScanAutomationEnabled: Bool {
        settings.resourceAutoTaskEnabled
            && settings.resourceAutoTaskTypes.contains(AutoTaskType.gitScanReview.rawValue)
    }

    private var gitScanAutomationStatusLabel: String {
        if gitScanAutomationEnabled {
            return "활성"
        }
        if settings.resourceAutoTaskEnabled {
            return "부분 활성"
        }
        return "비활성"
    }

    private var gitScanAutomationStatusColor: Color {
        if gitScanAutomationEnabled {
            return .green
        }
        if settings.resourceAutoTaskEnabled {
            return .orange
        }
        return .secondary
    }

    private var gitScanAutomationStatusDescription: String {
        if gitScanAutomationEnabled {
            return "유휴 시간 평가 시 Git 변경셋이 감지되면 스캔 리뷰 자동작업이 큐잉됩니다."
        }
        if settings.resourceAutoTaskEnabled {
            return "사용량 > 자동 작업 설정에서 \"Git 스캔 리뷰\" 유형을 켜면 연동됩니다."
        }
        return "사용량 > 자동 작업 설정을 활성화하면 프로액티브와 유휴자원 자동작업이 연동됩니다."
    }
}
