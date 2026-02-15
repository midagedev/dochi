import SwiftUI
import UserNotifications

// MARK: - SettingsView (NavigationSplitView)

struct SettingsView: View {
    var settings: AppSettings
    var keychainService: KeychainServiceProtocol
    var contextService: ContextServiceProtocol?
    var sessionContext: SessionContext?
    var ttsService: TTSServiceProtocol?
    var downloadManager: ModelDownloadManager?
    var telegramService: TelegramServiceProtocol?
    var mcpService: MCPServiceProtocol?
    var supabaseService: SupabaseServiceProtocol?
    var toolService: BuiltInToolService?
    var devicePolicyService: DevicePolicyServiceProtocol?
    var schedulerService: SchedulerServiceProtocol?
    var heartbeatService: HeartbeatService?
    var notificationManager: NotificationManager?
    var metricsCollector: MetricsCollector?
    var viewModel: DochiViewModel?
    var pluginManager: PluginManagerProtocol?
    var documentIndexer: DocumentIndexer?
    var feedbackStore: FeedbackStoreProtocol?
    var resourceOptimizer: (any ResourceOptimizerProtocol)?

    @State var selectedSection: SettingsSection = .aiModel
    @State private var searchText: String = ""

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(
                selectedSection: $selectedSection,
                searchText: $searchText
            )
        } detail: {
            settingsContent(for: selectedSection)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 180, max: 180)
        .frame(minWidth: 680, minHeight: 440)
        .frame(idealWidth: 780, idealHeight: 540)
    }

    // MARK: - Content Router

    @ViewBuilder
    private func settingsContent(for section: SettingsSection) -> some View {
        switch section {
        case .aiModel:
            ModelSettingsView(settings: settings)

        case .apiKey:
            APIKeySettingsView(keychainService: keychainService)

        case .usage:
            if let metricsCollector {
                UsageDashboardView(metricsCollector: metricsCollector, settings: settings, resourceOptimizer: resourceOptimizer)
            } else {
                unavailableView(title: "사용량", message: "메트릭 수집기가 초기화되지 않았습니다.")
            }

        case .rag:
            RAGSettingsView(settings: settings, documentIndexer: documentIndexer)

        case .memory:
            MemorySettingsView(settings: settings, memoryConsolidator: viewModel?.memoryConsolidator)

        case .feedback:
            if let feedbackStore {
                FeedbackStatsView(
                    feedbackStore: feedbackStore,
                    settings: settings,
                    viewModel: viewModel
                )
            } else {
                unavailableView(title: "피드백 통계", message: "피드백 저장소가 초기화되지 않았습니다.")
            }

        case .voice:
            VoiceSettingsView(settings: settings, keychainService: keychainService, ttsService: ttsService, downloadManager: downloadManager)

        case .interface:
            Form {
                InterfaceSettingsContent(settings: settings, viewModel: viewModel, spotlightIndexer: viewModel?.concreteSpotlightIndexer)
            }
            .formStyle(.grouped)
            .padding()

        case .wakeWord:
            Form {
                WakeWordSettingsContent(settings: settings)
            }
            .formStyle(.grouped)
            .padding()

        case .heartbeat:
            Form {
                HeartbeatSettingsContent(settings: settings, heartbeatService: heartbeatService, notificationManager: notificationManager)
            }
            .formStyle(.grouped)
            .padding()

        case .proactiveSuggestion:
            ProactiveSuggestionSettingsView(
                settings: settings,
                proactiveSuggestionService: viewModel?.proactiveSuggestionService
            )

        case .automation:
            AutomationSettingsView(settings: settings, schedulerService: schedulerService)

        case .family:
            if let contextService, let sessionContext {
                FamilySettingsView(
                    contextService: contextService,
                    settings: settings,
                    sessionContext: sessionContext
                )
            } else {
                unavailableView(title: "가족 구성원", message: "컨텍스트 서비스가 초기화되지 않았습니다.")
            }

        case .interest:
            InterestSettingsView(
                settings: settings,
                interestService: viewModel?.interestDiscoveryService,
                contextService: contextService,
                userId: sessionContext?.currentUserId
            )

        case .agent:
            if let contextService, let sessionContext {
                AgentSettingsView(
                    contextService: contextService,
                    settings: settings,
                    sessionContext: sessionContext,
                    viewModel: viewModel
                )
            } else {
                unavailableView(title: "에이전트", message: "컨텍스트 서비스가 초기화되지 않았습니다.")
            }

        case .tools:
            if let toolService {
                ToolsSettingsView(toolService: toolService)
            } else {
                unavailableView(title: "도구", message: "도구 서비스가 초기화되지 않았습니다.")
            }

        case .integrations:
            IntegrationsSettingsView(
                keychainService: keychainService,
                telegramService: telegramService,
                mcpService: mcpService,
                settings: settings
            )

        case .shortcuts:
            ShortcutsSettingsView()

        case .plugins:
            PluginSettingsView(pluginManager: pluginManager)

        case .terminal:
            TerminalSettingsView(settings: settings)

        case .externalTool:
            ExternalToolSettingsView(
                settings: settings,
                externalToolManager: viewModel?.externalToolManager
            )

        case .devices:
            if let devicePolicyService {
                DeviceSettingsView(
                    devicePolicyService: devicePolicyService,
                    settings: settings,
                    supabaseService: supabaseService
                )
            } else {
                unavailableView(title: "디바이스", message: "디바이스 정책 서비스가 초기화되지 않았습니다.")
            }

        case .account:
            AccountSettingsView(
                supabaseService: supabaseService,
                settings: settings,
                syncEngine: viewModel?.syncEngine
            )

        case .guide:
            Form {
                GuideSettingsContent(settings: settings)
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    @ViewBuilder
    private func unavailableView(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Interface Settings Content (split from GeneralSettingsView)

struct InterfaceSettingsContent: View {
    var settings: AppSettings
    var viewModel: DochiViewModel?
    var spotlightIndexer: SpotlightIndexer?

    var body: some View {
        Section {
            HStack {
                Text("채팅 글꼴 크기: \(Int(settings.chatFontSize))pt")
                Slider(value: Binding(
                    get: { settings.chatFontSize },
                    set: { settings.chatFontSize = $0 }
                ), in: 10...24, step: 1)
            }

            Text("미리보기 텍스트")
                .font(.system(size: settings.chatFontSize))
                .foregroundStyle(.secondary)
        } header: {
            SettingsSectionHeader(
                title: "글꼴",
                helpContent: "대화 영역의 글꼴 크기를 조절합니다. 시스템 설정의 접근성 글꼴과 독립적입니다."
            )
        }

        Section {
            Picker("모드", selection: Binding(
                get: { settings.interactionMode },
                set: { settings.interactionMode = $0 }
            )) {
                Text("음성 + 텍스트").tag(InteractionMode.voiceAndText.rawValue)
                Text("텍스트 전용").tag(InteractionMode.textOnly.rawValue)
            }
            .pickerStyle(.radioGroup)
        } header: {
            SettingsSectionHeader(
                title: "상호작용 모드",
                helpContent: "\"음성 + 텍스트\"는 마이크 버튼과 웨이크워드를 활성화합니다. \"텍스트 전용\"은 음성 기능을 비활성화합니다."
            )
        }

        Section {
            Toggle("3D 아바타 표시", isOn: Binding(
                get: { settings.avatarEnabled },
                set: { settings.avatarEnabled = $0 }
            ))

            Text("VRM 3D 아바타를 대화 영역 위에 표시합니다 (macOS 15+)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.avatarEnabled {
                Text("Dochi/Resources/Models/ 디렉토리에 default_avatar.vrm 파일을 배치해주세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SettingsSectionHeader(
                title: "아바타",
                helpContent: "VRM 형식의 3D 아바타를 대화 영역 위에 표시합니다. macOS 15 이상에서 사용 가능합니다. Resources/Models/에 VRM 파일이 필요합니다."
            )
        }

        Section {
            Toggle("메뉴바 아이콘 표시", isOn: Binding(
                get: { settings.menuBarEnabled },
                set: { settings.menuBarEnabled = $0 }
            ))

            Text("메뉴바에서 바로 도치와 대화할 수 있습니다")
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.menuBarEnabled {
                Toggle("글로벌 단축키 (Cmd+Shift+D)", isOn: Binding(
                    get: { settings.menuBarGlobalShortcutEnabled },
                    set: { settings.menuBarGlobalShortcutEnabled = $0 }
                ))

                Text("다른 앱 사용 중에도 단축키로 퀵 액세스 팝업을 열 수 있습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SettingsSectionHeader(
                title: "메뉴바 퀵 액세스",
                helpContent: "메뉴바 아이콘을 통해 메인 앱을 열지 않고도 빠르게 도치와 대화할 수 있습니다. Cmd+Shift+D로 어디서든 팝업을 토글할 수 있습니다."
            )
        }

        // MARK: - Spotlight 검색 (H-4)

        Section {
            Toggle("Spotlight 인덱싱 활성화", isOn: Binding(
                get: { settings.spotlightIndexingEnabled },
                set: { settings.spotlightIndexingEnabled = $0 }
            ))

            if settings.spotlightIndexingEnabled {
                // 인덱싱 상태 — spotlightIndexer는 @Observable 구체 타입으로 직접 받아 관찰 추적 가능
                if let indexer = spotlightIndexer {
                    HStack {
                        Text("인덱싱된 항목")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(indexer.indexedItemCount)건")
                            .font(.system(.body, design: .monospaced))
                    }

                    if let lastDate = indexer.lastIndexedAt {
                        HStack {
                            Text("마지막 인덱싱")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lastDate, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 재구축/초기화 버튼
                    if indexer.isRebuilding {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: indexer.rebuildProgress)
                            Text("재구축 중... \(Int(indexer.rebuildProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button("인덱스 재구축") {
                                guard let vm = viewModel else { return }
                                Task {
                                    await indexer.rebuildAllIndices(
                                        conversations: vm.conversations,
                                        contextService: vm.contextService,
                                        sessionContext: vm.sessionContext
                                    )
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("인덱스 초기화") {
                                Task {
                                    await indexer.clearAllIndices()
                                }
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.red)
                        }
                    }
                }

                Divider()

                // 인덱싱 범위 체크박스
                Text("인덱싱 범위")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("대화", isOn: Binding(
                    get: { settings.spotlightIndexConversations },
                    set: { settings.spotlightIndexConversations = $0 }
                ))

                Toggle("개인 메모리", isOn: Binding(
                    get: { settings.spotlightIndexPersonalMemory },
                    set: { settings.spotlightIndexPersonalMemory = $0 }
                ))

                Toggle("에이전트 메모리", isOn: Binding(
                    get: { settings.spotlightIndexAgentMemory },
                    set: { settings.spotlightIndexAgentMemory = $0 }
                ))

                Toggle("워크스페이스 메모리", isOn: Binding(
                    get: { settings.spotlightIndexWorkspaceMemory },
                    set: { settings.spotlightIndexWorkspaceMemory = $0 }
                ))
            }
        } header: {
            SettingsSectionHeader(
                title: "Spotlight 검색",
                helpContent: "대화와 메모리를 macOS Spotlight에 인덱싱하여 앱 밖에서도 검색할 수 있습니다. Spotlight에서 결과를 클릭하면 해당 대화나 메모리로 바로 이동합니다."
            )
        }
    }
}

// MARK: - WakeWord Settings Content (split from GeneralSettingsView)

struct WakeWordSettingsContent: View {
    var settings: AppSettings

    var body: some View {
        Section {
            Toggle("웨이크워드 감지", isOn: Binding(
                get: { settings.wakeWordEnabled },
                set: { settings.wakeWordEnabled = $0 }
            ))

            TextField("웨이크워드", text: Binding(
                get: { settings.wakeWord },
                set: { settings.wakeWord = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Text("침묵 타임아웃: \(String(format: "%.1f", settings.sttSilenceTimeout))초")
                Slider(value: Binding(
                    get: { settings.sttSilenceTimeout },
                    set: { settings.sttSilenceTimeout = $0 }
                ), in: 1...5, step: 0.5)
            }

            Toggle("항상 대기 모드", isOn: Binding(
                get: { settings.wakeWordAlwaysOn },
                set: { settings.wakeWordAlwaysOn = $0 }
            ))

            Text("앱이 활성화되어 있는 동안 항상 웨이크워드를 감지합니다")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            SettingsSectionHeader(
                title: "웨이크워드",
                helpContent: "지정한 단어를 말하면 자동으로 음성 입력이 시작됩니다. \"항상 대기 모드\"를 켜면 앱이 활성화된 동안 계속 감지합니다."
            )
        }
    }
}

// MARK: - Heartbeat Settings Content (split from GeneralSettingsView)

struct HeartbeatSettingsContent: View {
    var settings: AppSettings
    var heartbeatService: HeartbeatService?
    var notificationManager: NotificationManager?

    var body: some View {
        Section {
            Toggle("하트비트 활성화", isOn: Binding(
                get: { settings.heartbeatEnabled },
                set: { settings.heartbeatEnabled = $0 }
            ))

            Text("주기적으로 일정과 할 일을 점검하여 자동 알림")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("점검 주기: \(settings.heartbeatIntervalMinutes)분")
                Slider(
                    value: Binding(
                        get: { Double(settings.heartbeatIntervalMinutes) },
                        set: { settings.heartbeatIntervalMinutes = Int($0.rounded()) }
                    ),
                    in: 5...120,
                    step: 5
                )
            }

            Toggle("캘린더 점검", isOn: Binding(
                get: { settings.heartbeatCheckCalendar },
                set: { settings.heartbeatCheckCalendar = $0 }
            ))
            Toggle("칸반 점검", isOn: Binding(
                get: { settings.heartbeatCheckKanban },
                set: { settings.heartbeatCheckKanban = $0 }
            ))
            Toggle("미리알림 점검", isOn: Binding(
                get: { settings.heartbeatCheckReminders },
                set: { settings.heartbeatCheckReminders = $0 }
            ))
        } header: {
            SettingsSectionHeader(
                title: "하트비트",
                helpContent: "주기적으로 캘린더, 칸반, 미리알림을 점검하여 알려줄 내용이 있으면 자동으로 메시지를 보냅니다. 조용한 시간 동안에는 알림을 보내지 않습니다."
            )
        }

        // MARK: - Notification Center (H-3)
        Section {
            // Authorization status row
            if let notificationManager {
                HStack {
                    Text("알림 권한")
                    Spacer()
                    NotificationAuthorizationStatusView(status: notificationManager.authorizationStatus)
                }
            }

            Toggle("알림 소리", isOn: Binding(
                get: { settings.notificationSoundEnabled },
                set: { settings.notificationSoundEnabled = $0 }
            ))

            Toggle("알림에서 답장", isOn: Binding(
                get: { settings.notificationReplyEnabled },
                set: { settings.notificationReplyEnabled = $0 }
            ))

            // Category toggles
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading) {
                    Toggle("캘린더 알림", isOn: Binding(
                        get: { settings.notificationCalendarEnabled },
                        set: { settings.notificationCalendarEnabled = $0 }
                    ))
                    Text("다가오는 일정을 알림 센터에 표시")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.orange)
                    .frame(width: 20)
                VStack(alignment: .leading) {
                    Toggle("칸반 알림", isOn: Binding(
                        get: { settings.notificationKanbanEnabled },
                        set: { settings.notificationKanbanEnabled = $0 }
                    ))
                    Text("진행 중인 칸반 작업을 알림 센터에 표시")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Image(systemName: "bell")
                    .foregroundStyle(.green)
                    .frame(width: 20)
                VStack(alignment: .leading) {
                    Toggle("미리알림 알림", isOn: Binding(
                        get: { settings.notificationReminderEnabled },
                        set: { settings.notificationReminderEnabled = $0 }
                    ))
                    Text("마감 임박한 미리알림을 알림 센터에 표시")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Image(systemName: "externaldrive")
                    .foregroundStyle(.purple)
                    .frame(width: 20)
                VStack(alignment: .leading) {
                    Toggle("메모리 알림", isOn: Binding(
                        get: { settings.notificationMemoryEnabled },
                        set: { settings.notificationMemoryEnabled = $0 }
                    ))
                    Text("메모리 크기 경고를 알림 센터에 표시")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SettingsSectionHeader(
                title: "알림 센터",
                helpContent: "하트비트 알림을 macOS 알림 센터로 전달합니다. 카테고리별로 알림을 켜거나 끌 수 있으며, 알림에서 바로 답장할 수 있습니다."
            )
        }
        .disabled(!settings.heartbeatEnabled)

        Section("하트비트 조용한 시간") {
            Stepper(
                "시작: \(settings.heartbeatQuietHoursStart):00",
                value: Binding(
                    get: { settings.heartbeatQuietHoursStart },
                    set: { settings.heartbeatQuietHoursStart = min(max($0, 0), 23) }
                ),
                in: 0...23
            )

            Stepper(
                "종료: \(settings.heartbeatQuietHoursEnd):00",
                value: Binding(
                    get: { settings.heartbeatQuietHoursEnd },
                    set: { settings.heartbeatQuietHoursEnd = min(max($0, 0), 23) }
                ),
                in: 0...23
            )
        }

        if let heartbeatService {
            Section("하트비트 상태") {
                if let lastTick = heartbeatService.lastTickDate {
                    HStack {
                        Text("마지막 실행")
                        Spacer()
                        Text(lastTick, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("아직 실행되지 않음")
                        .foregroundStyle(.secondary)
                }

                if let result = heartbeatService.lastTickResult {
                    HStack {
                        Text("점검 항목")
                        Spacer()
                        Text(result.checksPerformed.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Text("발견 항목")
                        Spacer()
                        Text("\(result.itemsFound)건")
                            .foregroundStyle(result.itemsFound > 0 ? .primary : .secondary)
                    }
                    if result.notificationSent {
                        Text("알림 전송됨")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    if let error = result.error {
                        Text("오류: \(error)")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                HStack {
                    Text("실행 이력")
                    Spacer()
                    Text("\(heartbeatService.tickHistory.count)건")
                        .foregroundStyle(.secondary)
                }

                if heartbeatService.consecutiveErrors > 0 {
                    HStack {
                        Text("연속 오류")
                        Spacer()
                        Text("\(heartbeatService.consecutiveErrors)회")
                            .foregroundStyle(.red)
                    }
                }
            }
        }

        // MARK: - Proactive Suggestions (K-2)

        Section {
            Toggle("프로액티브 제안 활성화", isOn: Binding(
                get: { settings.proactiveSuggestionEnabled },
                set: { settings.proactiveSuggestionEnabled = $0 }
            ))

            Text("유휴 상태일 때 칸반/메모리/관심사 기반 제안을 자동 표시")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("유휴 감지: \(settings.proactiveSuggestionIdleMinutes)분")
                Slider(
                    value: Binding(
                        get: { Double(settings.proactiveSuggestionIdleMinutes) },
                        set: { settings.proactiveSuggestionIdleMinutes = Int($0.rounded()) }
                    ),
                    in: 5...120,
                    step: 5
                )
            }

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

            Toggle("조용한 시간에 제안 중지", isOn: Binding(
                get: { settings.proactiveSuggestionQuietHoursEnabled },
                set: { settings.proactiveSuggestionQuietHoursEnabled = $0 }
            ))
        } header: {
            SettingsSectionHeader(
                title: "프로액티브 제안",
                helpContent: "사용자가 일정 시간 유휴 상태일 때, 칸반 진행 상황/메모리 기한/대화 주제 등을 기반으로 자동 제안합니다. 조용한 시간 설정은 하트비트와 공유합니다."
            )
        }
        .disabled(!settings.proactiveSuggestionEnabled)

        Section("제안 유형") {
            ForEach(SuggestionType.allCases, id: \.rawValue) { type in
                Toggle(isOn: suggestionTypeBinding(for: type)) {
                    HStack(spacing: 8) {
                        Image(systemName: type.icon)
                            .foregroundStyle(suggestionTypeBadgeColor(type))
                            .frame(width: 20)
                        Text(type.displayName)
                    }
                }
            }
        }
        .disabled(!settings.proactiveSuggestionEnabled)
    }

    private func suggestionTypeBinding(for type: SuggestionType) -> Binding<Bool> {
        Binding(
            get: {
                switch type {
                case .newsTrend: return settings.suggestionTypeNewsEnabled
                case .deepDive: return settings.suggestionTypeDeepDiveEnabled
                case .relatedResearch: return settings.suggestionTypeResearchEnabled
                case .kanbanCheck: return settings.suggestionTypeKanbanEnabled
                case .memoryRemind: return settings.suggestionTypeMemoryEnabled
                case .costReport: return settings.suggestionTypeCostEnabled
                }
            },
            set: { newValue in
                switch type {
                case .newsTrend: settings.suggestionTypeNewsEnabled = newValue
                case .deepDive: settings.suggestionTypeDeepDiveEnabled = newValue
                case .relatedResearch: settings.suggestionTypeResearchEnabled = newValue
                case .kanbanCheck: settings.suggestionTypeKanbanEnabled = newValue
                case .memoryRemind: settings.suggestionTypeMemoryEnabled = newValue
                case .costReport: settings.suggestionTypeCostEnabled = newValue
                }
            }
        )
    }

    private func suggestionTypeBadgeColor(_ type: SuggestionType) -> Color {
        switch type.badgeColor {
        case "blue": return .blue
        case "purple": return .purple
        case "teal": return .teal
        case "orange": return .orange
        case "green": return .green
        case "red": return .red
        default: return .gray
        }
    }
}

/// Displays notification authorization status with colored indicator.
struct NotificationAuthorizationStatusView: View {
    let status: UNAuthorizationStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .authorized, .provisional:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .yellow
        @unknown default:
            return .gray
        }
    }

    private var statusText: String {
        switch status {
        case .authorized:
            return "허용됨"
        case .denied:
            return "거부됨"
        case .notDetermined:
            return "미결정"
        case .provisional:
            return "임시 허용"
        @unknown default:
            return "알 수 없음"
        }
    }
}

// MARK: - Guide Settings Content (split from GeneralSettingsView)

struct GuideSettingsContent: View {
    var settings: AppSettings

    @State private var showFeatureTourSheet = false

    var body: some View {
        Section("가이드") {
            Button {
                settings.resetFeatureTour()
                showFeatureTourSheet = true
            } label: {
                HStack {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                    Text("기능 투어 다시 보기")
                }
            }
            .buttonStyle(.plain)

            Button {
                settings.resetAllHints()
                HintManager.shared.resetAllHints()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                    Text("인앱 힌트 초기화")
                }
            }
            .buttonStyle(.plain)

            Toggle("인앱 힌트 표시", isOn: Binding(
                get: { settings.hintsEnabled },
                set: { newValue in
                    settings.hintsEnabled = newValue
                    if !newValue {
                        HintManager.shared.disableAllHints()
                    }
                }
            ))
        }
        .sheet(isPresented: $showFeatureTourSheet) {
            FeatureTourView(
                onComplete: { showFeatureTourSheet = false },
                onSkip: { showFeatureTourSheet = false }
            )
        }
    }
}

// MARK: - GeneralSettingsView (backward compatibility wrapper)

struct GeneralSettingsView: View {
    var settings: AppSettings
    var heartbeatService: HeartbeatService?
    var notificationManager: NotificationManager?

    var body: some View {
        Form {
            InterfaceSettingsContent(settings: settings)
            WakeWordSettingsContent(settings: settings)
            HeartbeatSettingsContent(settings: settings, heartbeatService: heartbeatService, notificationManager: notificationManager)
            GuideSettingsContent(settings: settings)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Model Settings

struct ModelSettingsView: View {
    var settings: AppSettings

    @State private var selectedProviderRaw: String = ""
    @State private var selectedModel: String = ""
    @State private var ollamaModels: [LocalModelInfo] = []
    @State private var ollamaAvailable: Bool? = nil
    @State private var ollamaURL: String = ""
    @State private var lmStudioModels: [LocalModelInfo] = []
    @State private var lmStudioAvailable: Bool? = nil
    @State private var lmStudioURL: String = ""

    // Offline fallback
    @State private var offlineFallbackModels: [String] = []

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: selectedProviderRaw) ?? .openai
    }

    /// Combined model list: static for most providers, dynamic for local providers.
    private var availableModels: [String] {
        switch selectedProvider {
        case .ollama:
            return ollamaModels.map(\.name)
        case .lmStudio:
            return lmStudioModels.map(\.name)
        default:
            return selectedProvider.models
        }
    }

    /// Get LocalModelInfo for current local provider, if applicable.
    private var currentLocalModels: [LocalModelInfo] {
        switch selectedProvider {
        case .ollama: return ollamaModels
        case .lmStudio: return lmStudioModels
        default: return []
        }
    }

    var body: some View {
        Form {
            // Provider picker with cloud/local grouping
            Section {
                Picker("프로바이더", selection: $selectedProviderRaw) {
                    // Cloud providers
                    Section("클라우드") {
                        ForEach(LLMProvider.cloudProviders, id: \.self) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    // Local providers
                    Section("로컬") {
                        ForEach(LLMProvider.localProviders, id: \.self) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                }
                .onChange(of: selectedProviderRaw) { _, newValue in
                    settings.llmProvider = newValue
                    let provider = LLMProvider(rawValue: newValue) ?? .openai
                    switch provider {
                    case .ollama:
                        fetchOllamaModels()
                    case .lmStudio:
                        fetchLMStudioModels()
                    default:
                        if !provider.models.contains(selectedModel) {
                            selectedModel = provider.models.first ?? ""
                            settings.llmModel = selectedModel
                        }
                    }
                }

                if selectedProvider.isLocal {
                    // Local model picker with metadata
                    Picker("모델", selection: $selectedModel) {
                        if availableModels.isEmpty {
                            Text("모델 없음").tag("")
                        }
                        ForEach(currentLocalModels) { model in
                            HStack {
                                Text(model.name)
                                if !model.compactDescription.isEmpty {
                                    Text(model.compactDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if model.supportsTools {
                                    Image(systemName: "wrench.and.screwdriver")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(model.name)
                        }
                    }
                    .onChange(of: selectedModel) { _, newValue in
                        settings.llmModel = newValue
                    }

                    // Tool support warning for selected model
                    if let selectedInfo = currentLocalModels.first(where: { $0.name == selectedModel }),
                       !selectedInfo.supportsTools {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("이 모델은 도구 호출(function calling)을 지원하지 않을 수 있습니다")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Picker("모델", selection: $selectedModel) {
                        ForEach(selectedProvider.models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .onChange(of: selectedModel) { _, newValue in
                        settings.llmModel = newValue
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: "LLM 프로바이더",
                    helpContent: "AI 응답을 생성하는 서비스를 선택합니다. 클라우드 프로바이더는 API 키가 필요하며, 로컬 프로바이더(Ollama, LM Studio)는 별도 설치 후 사용합니다."
                )
            }

            // Ollama settings
            if selectedProvider == .ollama {
                Section("Ollama 설정") {
                    HStack {
                        Text("Base URL")
                        TextField("http://localhost:11434", text: $ollamaURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit {
                                settings.ollamaBaseURL = ollamaURL
                                fetchOllamaModels()
                            }
                    }

                    localServerStatusRow(available: ollamaAvailable)

                    Button("모델 새로고침") {
                        fetchOllamaModels()
                    }
                }
            }

            // LM Studio settings
            if selectedProvider == .lmStudio {
                Section("LM Studio 설정") {
                    HStack {
                        Text("Base URL")
                        TextField("http://localhost:1234", text: $lmStudioURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit {
                                settings.lmStudioBaseURL = lmStudioURL
                                fetchLMStudioModels()
                            }
                    }

                    localServerStatusRow(available: lmStudioAvailable)

                    Button("모델 새로고침") {
                        fetchLMStudioModels()
                    }
                }
            }

            Section {
                HStack {
                    Text("컨텍스트 윈도우")
                    Spacer()
                    let tokens = selectedProvider.contextWindowTokens(for: selectedModel)
                    Text("\(tokens / 1000)K tokens")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                SettingsSectionHeader(
                    title: "컨텍스트",
                    helpContent: "모델이 한 번에 처리할 수 있는 텍스트 양(토큰)입니다. 대화가 길어지면 오래된 메시지는 자동으로 압축됩니다."
                )
            }

            // Offline fallback
            Section {
                Toggle("오프라인 자동 전환", isOn: Binding(
                    get: { settings.offlineFallbackEnabled },
                    set: { settings.offlineFallbackEnabled = $0 }
                ))

                Text("네트워크 연결이 끊어지면 자동으로 로컬 모델로 전환합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.offlineFallbackEnabled {
                    Picker("폴백 프로바이더", selection: Binding(
                        get: { settings.offlineFallbackProvider },
                        set: { newValue in
                            settings.offlineFallbackProvider = newValue
                            settings.offlineFallbackModel = ""
                            fetchOfflineFallbackModels()
                        }
                    )) {
                        ForEach(LLMProvider.localProviders, id: \.self) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }

                    Picker("폴백 모델", selection: Binding(
                        get: { settings.offlineFallbackModel },
                        set: { settings.offlineFallbackModel = $0 }
                    )) {
                        if offlineFallbackModels.isEmpty {
                            Text("서버 연결 필요").tag("")
                        }
                        ForEach(offlineFallbackModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    if !settings.offlineFallbackModel.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("오프라인 폴백 설정 완료: \(settings.offlineFallbackModel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: "오프라인 폴백",
                    helpContent: "클라우드 LLM 서비스에 접속할 수 없을 때 로컬에서 실행 중인 Ollama 또는 LM Studio 모델로 자동 전환합니다."
                )
            }

            Section {
                Toggle("자동 모델 선택", isOn: Binding(
                    get: { settings.taskRoutingEnabled },
                    set: { settings.taskRoutingEnabled = $0 }
                ))

                Text("메시지 복잡도에 따라 경량/고급 모델을 자동 선택합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.taskRoutingEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("경량 모델 (일상 대화)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Picker("프로바이더", selection: Binding(
                                get: { settings.lightModelProvider },
                                set: { settings.lightModelProvider = $0 }
                            )) {
                                Text("기본 모델 사용").tag("")
                                ForEach(LLMProvider.allCases, id: \.self) { p in
                                    Text(p.displayName).tag(p.rawValue)
                                }
                            }
                            .frame(width: 140)

                            TextField("모델명", text: Binding(
                                get: { settings.lightModelName },
                                set: { settings.lightModelName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("고급 모델 (코딩, 분석)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Picker("프로바이더", selection: Binding(
                                get: { settings.heavyModelProvider },
                                set: { settings.heavyModelProvider = $0 }
                            )) {
                                Text("기본 모델 사용").tag("")
                                ForEach(LLMProvider.allCases, id: \.self) { p in
                                    Text(p.displayName).tag(p.rawValue)
                                }
                            }
                            .frame(width: 140)

                            TextField("모델명", text: Binding(
                                get: { settings.heavyModelName },
                                set: { settings.heavyModelName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        }
                    }

                    Text("표준 복잡도 메시지는 위에서 선택한 기본 모델을 사용합니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SettingsSectionHeader(
                    title: "용도별 모델 라우팅",
                    helpContent: "메시지 복잡도를 자동으로 판단하여 간단한 질문은 빠른 모델에, 복잡한 작업은 고급 모델에 보냅니다. 비용 절약과 속도 개선에 유용합니다."
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            selectedProviderRaw = settings.llmProvider
            selectedModel = settings.llmModel
            ollamaURL = settings.ollamaBaseURL
            lmStudioURL = settings.lmStudioBaseURL
            if selectedProvider == .ollama {
                fetchOllamaModels()
            } else if selectedProvider == .lmStudio {
                fetchLMStudioModels()
            }
            if settings.offlineFallbackEnabled {
                fetchOfflineFallbackModels()
            }
        }
    }

    // MARK: - Local Server Status Row

    @ViewBuilder
    private func localServerStatusRow(available: Bool?) -> some View {
        HStack {
            Text("상태")
            Spacer()
            if let available {
                if available {
                    Label("연결됨", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("연결 불가", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchOllamaModels() {
        ollamaAvailable = nil
        Task {
            let baseURL = URL(string: settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
            let infos = await OllamaModelFetcher.fetchModelInfos(baseURL: baseURL)
            let available = await OllamaModelFetcher.isAvailable(baseURL: baseURL)
            ollamaModels = infos
            ollamaAvailable = available
            if !infos.map(\.name).contains(selectedModel) {
                selectedModel = infos.first?.name ?? ""
                settings.llmModel = selectedModel
            }
        }
    }

    private func fetchLMStudioModels() {
        lmStudioAvailable = nil
        Task {
            let baseURL = URL(string: settings.lmStudioBaseURL) ?? URL(string: "http://localhost:1234")!
            let infos = await LMStudioModelFetcher.fetchModelInfos(baseURL: baseURL)
            let available = await LMStudioModelFetcher.isAvailable(baseURL: baseURL)
            lmStudioModels = infos
            lmStudioAvailable = available
            if !infos.map(\.name).contains(selectedModel) {
                selectedModel = infos.first?.name ?? ""
                settings.llmModel = selectedModel
            }
        }
    }

    private func fetchOfflineFallbackModels() {
        Task {
            guard let provider = LLMProvider(rawValue: settings.offlineFallbackProvider) else { return }
            switch provider {
            case .ollama:
                let baseURL = URL(string: settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
                offlineFallbackModels = await OllamaModelFetcher.fetchModels(baseURL: baseURL)
            case .lmStudio:
                let baseURL = URL(string: settings.lmStudioBaseURL) ?? URL(string: "http://localhost:1234")!
                offlineFallbackModels = await LMStudioModelFetcher.fetchModels(baseURL: baseURL)
            default:
                offlineFallbackModels = []
            }
        }
    }
}

// MARK: - API Key Settings

struct APIKeySettingsView: View {
    var keychainService: KeychainServiceProtocol

    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var zaiKey: String = ""
    @State private var tavilyKey: String = ""
    @State private var falKey: String = ""
    @State private var saveStatus: String?
    @State private var showKeys: Bool = false
    @State private var showTierKeys: Bool = false

    // Tier-specific keys
    @State private var openaiPremiumKey: String = ""
    @State private var openaiEconomyKey: String = ""
    @State private var anthropicPremiumKey: String = ""
    @State private var anthropicEconomyKey: String = ""

    var body: some View {
        Form {
            Section {
                Toggle("키 표시", isOn: $showKeys)

                apiKeyRow(label: "OpenAI", key: $openaiKey, account: LLMProvider.openai.keychainAccount)
                apiKeyRow(label: "Anthropic", key: $anthropicKey, account: LLMProvider.anthropic.keychainAccount)
                apiKeyRow(label: "Z.AI", key: $zaiKey, account: LLMProvider.zai.keychainAccount)
            } header: {
                SettingsSectionHeader(
                    title: "LLM API 키",
                    helpContent: "API 키는 macOS 키체인에 암호화되어 저장됩니다. 각 프로바이더 웹사이트에서 키를 발급받을 수 있습니다. 키를 입력하지 않은 프로바이더의 모델은 사용할 수 없습니다."
                )
            }

            Section("티어별 API 키") {
                Toggle("티어별 키 관리", isOn: $showTierKeys)
                Text("용도별 모델 라우팅 시 프리미엄/경제 티어 전용 키를 사용합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if showTierKeys {
                    Group {
                        Text("OpenAI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        apiKeyRow(label: "  프리미엄", key: $openaiPremiumKey, account: LLMProvider.openai.keychainAccount + APIKeyTier.premium.keychainSuffix)
                        apiKeyRow(label: "  경제", key: $openaiEconomyKey, account: LLMProvider.openai.keychainAccount + APIKeyTier.economy.keychainSuffix)
                    }

                    Group {
                        Text("Anthropic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        apiKeyRow(label: "  프리미엄", key: $anthropicPremiumKey, account: LLMProvider.anthropic.keychainAccount + APIKeyTier.premium.keychainSuffix)
                        apiKeyRow(label: "  경제", key: $anthropicEconomyKey, account: LLMProvider.anthropic.keychainAccount + APIKeyTier.economy.keychainSuffix)
                    }

                    Text("티어별 키가 없으면 기본 키를 사용합니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("도구 API 키") {
                apiKeyRow(label: "Tavily (웹 검색)", key: $tavilyKey, account: "tavily_api_key")
                apiKeyRow(label: "Fal.ai (이미지)", key: $falKey, account: "fal_api_key")
            }

            Section {
                HStack {
                    Button("저장") {
                        saveAllKeys()
                    }
                    .keyboardShortcut(.defaultAction)

                    if let status = saveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadKeys()
        }
    }

    @ViewBuilder
    private func apiKeyRow(label: String, key: Binding<String>, account: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            if showKeys {
                TextField("sk-...", text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            } else {
                SecureField("sk-...", text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            if let stored = keychainService.load(account: account), !stored.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .help("저장됨")
            }
        }
    }

    private func loadKeys() {
        openaiKey = keychainService.load(account: LLMProvider.openai.keychainAccount) ?? ""
        anthropicKey = keychainService.load(account: LLMProvider.anthropic.keychainAccount) ?? ""
        zaiKey = keychainService.load(account: LLMProvider.zai.keychainAccount) ?? ""
        tavilyKey = keychainService.load(account: "tavily_api_key") ?? ""
        falKey = keychainService.load(account: "fal_api_key") ?? ""

        // Tier keys
        openaiPremiumKey = keychainService.load(account: LLMProvider.openai.keychainAccount + APIKeyTier.premium.keychainSuffix) ?? ""
        openaiEconomyKey = keychainService.load(account: LLMProvider.openai.keychainAccount + APIKeyTier.economy.keychainSuffix) ?? ""
        anthropicPremiumKey = keychainService.load(account: LLMProvider.anthropic.keychainAccount + APIKeyTier.premium.keychainSuffix) ?? ""
        anthropicEconomyKey = keychainService.load(account: LLMProvider.anthropic.keychainAccount + APIKeyTier.economy.keychainSuffix) ?? ""
    }

    private func saveAllKeys() {
        do {
            var keys: [(String, String)] = [
                (LLMProvider.openai.keychainAccount, openaiKey),
                (LLMProvider.anthropic.keychainAccount, anthropicKey),
                (LLMProvider.zai.keychainAccount, zaiKey),
                ("tavily_api_key", tavilyKey),
                ("fal_api_key", falKey),
            ]

            // Tier keys
            let tierKeys: [(String, String)] = [
                (LLMProvider.openai.keychainAccount + APIKeyTier.premium.keychainSuffix, openaiPremiumKey),
                (LLMProvider.openai.keychainAccount + APIKeyTier.economy.keychainSuffix, openaiEconomyKey),
                (LLMProvider.anthropic.keychainAccount + APIKeyTier.premium.keychainSuffix, anthropicPremiumKey),
                (LLMProvider.anthropic.keychainAccount + APIKeyTier.economy.keychainSuffix, anthropicEconomyKey),
            ]
            keys.append(contentsOf: tierKeys)

            for (account, value) in keys {
                if !value.isEmpty {
                    try keychainService.save(account: account, value: value)
                }
            }
            saveStatus = "저장 완료"
            Log.app.info("API keys saved")
        } catch {
            saveStatus = "저장 실패: \(error.localizedDescription)"
            Log.app.error("API key save failed: \(error.localizedDescription)")
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            saveStatus = nil
        }
    }
}
