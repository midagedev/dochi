import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: DochiViewModel

    @State private var showSettings = false
    @State private var showChangelog = false
    @State private var showOnboarding = false
    @State private var inputText = ""
    @State private var glowPulse = false
    @State private var glowFlash = false
    @State private var previousTranscript = ""

    private let changelogService = ChangelogService()

    var body: some View {
        NavigationSplitView {
            SidebarView(showSettings: $showSettings)
        } detail: {
            VStack(spacing: 0) {
                toolbarArea
                if !viewModel.builtInToolService.activeAlarms.isEmpty {
                    ActiveAlarmsBar()
                }
                Divider()
                ConversationView()
                Divider()
                inputArea
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogView(changelogService: changelogService, showFullChangelog: false)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onAppear {
            viewModel.connectOnLaunch()
            checkForNewVersion()
        }
    }

    private func checkForNewVersion() {
        if changelogService.hasNewVersion {
            // 약간 딜레이 후 표시 (앱 로딩 완료 후)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showChangelog = true
            }
        } else if changelogService.isFirstLaunch {
            changelogService.markCurrentVersionAsSeen()
            // 첫 실행 시 온보딩 표시
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showOnboarding = true
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarArea: some View {
        HStack(spacing: 12) {
            // Connection toggle
            Button {
                viewModel.toggleConnection()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)
                    Text(connectionLabel)
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)

            // State indicator
            if viewModel.isConnected {
                if isWakeWordActive {
                    WakeWordIndicator(wakeWord: viewModel.settings.wakeWord)
                } else {
                    Text(stateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let error = currentError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            // 자동종료 토글
            if viewModel.isConnected {
                Button {
                    viewModel.autoEndSession.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.autoEndSession ? "timer" : "timer.circle")
                            .font(.caption)
                        Text("자동종료")
                            .font(.caption)
                    }
                    .foregroundStyle(viewModel.autoEndSession ? .primary : .tertiary)
                }
                .buttonStyle(.borderless)
                .help(viewModel.autoEndSession ? "자동종료 켜짐: 무응답 시 대화 종료" : "자동종료 꺼짐: 무응답 시 계속 듣기")
            }

            // Voice indicator
            if isResponding {
                HStack(spacing: 4) {
                    AudioBarsView()
                    Text("응답 중")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var connectionColor: Color {
        switch viewModel.supertonicService.state {
        case .unloaded: return .red
        case .loading: return .yellow
        case .ready:
            switch viewModel.state {
            case .idle: return .green
            case .listening: return .orange
            case .processing: return .blue
            case .executingTool: return .cyan
            case .speaking: return .purple
            }
        case .synthesizing: return .blue
        case .playing: return .purple
        }
    }

    private var connectionLabel: String {
        switch viewModel.supertonicService.state {
        case .unloaded: return "연결"
        case .loading: return "로딩 중..."
        case .ready, .synthesizing, .playing: return "연결됨"
        }
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle: return "대기 중"
        case .listening: return "듣는 중..."
        case .processing: return "응답 생성 중..."
        case .executingTool(let name): return "\(name) 실행 중..."
        case .speaking: return "음성 재생 중..."
        }
    }

    private var currentError: String? {
        viewModel.errorMessage ?? viewModel.llmService.error ?? viewModel.supertonicService.error
    }

    private var isWakeWordActive: Bool {
        viewModel.speechService.state == .waitingForWakeWord
    }

    private var isResponding: Bool {
        switch viewModel.state {
        case .processing, .executingTool, .speaking: return true
        case .idle, .listening: return false
        }
    }

    // MARK: - Input Area

    private var isListening: Bool {
        viewModel.state == .listening
    }

    private var inputArea: some View {
        HStack(spacing: 12) {
            // 마이크 버튼 (연결 시)
            if viewModel.isConnected {
                micButton
            }

            if isListening {
                listeningContent
            } else {
                textInputContent
            }
        }
        .padding()
        .background(listeningGlow)
        .animation(.easeInOut(duration: 0.3), value: isListening)
        .onChange(of: isListening) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
                previousTranscript = ""
            } else {
                glowPulse = false
                glowFlash = false
            }
        }
        .onChange(of: viewModel.speechService.transcript) { oldValue, newValue in
            guard isListening, !newValue.isEmpty, newValue != oldValue else { return }
            // 트랜스크립트 변경 시 반짝임
            glowFlash = true
            withAnimation(.easeOut(duration: 0.3)) {
                glowFlash = false
            }
        }
    }

    private var micButton: some View {
        Button {
            if isListening {
                viewModel.stopListening()
            } else {
                viewModel.startListening()
            }
        } label: {
            ZStack {
                if isListening {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .scaleEffect(glowPulse ? 1.4 : 1.0)
                        .opacity(glowPulse ? 0.0 : 0.6)
                }
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.title2)
                    .foregroundStyle(isListening ? .orange : .secondary)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless)
    }

    private var listeningContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("듣는 중...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !viewModel.speechService.transcript.isEmpty {
                    Text(viewModel.speechService.transcript)
                        .font(.body)
                        .lineLimit(3)
                        .truncationMode(.head)
                }
            }
            Spacer()
            AudioBarsView()
        }
    }

    private var textInputContent: some View {
        HStack(spacing: 12) {
            TextField("메시지를 입력하세요...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit { submitText() }

            if isResponding {
                Button {
                    viewModel.cancelResponse()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("응답 취소")
            } else {
                Button {
                    submitText()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary : Color.blue
                        )
                }
                .buttonStyle(.borderless)
                .disabled(sendDisabled)
            }
        }
    }

    @ViewBuilder
    private var listeningGlow: some View {
        if isListening {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.06))
                .shadow(
                    color: .orange.opacity(glowFlash ? 0.6 : (glowPulse ? 0.4 : 0.1)),
                    radius: glowFlash ? 16 : (glowPulse ? 12 : 4)
                )
        }
    }

    private var sendDisabled: Bool {
        let empty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let provider = viewModel.settings.llmProvider
        let hasKey = !viewModel.settings.apiKey(for: provider).isEmpty
        return empty || !hasKey || viewModel.state == .processing
    }

    private func submitText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        viewModel.sendMessage(text)
    }
}

