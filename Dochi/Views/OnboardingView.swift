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
    @State private var selectedOperatingProfile: OperatingProfile = .familyHomeAssistant
    @State private var isValidatingKey = false
    @State private var errorMessage: String?
    @State private var showFeatureTour = false
    @State private var quickSeedEnabled = true
    @State private var quickSeedStatus: QuickSeedStatus = .idle
    @State private var isCreatingQuickSeed = false
    @State private var didPersistSettings = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case provider
        case apiKey
        case profile
        case operatingProfile
        case agent
        case complete
    }

    enum QuickSeedStatus {
        case idle
        case success(String)
        case failure(String)
    }

    var body: some View {
        Group {
            if showFeatureTour {
                FeatureTourView(
                    onComplete: {
                        settings.featureTourCompleted = true
                        showFeatureTour = false
                        onComplete()
                    },
                    onSkip: {
                        settings.featureTourCompleted = true
                        settings.featureTourSkipped = true
                        showFeatureTour = false
                        onComplete()
                    }
                )
            } else {
                onboardingContent
            }
        }
    }

    private var onboardingContent: some View {
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
                case .operatingProfile:
                    operatingProfileStep
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
                    // 완료 단계: 두 가지 선택지
                    Button("시작하기") {
                        finishOnboarding()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isCreatingQuickSeed)

                    Button("기능 둘러보기") {
                        finishOnboardingAndStartTour()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isCreatingQuickSeed)
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

    private var operatingProfileStep: some View {
        VStack(spacing: 16) {
            Text("운영 프로필 선택")
                .font(.title2)
                .fontWeight(.semibold)

            Text("도치가 어떤 역할을 기본으로 수행할지 선택해주세요.\n선택하지 않으면 가족 홈 어시스턴트로 시작합니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                operatingProfileOption(.familyHomeAssistant)
                operatingProfileOption(.personalProductivityAssistant)
            }

            Button("기본값으로 계속 (가족형)") {
                selectedOperatingProfile = .familyHomeAssistant
                advanceStep()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    private func operatingProfileOption(_ profile: OperatingProfile) -> some View {
        Button {
            selectedOperatingProfile = profile
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .fontWeight(.medium)
                    Text(profile.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedOperatingProfile == profile {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .background(selectedOperatingProfile == profile ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
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
                settingRow("운영 프로필", value: selectedOperatingProfile.displayName)
                settingRow("에이전트", value: agentName)
                settingRow("대화 모드", value: interactionMode == .voiceAndText ? "음성 + 텍스트" : "텍스트만")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("온보딩 종료 시 Quick Seed 자동 생성", isOn: $quickSeedEnabled)
                    .toggleStyle(.checkbox)

                Text("생성 순서: 미리알림 → 칸반 → 자동화 (최소 1개)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isCreatingQuickSeed {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Quick Seed 생성 중...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                quickSeedStatusView
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(10)

            Text("설정은 나중에 언제든 변경할 수 있습니다.\n\"기능 둘러보기\"를 눌러 도치의 기능을 알아보세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

    @ViewBuilder
    private var quickSeedStatusView: some View {
        switch quickSeedStatus {
        case .idle:
            EmptyView()
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Quick Seed 생성 실패", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("다시 시도") {
                        Task { await retryQuickSeed() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCreatingQuickSeed)

                    Button("Seed 없이 시작") {
                        Task { await completeOnboarding(startFeatureTour: false, forceSkipQuickSeed: true) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCreatingQuickSeed)

                    Button("Seed 없이 둘러보기") {
                        Task { await completeOnboarding(startFeatureTour: true, forceSkipQuickSeed: true) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCreatingQuickSeed)
                }
            }
        }
    }

    // MARK: - Logic

    private var canAdvance: Bool {
        switch step {
        case .welcome, .profile, .operatingProfile, .agent, .complete:
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

        // Save key immediately and block step transition on failure.
        switch KeychainWriteCoordinator.saveRequiredValue(
            apiKey,
            account: selectedProvider.keychainAccount,
            keychain: keychainService
        ) {
        case .success:
            break
        case .failure(let error):
            errorMessage = "API 키 저장 실패: \(error.localizedDescription)"
            return
        }

        withAnimation {
            step = .profile
        }
    }

    private func defaultModel(for provider: LLMProvider) -> String {
        provider.onboardingDefaultModel
    }

    private func persistSettings() {
        settings.llmProvider = selectedProvider.rawValue
        settings.llmModel = defaultModel(for: selectedProvider)
        settings.activeAgentName = agentName.isEmpty ? "도치" : agentName
        settings.interactionMode = interactionMode.rawValue
        settings.operatingProfile = selectedOperatingProfile.rawValue

        // Create first user profile if name provided
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let profile = UserProfile(name: trimmedName)
            contextService.saveProfiles([profile])
            settings.defaultUserId = profile.id.uuidString
            Log.app.info("Created initial user profile: \(trimmedName)")
        }
    }

    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
    }

    private func finishOnboarding() {
        Task { await completeOnboarding(startFeatureTour: false) }
    }

    private func finishOnboardingAndStartTour() {
        Task { await completeOnboarding(startFeatureTour: true) }
    }

    private func retryQuickSeed() async {
        isCreatingQuickSeed = true
        let result = await createQuickSeed()
        isCreatingQuickSeed = false

        switch result {
        case .success(let message):
            quickSeedStatus = .success(message)
        case .failure(let message):
            quickSeedStatus = .failure(message)
        }
    }

    private func completeOnboarding(startFeatureTour: Bool, forceSkipQuickSeed: Bool = false) async {
        persistSettingsIfNeeded()

        if quickSeedEnabled && !forceSkipQuickSeed {
            if case .success = quickSeedStatus {
                // Seed already prepared; don't create duplicates.
            } else {
                isCreatingQuickSeed = true
                let result = await createQuickSeed()
                isCreatingQuickSeed = false

                switch result {
                case .success(let message):
                    quickSeedStatus = .success(message)
                case .failure(let message):
                    quickSeedStatus = .failure(message)
                    return
                }
            }
        }

        markOnboardingComplete()
        if startFeatureTour {
            withAnimation {
                showFeatureTour = true
            }
        } else {
            onComplete()
        }
    }

    private enum QuickSeedCreationResult {
        case success(String)
        case failure(String)
    }

    private enum SeedAttemptResult {
        case success(String)
        case failure(String)
    }

    private func createQuickSeed() async -> QuickSeedCreationResult {
        var errors: [String] = []

        switch await createReminderSeed() {
        case .success(let message):
            return .success(message)
        case .failure(let error):
            errors.append("미리알림 실패: \(error)")
        }

        switch createKanbanSeed() {
        case .success(let message):
            return .success(message)
        case .failure(let error):
            errors.append("칸반 실패: \(error)")
        }

        switch createAutomationSeed() {
        case .success(let message):
            return .success(message)
        case .failure(let error):
            errors.append("자동화 실패: \(error)")
        }

        return .failure(errors.joined(separator: "\n"))
    }

    private func createReminderSeed() async -> SeedAttemptResult {
        let title = "도치 첫 실행 체크"
        let notes = "온보딩 Quick Seed로 생성된 미리알림입니다."

        let script = """
        tell application "Reminders"
            if (count of lists) is 0 then
                make new list with properties {name:"Dochi"}
            end if
            set targetList to first list
            set seedTitle to "\(CreateReminderTool.escapeAppleScript(title))"
            set existingReminders to (every reminder of targetList whose name is seedTitle)
            if (count of existingReminders) is 0 then
                make new reminder at end of targetList with properties {name:seedTitle, body:"\(CreateReminderTool.escapeAppleScript(notes))"}
                return "CREATED"
            end if
            return "EXISTS"
        end tell
        """

        let result = await runAppleScript(script)
        switch result {
        case .success:
            return .success("Quick Seed 준비 완료: 미리알림 1개")
        case .failure(let error):
            return .failure(error.message)
        }
    }

    private func createKanbanSeed() -> SeedAttemptResult {
        let boardName = "온보딩 Quick Seed"
        let cardTitle = "오늘 시작할 일 1개 정하기"

        let existingBoard = KanbanManager.shared
            .listBoards()
            .first { $0.name == boardName }

        let board = existingBoard ?? KanbanManager.shared.createBoard(name: boardName)
        if board.cards.contains(where: { $0.title == cardTitle }) {
            return .success("Quick Seed 준비 완료: 칸반 1개")
        }

        guard KanbanManager.shared.addCard(
            boardId: board.id,
            title: cardTitle,
            column: board.columns.first,
            priority: .medium,
            description: "온보딩에서 자동 생성된 시작 카드",
            labels: ["온보딩"]
        ) != nil else {
            return .failure("카드 생성에 실패했습니다.")
        }

        return .success("Quick Seed 준비 완료: 칸반 1개")
    }

    private func createAutomationSeed() -> SeedAttemptResult {
        let scheduleName = "온보딩 Quick Seed 브리핑"
        let scheduler = SchedulerService(settings: settings)
        scheduler.loadSchedules()

        if scheduler.schedules.contains(where: { $0.name == scheduleName }) {
            return .success("Quick Seed 준비 완료: 자동화 1개")
        }

        let schedule = ScheduleEntry(
            name: scheduleName,
            icon: "🌱",
            cronExpression: "0 9 * * *",
            prompt: "오늘 일정과 할 일을 보고 가장 먼저 시작할 1개를 제안해줘",
            agentName: settings.activeAgentName.isEmpty ? "도치" : settings.activeAgentName
        )
        scheduler.addSchedule(schedule)

        return .success("Quick Seed 준비 완료: 자동화 1개")
    }

    private func persistSettingsIfNeeded() {
        guard !didPersistSettings else { return }
        persistSettings()
        didPersistSettings = true
    }
}
