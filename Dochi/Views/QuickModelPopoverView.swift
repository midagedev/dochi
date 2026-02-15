import SwiftUI

/// Quick model switching popover, triggered from SystemHealthBarView model indicator or Cmd+Shift+M.
struct QuickModelPopoverView: View {
    var settings: AppSettings
    var keychainService: KeychainServiceProtocol?
    var isOfflineFallbackActive: Bool = false

    @State private var selectedProviderRaw: String = ""
    @State private var selectedModel: String = ""
    @State private var ollamaModels: [LocalModelInfo] = []
    @State private var lmStudioModels: [LocalModelInfo] = []
    @State private var ollamaAvailable: Bool? = nil
    @State private var lmStudioAvailable: Bool? = nil

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: selectedProviderRaw) ?? .openai
    }

    private var availableModels: [String] {
        switch selectedProvider {
        case .ollama: return ollamaModels.map(\.name)
        case .lmStudio: return lmStudioModels.map(\.name)
        default: return selectedProvider.models
        }
    }

    private var currentLocalModels: [LocalModelInfo] {
        switch selectedProvider {
        case .ollama: return ollamaModels
        case .lmStudio: return lmStudioModels
        default: return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("빠른 모델 변경")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 2)

            Divider()

            // Provider selection with cloud/local grouping
            VStack(alignment: .leading, spacing: 6) {
                Text("클라우드")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                ForEach(LLMProvider.cloudProviders, id: \.self) { provider in
                    providerRow(provider)
                }

                Text("로컬")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.top, 4)

                ForEach(LLMProvider.localProviders, id: \.self) { provider in
                    providerRow(provider)
                }
            }

            Divider()

            // Model list
            VStack(alignment: .leading, spacing: 6) {
                Text("모델")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if availableModels.isEmpty {
                    if selectedProvider.isLocal {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("사용 가능한 모델이 없습니다")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            Text("서버가 실행 중인지 확인하세요")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("사용 가능한 모델이 없습니다")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    }
                } else {
                    ForEach(availableModels, id: \.self) { model in
                        modelRow(model)
                    }
                }
            }

            Divider()

            // Auto model selection toggle
            Toggle("자동 모델 선택 (라우팅)", isOn: Binding(
                get: { settings.taskRoutingEnabled },
                set: {
                    settings.taskRoutingEnabled = $0
                    Log.app.info("설정 변경: taskRoutingEnabled = \($0)")
                }
            ))
            .font(.system(size: 11))

            // Offline fallback info
            if settings.offlineFallbackEnabled {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: isOfflineFallbackActive ? "exclamationmark.triangle.fill" : "wifi.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(isOfflineFallbackActive ? .orange : .secondary)

                    if isOfflineFallbackActive {
                        Text("오프라인 모드 활성 중")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("오프라인 폴백")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if !settings.offlineFallbackModel.isEmpty {
                                Text("\(settings.offlineFallbackModel)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()
                }
            }

            Divider()

            // Footer: link to full settings
            HStack {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                        Text("설정에서 상세 설정 열기")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            selectedProviderRaw = settings.llmProvider
            selectedModel = settings.llmModel
            if selectedProvider == .ollama {
                fetchOllamaModels()
            } else if selectedProvider == .lmStudio {
                fetchLMStudioModels()
            }
            // Check local server availability for all local providers
            checkLocalServers()
        }
    }

    // MARK: - Provider Row

    @ViewBuilder
    private func providerRow(_ provider: LLMProvider) -> some View {
        let isSelected = selectedProvider == provider
        let hasKey = !provider.requiresAPIKey || hasAPIKey(for: provider)

        Button {
            guard hasKey else { return }
            selectedProviderRaw = provider.rawValue
            settings.llmProvider = provider.rawValue
            Log.app.info("설정 변경: llmProvider = \(provider.rawValue)")

            switch provider {
            case .ollama:
                fetchOllamaModels()
            case .lmStudio:
                fetchLMStudioModels()
            default:
                if !provider.models.contains(selectedModel) {
                    let newModel = provider.models.first ?? ""
                    selectedModel = newModel
                    settings.llmModel = newModel
                    Log.app.info("설정 변경: llmModel = \(newModel)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(provider.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(hasKey ? .primary : .secondary)

                if !hasKey {
                    Text("(키 없음)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // Local server connection indicator
                if provider.isLocal {
                    Spacer()
                    let available = provider == .ollama ? ollamaAvailable : lmStudioAvailable
                    if let available {
                        Circle()
                            .fill(available ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                    }
                } else {
                    Spacer()
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(!hasKey)
    }

    // MARK: - Model Row

    @ViewBuilder
    private func modelRow(_ model: String) -> some View {
        let isSelected = selectedModel == model
        let localInfo = currentLocalModels.first { $0.name == model }

        Button {
            selectedModel = model
            settings.llmModel = model
            Log.app.info("설정 변경: llmModel = \(model)")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(model)
                    .font(.system(size: 12))
                    .lineLimit(1)

                Spacer()

                // Local model metadata (compact)
                if let info = localInfo {
                    if let parameterSize = info.parameterSize {
                        Text(parameterSize)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if info.size > 0 {
                        Text(info.formattedSize)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if info.supportsTools {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    // Context window tokens for cloud models
                    let tokens = selectedProvider.contextWindowTokens(for: model)
                    Text("\(tokens / 1000)K")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func hasAPIKey(for provider: LLMProvider) -> Bool {
        guard let keychainService else { return true }
        guard provider.requiresAPIKey else { return true }
        let key = keychainService.load(account: provider.keychainAccount)
        return key != nil && !key!.isEmpty
    }

    private func fetchOllamaModels() {
        Task {
            let baseURL = URL(string: settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
            let infos = await OllamaModelFetcher.fetchModelInfos(baseURL: baseURL)
            ollamaModels = infos
            ollamaAvailable = await OllamaModelFetcher.isAvailable(baseURL: baseURL)
            if !infos.map(\.name).contains(selectedModel) {
                let newModel = infos.first?.name ?? ""
                selectedModel = newModel
                settings.llmModel = newModel
            }
        }
    }

    private func fetchLMStudioModels() {
        Task {
            let baseURL = URL(string: settings.lmStudioBaseURL) ?? URL(string: "http://localhost:1234")!
            let infos = await LMStudioModelFetcher.fetchModelInfos(baseURL: baseURL)
            lmStudioModels = infos
            lmStudioAvailable = await LMStudioModelFetcher.isAvailable(baseURL: baseURL)
            if !infos.map(\.name).contains(selectedModel) {
                let newModel = infos.first?.name ?? ""
                selectedModel = newModel
                settings.llmModel = newModel
            }
        }
    }

    private func checkLocalServers() {
        Task {
            let ollamaURL = URL(string: settings.ollamaBaseURL) ?? URL(string: "http://localhost:11434")!
            ollamaAvailable = await OllamaModelFetcher.isAvailable(baseURL: ollamaURL)

            let lmURL = URL(string: settings.lmStudioBaseURL) ?? URL(string: "http://localhost:1234")!
            lmStudioAvailable = await LMStudioModelFetcher.isAvailable(baseURL: lmURL)
        }
    }
}