// MARK: - Wake Word Indicator

struct WakeWordIndicator: View {
    let wakeWord: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.mint.opacity(0.25))
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)
                Image(systemName: "ear")
                    .font(.caption)
                    .foregroundStyle(.mint)
            }
            Text("\"\(wakeWord)\" 대기 중")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .onDisappear { pulse = false }
    }
}

// MARK: - Active Alarms Bar

struct ActiveAlarmsBar: View {
    @EnvironmentObject var viewModel: DochiViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 8) {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                ForEach(viewModel.builtInToolService.activeAlarms) { alarm in
                    HStack(spacing: 4) {
                        Text(alarm.label)
                            .font(.caption)
                            .lineLimit(1)
                        Text(remainingText(alarm.fireDate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.1), in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    private func remainingText(_ fireDate: Date) -> String {
        let remaining = max(0, Int(fireDate.timeIntervalSinceNow))
        if remaining >= 3600 {
            let h = remaining / 3600
            let m = (remaining % 3600) / 60
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", remaining % 60))"
        } else if remaining >= 60 {
            let m = remaining / 60
            let s = remaining % 60
            return "\(m):\(String(format: "%02d", s))"
        } else {
            return "\(remaining)초"
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Binding var showSettings: Bool
    @State private var showSystemEditor = false
    @State private var showBasePromptEditor = false
    @State private var showAgentPersonaEditor = false
    @State private var showMemoryEditor = false
    @State private var showFamilyMemoryEditor = false
    @State private var showAgentMemoryEditor = false
    @State private var editingUserMemoryProfile: UserProfile?

    private var contextService: ContextServiceProtocol {
        viewModel.settings.contextService
    }

    var body: some View {
        List {
            Section("에이전트") {
                // 에이전트 페르소나
                Button {
                    showAgentPersonaEditor = true
                } label: {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            let agentName = viewModel.settings.activeAgentName
                            Text(agentName)
                                .font(.body)
                            let persona = contextService.loadAgentPersona(agentName: agentName)
                            Text(persona.isEmpty ? "페르소나 미설정" : persona)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                // 에이전트 기억
                Button {
                    showAgentMemoryEditor = true
                } label: {
                    HStack {
                        Image(systemName: "brain")
                            .foregroundStyle(.mint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("에이전트 기억")
                                .font(.body)
                            let agentMemory = contextService.loadAgentMemory(agentName: viewModel.settings.activeAgentName)
                            Text(agentMemory.isEmpty ? "비어 있음" : "\(agentMemory.components(separatedBy: .newlines).filter { !$0.isEmpty }.count)개 항목")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Section("시스템 프롬프트") {
                // 앱 레벨 기본 규칙
                Button {
                    showBasePromptEditor = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("기본 규칙")
                                .font(.body)
                            let basePrompt = contextService.loadBaseSystemPrompt()
                            Text(basePrompt.isEmpty ? "설정되지 않음" : basePrompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                // 레거시 system.md (존재하는 경우만 표시)
                let legacySystem = contextService.loadSystem()
                if !legacySystem.isEmpty {
                    Button {
                        showSystemEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("system.md (레거시)")
                                    .font(.body)
                                Text(legacySystem)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            let profiles = contextService.loadProfiles()
            if profiles.isEmpty {
                // 레거시 모드: 단일 사용자 기억
                Section("사용자 기억") {
                    Button {
                        showMemoryEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "brain")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("memory.md")
                                    .font(.body)
                                let memory = contextService.loadMemory()
                                Text(memory.isEmpty ? "비어 있음" : "\(memory.components(separatedBy: .newlines).filter { !$0.isEmpty }.count)개 항목")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // 다중 사용자 모드: 가족 기억 + 개인 기억
                Section("기억") {
                    Button {
                        showFamilyMemoryEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "house")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("가족 공유")
                                    .font(.body)
                                let family = contextService.loadFamilyMemory()
                                Text(family.isEmpty ? "비어 있음" : "\(family.components(separatedBy: .newlines).filter { !$0.isEmpty }.count)개 항목")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(profiles) { profile in
                        Button {
                            editingUserMemoryProfile = profile
                        } label: {
                            HStack {
                                Image(systemName: "brain")
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.body)
                                    let userMem = contextService.loadUserMemory(userId: profile.id)
                                    Text(userMem.isEmpty ? "비어 있음" : "\(userMem.components(separatedBy: .newlines).filter { !$0.isEmpty }.count)개 항목")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 현재 사용자 표시
            if let userName = viewModel.currentUserName {
                Section("현재 사용자") {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.green)
                        Text(userName)
                            .font(.body)
                    }
                }
            }

            Section("대화") {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Label("새 대화", systemImage: "plus.circle")
                }
                if !viewModel.messages.isEmpty {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(.blue)
                        Text("현재 대화")
                            .font(.body)
                        Spacer()
                        Text("\(viewModel.messages.count)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("대화 기록") {
                if viewModel.conversations.isEmpty {
                    Text("저장된 대화가 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.conversations) { conv in
                        Button {
                            viewModel.loadConversation(conv)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conv.title)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(conv.updatedAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.currentConversationId == conv.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteConversation(id: conv.id)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showSystemEditor) {
            SystemEditorView(contextService: contextService)
        }
        .sheet(isPresented: $showBasePromptEditor) {
            BasePromptEditorView(contextService: contextService)
        }
        .sheet(isPresented: $showAgentPersonaEditor) {
            AgentPersonaEditorView(contextService: contextService, agentName: viewModel.settings.activeAgentName)
        }
        .sheet(isPresented: $showAgentMemoryEditor) {
            AgentMemoryEditorView(contextService: contextService, agentName: viewModel.settings.activeAgentName)
        }
        .sheet(isPresented: $showMemoryEditor) {
            MemoryEditorView(contextService: contextService)
        }
        .sheet(isPresented: $showFamilyMemoryEditor) {
            FamilyMemoryEditorView(contextService: contextService)
        }
        .sheet(item: $editingUserMemoryProfile) { profile in
            UserMemoryEditorView(contextService: contextService, profile: profile)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showSettings = true
            } label: {
                Label("설정", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }
}
