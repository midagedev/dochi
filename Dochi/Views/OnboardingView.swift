import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    let settings: AppSettings
    let keychainService: KeychainServiceProtocol
    let contextService: ContextServiceProtocol
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var selectedProvider: LLMProvider = .openai
    @State private var apiKey: String = ""
    @State private var userName: String = ""
    @State private var agentName: String = "도치"
    @State private var interactionMode: InteractionMode = .voiceAndText
    @State private var isValidatingKey = false
    @State private var errorMessage: String?

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case provider
        case apiKey
        case profile
        case agent
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<OnboardingStep.allCases.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()

            // Content
            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .provider:
                    providerStep
                case .apiKey:
                    apiKeyStep
                case .profile:
                    profileStep
                case .agent:
                    agentStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: 480)
            .padding(32)

            Spacer()

            // Navigation
            HStack {
                if step.rawValue > 0 && step != .complete {
                    Button("이전") {
                        withAnimation { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if step == .complete {
                    Button("시작하기") {
                        finishOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(step == .apiKey ? "확인" : "다음") {
                        advanceStep()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isValidatingKey || !canAdvance)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 480)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("도치에 오신 것을 환영합니다")
                .font(.title)
                .fontWeight(.bold)

            Text("AI 어시스턴트 도치를 설정해볼까요?\n음성과 텍스트로 대화하고, 다양한 도구를 활용할 수 있습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var providerStep: some View {
        VStack(spacing: 16) {
            Text("LLM 프로바이더 선택")
                .font(.title2)
                .fontWeight(.semibold)

            Text("사용할 AI 모델 프로바이더를 선택해주세요.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                providerOption(.openai, title: "OpenAI", subtitle: "GPT-4o, GPT-4o-mini, o3-mini")
                providerOption(.anthropic, title: "Anthropic", subtitle: "Claude Sonnet 4.5, Claude Opus 4.6")
                providerOption(.zai, title: "Z.AI", subtitle: "GLM-4 Plus")
            }
        }
    }

    private func providerOption(_ provider: LLMProvider, title: String, subtitle: String) -> some View {
        Button {
            selectedProvider = provider
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selectedProvider == provider {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .background(selectedProvider == provider ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Text("API 키 입력")
                .font(.title2)
                .fontWeight(.semibold)

            Text("\(selectedProvider.rawValue.uppercased()) API 키를 입력해주세요.\n키는 macOS 키체인에 안전하게 저장됩니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("sk-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

            if isValidatingKey {
                ProgressView()
                    .scaleEffect(0.8)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var profileStep: some View {
        VStack(spacing: 16) {
            Text("프로필 설정")
                .font(.title2)
                .fontWeight(.semibold)

            Text("이름을 알려주세요. 도치가 대화할 때 사용합니다.")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField("이름", text: $userName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Picker("대화 모드", selection: $interactionMode) {
                Text("음성 + 텍스트").tag(InteractionMode.voiceAndText)
                Text("텍스트만").tag(InteractionMode.textOnly)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
        }
    }

    private var agentStep: some View {
        VStack(spacing: 16) {
            Text("에이전트 이름")
                .font(.title2)
                .fontWeight(.semibold)

            Text("AI 어시스턴트의 이름을 정해주세요.\n기본 이름은 '도치'입니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("에이전트 이름", text: $agentName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
        }
    }

    private var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("설정 완료!")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                settingRow("프로바이더", value: selectedProvider.rawValue.uppercased())
                settingRow("모델", value: defaultModel(for: selectedProvider))
                settingRow("이름", value: userName.isEmpty ? "(미설정)" : userName)
                settingRow("에이전트", value: agentName)
                settingRow("대화 모드", value: interactionMode == .voiceAndText ? "음성 + 텍스트" : "텍스트만")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(10)

            Text("설정은 나중에 언제든 변경할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func settingRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Logic

    private var canAdvance: Bool {
        switch step {
        case .welcome, .profile, .agent, .complete:
            return true
        case .provider:
            return true
        case .apiKey:
            return !apiKey.isEmpty
        }
    }

    private func advanceStep() {
        if step == .apiKey {
            validateAndAdvance()
            return
        }
        withAnimation {
            step = OnboardingStep(rawValue: step.rawValue + 1) ?? .complete
        }
    }

    private func validateAndAdvance() {
        guard !apiKey.isEmpty else { return }
        errorMessage = nil

        // Save key immediately
        let account = "\(selectedProvider.rawValue)_api_key"
        try? keychainService.save(account: account, value: apiKey)

        withAnimation {
            step = .profile
        }
    }

    private func defaultModel(for provider: LLMProvider) -> String {
        switch provider {
        case .openai: "gpt-4o"
        case .anthropic: "claude-sonnet-4-5-20250929"
        case .zai: "glm-4-plus"
        case .ollama: "llama3"
        }
    }

    private func finishOnboarding() {
        // Save all settings
        settings.llmProvider = selectedProvider.rawValue
        settings.llmModel = defaultModel(for: selectedProvider)
        settings.activeAgentName = agentName.isEmpty ? "도치" : agentName
        settings.interactionMode = interactionMode.rawValue

        // Create first user profile if name provided
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let profile = UserProfile(name: trimmedName)
            contextService.saveProfiles([profile])
            settings.defaultUserId = profile.id.uuidString
            Log.app.info("Created initial user profile: \(trimmedName)")
        }

        // Mark onboarding complete
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")

        onComplete()
    }
}
