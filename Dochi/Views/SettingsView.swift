import SwiftUI

struct SettingsView: View {
    var settings: AppSettings
    var keychainService: KeychainServiceProtocol
    var contextService: ContextServiceProtocol?
    var sessionContext: SessionContext?
    var ttsService: TTSServiceProtocol?
    var telegramService: TelegramServiceProtocol?
    var mcpService: MCPServiceProtocol?
    var supabaseService: SupabaseServiceProtocol?
    var toolService: BuiltInToolService?
    var heartbeatService: HeartbeatService?
    var viewModel: DochiViewModel?

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, heartbeatService: heartbeatService)
                .tabItem {
                    Label("일반", systemImage: "gear")
                }

            ModelSettingsView(settings: settings)
                .tabItem {
                    Label("AI 모델", systemImage: "brain")
                }

            APIKeySettingsView(keychainService: keychainService)
                .tabItem {
                    Label("API 키", systemImage: "key")
                }

            VoiceSettingsView(settings: settings, keychainService: keychainService, ttsService: ttsService)
                .tabItem {
                    Label("음성", systemImage: "speaker.wave.2")
                }

            if let contextService, let sessionContext {
                FamilySettingsView(
                    contextService: contextService,
                    settings: settings,
                    sessionContext: sessionContext
                )
                .tabItem {
                    Label("가족", systemImage: "person.2")
                }

                AgentSettingsView(
                    contextService: contextService,
                    settings: settings,
                    sessionContext: sessionContext,
                    viewModel: viewModel
                )
                .tabItem {
                    Label("에이전트", systemImage: "person.crop.rectangle.stack")
                }
            }

            if let toolService {
                ToolsSettingsView(toolService: toolService)
                    .tabItem {
                        Label("도구", systemImage: "wrench.and.screwdriver")
                    }
            }

            IntegrationsSettingsView(
                keychainService: keychainService,
                telegramService: telegramService,
                mcpService: mcpService,
                settings: settings
            )
            .tabItem {
                Label("통합", systemImage: "puzzlepiece")
            }

            AccountSettingsView(
                supabaseService: supabaseService,
                settings: settings
            )
            .tabItem {
                Label("계정", systemImage: "person.circle")
            }
        }
        .frame(width: 600, height: 480)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    var settings: AppSettings
    var heartbeatService: HeartbeatService?

    var body: some View {
        Form {
            Section("글꼴") {
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
            }

            Section("상호작용 모드") {
                Picker("모드", selection: Binding(
                    get: { settings.interactionMode },
                    set: { settings.interactionMode = $0 }
                )) {
                    Text("음성 + 텍스트").tag(InteractionMode.voiceAndText.rawValue)
                    Text("텍스트 전용").tag(InteractionMode.textOnly.rawValue)
                }
                .pickerStyle(.radioGroup)
            }

            Section("웨이크워드") {
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
                .help("앱이 활성화되어 있는 동안 항상 웨이크워드를 감지합니다")
            }

            Section("아바타") {
                Toggle("3D 아바타 표시", isOn: Binding(
                    get: { settings.avatarEnabled },
                    set: { settings.avatarEnabled = $0 }
                ))
                    .help("VRM 3D 아바타를 대화 영역 위에 표시합니다")

                if settings.avatarEnabled {
                    Text("Dochi/Resources/Models/ 디렉토리에 default_avatar.vrm 파일을 배치해주세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("하트비트") {
                Toggle("하트비트 활성화", isOn: Binding(
                    get: { settings.heartbeatEnabled },
                    set: { settings.heartbeatEnabled = $0 }
                ))

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
            }

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
    @State private var ollamaModels: [String] = []
    @State private var ollamaAvailable: Bool? = nil
    @State private var ollamaURL: String = ""

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: selectedProviderRaw) ?? .openai
    }

    /// Combined model list: static for most providers, dynamic for Ollama.
    private var availableModels: [String] {
        if selectedProvider == .ollama {
            return ollamaModels
        }
        return selectedProvider.models
    }

    var body: some View {
        Form {
            Section("LLM 프로바이더") {
                Picker("프로바이더", selection: $selectedProviderRaw) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .onChange(of: selectedProviderRaw) { _, newValue in
                    settings.llmProvider = newValue
                    let provider = LLMProvider(rawValue: newValue) ?? .openai
                    if provider == .ollama {
                        fetchOllamaModels()
                    } else if !provider.models.contains(selectedModel) {
                        selectedModel = provider.models.first ?? ""
                        settings.llmModel = selectedModel
                    }
                }

                if selectedProvider == .ollama {
                    Picker("모델", selection: $selectedModel) {
                        if ollamaModels.isEmpty {
                            Text("모델 없음").tag("")
                        }
                        ForEach(ollamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .onChange(of: selectedModel) { _, newValue in
                        settings.llmModel = newValue
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
            }

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

                    HStack {
                        Text("상태")
                        Spacer()
                        if let available = ollamaAvailable {
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

                    Button("모델 새로고침") {
                        fetchOllamaModels()
                    }
                }
            }

            Section("컨텍스트") {
                HStack {
                    Text("컨텍스트 윈도우")
                    Spacer()
                    let tokens = selectedProvider.contextWindowTokens(for: selectedModel)
                    Text("\(tokens / 1000)K tokens")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("용도별 모델 라우팅") {
                Toggle("자동 모델 선택", isOn: Binding(
                    get: { settings.taskRoutingEnabled },
                    set: { settings.taskRoutingEnabled = $0 }
                ))
                .help("메시지 복잡도에 따라 경량/고급 모델을 자동 선택합니다")

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
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            selectedProviderRaw = settings.llmProvider
            selectedModel = settings.llmModel
            ollamaURL = settings.ollamaBaseURL
            if selectedProvider == .ollama {
                fetchOllamaModels()
            }
        }
    }

    private func fetchOllamaModels() {
        ollamaAvailable = nil
        Task {
            let baseURL = URL(string: settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
            let models = await OllamaModelFetcher.fetchModels(baseURL: baseURL)
            let available = await OllamaModelFetcher.isAvailable(baseURL: baseURL)
            ollamaModels = models
            ollamaAvailable = available
            if !models.contains(selectedModel) {
                selectedModel = models.first ?? ""
                settings.llmModel = selectedModel
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
            Section("LLM API 키") {
                Toggle("키 표시", isOn: $showKeys)

                apiKeyRow(label: "OpenAI", key: $openaiKey, account: LLMProvider.openai.keychainAccount)
                apiKeyRow(label: "Anthropic", key: $anthropicKey, account: LLMProvider.anthropic.keychainAccount)
                apiKeyRow(label: "Z.AI", key: $zaiKey, account: LLMProvider.zai.keychainAccount)
            }

            Section("티어별 API 키") {
                Toggle("티어별 키 관리", isOn: $showTierKeys)
                    .help("용도별 모델 라우팅 시 프리미엄/경제 티어 전용 키를 사용합니다")

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
