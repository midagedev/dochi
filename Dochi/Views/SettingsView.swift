import SwiftUI

struct SettingsView: View {
    var settings: AppSettings
    var keychainService: KeychainServiceProtocol

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
        }
        .frame(width: 480, height: 340)
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
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Model Settings

struct ModelSettingsView: View {
    var settings: AppSettings

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: settings.llmProvider) ?? .openai
    }

    var body: some View {
        Form {
            Section("LLM 프로바이더") {
                Picker("프로바이더", selection: Binding(
                    get: { settings.llmProvider },
                    set: { newValue in
                        settings.llmProvider = newValue
                        // Reset model to first available when provider changes
                        let provider = LLMProvider(rawValue: newValue) ?? .openai
                        if !provider.models.contains(settings.llmModel) {
                            settings.llmModel = provider.models.first ?? ""
                        }
                    }
                )) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }

                Picker("모델", selection: Binding(
                    get: { settings.llmModel },
                    set: { settings.llmModel = $0 }
                )) {
                    ForEach(selectedProvider.models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            Section("컨텍스트") {
                HStack {
                    Text("최대 컨텍스트 크기")
                    Spacer()
                    Text("\(settings.contextMaxSize / 1000)K")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(settings.contextMaxSize) },
                    set: { settings.contextMaxSize = Int($0) }
                ), in: 10_000...200_000, step: 10_000)

                Toggle("자동 압축", isOn: Binding(
                    get: { settings.contextAutoCompress },
                    set: { settings.contextAutoCompress = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - API Key Settings

struct APIKeySettingsView: View {
    var keychainService: KeychainServiceProtocol

    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var zaiKey: String = ""
    @State private var saveStatus: String?
    @State private var showKeys: Bool = false

    var body: some View {
        Form {
            Section("API 키 관리") {
                Toggle("키 표시", isOn: $showKeys)

                apiKeyRow(label: "OpenAI", key: $openaiKey, account: LLMProvider.openai.keychainAccount)
                apiKeyRow(label: "Anthropic", key: $anthropicKey, account: LLMProvider.anthropic.keychainAccount)
                apiKeyRow(label: "Z.AI", key: $zaiKey, account: LLMProvider.zai.keychainAccount)
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
                .frame(width: 80, alignment: .leading)
            if showKeys {
                TextField("sk-...", text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            } else {
                SecureField("sk-...", text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            // Status indicator
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
    }

    private func saveAllKeys() {
        do {
            if !openaiKey.isEmpty {
                try keychainService.save(account: LLMProvider.openai.keychainAccount, value: openaiKey)
            }
            if !anthropicKey.isEmpty {
                try keychainService.save(account: LLMProvider.anthropic.keychainAccount, value: anthropicKey)
            }
            if !zaiKey.isEmpty {
                try keychainService.save(account: LLMProvider.zai.keychainAccount, value: zaiKey)
            }
            saveStatus = "저장 완료"
            Log.app.info("API keys saved")
        } catch {
            saveStatus = "저장 실패: \(error.localizedDescription)"
            Log.app.error("API key save failed: \(error.localizedDescription)")
        }

        // Clear status after delay
        Task {
            try? await Task.sleep(for: .seconds(3))
            saveStatus = nil
        }
    }
}
