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
                Toggle("알림 센터에 제안 표시", isOn: Binding(
                    get: { settings.notificationProactiveSuggestionEnabled },
                    set: { settings.notificationProactiveSuggestionEnabled = $0 }
                ))

                Toggle("메뉴바에 제안 표시", isOn: Binding(
                    get: { settings.proactiveSuggestionMenuBarEnabled },
                    set: { settings.proactiveSuggestionMenuBarEnabled = $0 }
                ))
            }
            .disabled(!settings.proactiveSuggestionEnabled)

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
}
