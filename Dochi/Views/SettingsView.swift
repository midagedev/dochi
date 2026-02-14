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

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
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
                    sessionContext: sessionContext
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

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: selectedProviderRaw) ?? .openai
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
                    if !provider.models.contains(selectedModel) {
                        selectedModel = provider.models.first ?? ""
                        settings.llmModel = selectedModel
                    }
                }

                Picker("모델", selection: $selectedModel) {
                    ForEach(selectedProvider.models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: selectedModel) { _, newValue in
                    settings.llmModel = newValue
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
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            selectedProviderRaw = settings.llmProvider
            selectedModel = settings.llmModel
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

    var body: some View {
        Form {
            Section("LLM API 키") {
                Toggle("키 표시", isOn: $showKeys)

                apiKeyRow(label: "OpenAI", key: $openaiKey, account: LLMProvider.openai.keychainAccount)
                apiKeyRow(label: "Anthropic", key: $anthropicKey, account: LLMProvider.anthropic.keychainAccount)
                apiKeyRow(label: "Z.AI", key: $zaiKey, account: LLMProvider.zai.keychainAccount)
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
    }

    private func saveAllKeys() {
        do {
            let keys: [(String, String)] = [
                (LLMProvider.openai.keychainAccount, openaiKey),
                (LLMProvider.anthropic.keychainAccount, anthropicKey),
                (LLMProvider.zai.keychainAccount, zaiKey),
                ("tavily_api_key", tavilyKey),
                ("fal_api_key", falKey),
            ]
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
