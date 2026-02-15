import SwiftUI

/// Quick model switching popover, triggered from SystemHealthBarView model indicator or Cmd+Shift+M.
struct QuickModelPopoverView: View {
    var settings: AppSettings
    var keychainService: KeychainServiceProtocol?

    @State private var selectedProviderRaw: String = ""
    @State private var selectedModel: String = ""
    @State private var ollamaModels: [String] = []

    private var selectedProvider: LLMProvider {
        LLMProvider(rawValue: selectedProviderRaw) ?? .openai
    }

    private var availableModels: [String] {
        if selectedProvider == .ollama {
            return ollamaModels
        }
        return selectedProvider.models
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("빠른 모델 변경")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 2)

            Divider()

            // Provider selection
            VStack(alignment: .leading, spacing: 6) {
                Text("프로바이더")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(LLMProvider.allCases, id: \.self) { provider in
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
                    Text("사용 가능한 모델이 없습니다")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
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
            }
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

            if provider == .ollama {
                fetchOllamaModels()
            } else if !provider.models.contains(selectedModel) {
                let newModel = provider.models.first ?? ""
                selectedModel = newModel
                settings.llmModel = newModel
                Log.app.info("설정 변경: llmModel = \(newModel)")
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

                Spacer()
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

                // Context window tokens
                let tokens = selectedProvider.contextWindowTokens(for: model)
                Text("\(tokens / 1000)K")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

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
            let models = await OllamaModelFetcher.fetchModels(baseURL: baseURL)
            ollamaModels = models
            if !models.contains(selectedModel) {
                let newModel = models.first ?? ""
                selectedModel = newModel
                settings.llmModel = newModel
            }
        }
    }
}
