import SwiftUI
import os

struct SettingsView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var zaiKey: String = ""
    @State private var tavilyKey: String = ""
    @State private var falaiKey: String = ""
    @State private var showSystemEditor = false
    @State private var showMemoryEditor = false
    @State private var showChangelog = false
    @State private var showAddMCPServer = false
    @State private var showAddProfile = false
    @State private var showFamilyMemoryEditor = false
    @State private var editingUserMemoryProfile: UserProfile?

    private let changelogService = ChangelogService()

    private var contextService: ContextServiceProtocol {
        viewModel.settings.contextService
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("설정")
                    .font(.headline)
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                // MARK: - API Keys
                Section("API 키") {
                    SecureField("OpenAI API 키", text: $openaiKey)
                        .onChange(of: openaiKey) { _, newValue in
                            viewModel.settings.apiKey = newValue
                        }
                    SecureField("Anthropic API 키", text: $anthropicKey)
                        .onChange(of: anthropicKey) { _, newValue in
                            viewModel.settings.anthropicApiKey = newValue
                        }
                    SecureField("Z.AI API 키", text: $zaiKey)
                        .onChange(of: zaiKey) { _, newValue in
                            viewModel.settings.zaiApiKey = newValue
                        }
                    SecureField("Tavily API 키 (웹검색)", text: $tavilyKey)
                        .onChange(of: tavilyKey) { _, newValue in
                            viewModel.settings.tavilyApiKey = newValue
                        }
                    SecureField("Fal.ai API 키 (이미지생성)", text: $falaiKey)
                        .onChange(of: falaiKey) { _, newValue in
                            viewModel.settings.falaiApiKey = newValue
                        }
                }

                // MARK: - LLM
                Section("LLM") {
                    Picker("제공자", selection: $viewModel.settings.llmProvider) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    Picker("모델", selection: $viewModel.settings.llmModel) {
                        ForEach(viewModel.settings.llmProvider.models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                // MARK: - Display
                Section("표시") {
                    HStack {
                        Text("글자 크기")
                        Slider(value: $viewModel.settings.chatFontSize, in: 12...28, step: 1)
                        Text("\(Int(viewModel.settings.chatFontSize))pt")
                            .font(.caption.monospacedDigit())
                            .frame(width: 36)
                    }
                    Text("가나다라마바사 ABC 123")
                        .font(.system(size: viewModel.settings.chatFontSize))
                        .foregroundStyle(.secondary)
                }

                // MARK: - STT
                Section("STT") {
                    HStack {
                        Text("무음 대기")
                        Slider(value: $viewModel.settings.sttSilenceTimeout, in: 0.5...3.0, step: 0.5)
                        Text(String(format: "%.1f초", viewModel.settings.sttSilenceTimeout))
                            .font(.caption.monospacedDigit())
                            .frame(width: 36)
                    }
                }

                // MARK: - TTS
                Section("TTS") {
                    Picker("음성", selection: $viewModel.settings.supertonicVoice) {
                        ForEach(SupertonicVoice.allCases, id: \.self) { voice in
                            Text(voice.displayName).tag(voice)
                        }
                    }
                    HStack {
                        Text("속도")
                        Slider(value: $viewModel.settings.ttsSpeed, in: 0.8...1.5, step: 0.05)
                        Text(String(format: "%.2f", viewModel.settings.ttsSpeed))
                            .font(.caption.monospacedDigit())
                            .frame(width: 36)
                    }
                    HStack {
                        Text("표현력")
                        Slider(value: diffusionStepsBinding, in: 4...20, step: 2)
                        Text("\(viewModel.settings.ttsDiffusionSteps)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 20)
                    }
                }

                // MARK: - System Prompt
                Section("시스템 프롬프트") {
                    VStack(alignment: .leading) {
                        let system = contextService.loadSystem()
                        Text(system.isEmpty
                             ? "페르소나와 행동 지침이 설정되지 않았습니다."
                             : system)
                            .font(.body)
                            .foregroundStyle(system.isEmpty ? .tertiary : .primary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button("편집") {
                                showSystemEditor = true
                            }
                            Spacer()
                            Text("system.md")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // MARK: - User Memory
                Section("사용자 기억") {
                    VStack(alignment: .leading) {
                        let memory = contextService.loadMemory()
                        Text(memory.isEmpty
                             ? "저장된 기억이 없습니다. 대화 종료 시 자동으로 추가됩니다."
                             : memory)
                            .font(.body)
                            .foregroundStyle(memory.isEmpty ? .tertiary : .primary)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button("편집") {
                                showMemoryEditor = true
                            }
                            if !memory.isEmpty {
                                Button("초기화", role: .destructive) {
                                    contextService.saveMemory("")
                                }
                            }
                            Spacer()
                            Text("\(contextService.memorySize / 1024)KB / \(viewModel.settings.contextMaxSize / 1024)KB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("자동 압축", isOn: $viewModel.settings.contextAutoCompress)
                    if viewModel.settings.contextAutoCompress {
                        HStack {
                            Text("최대 크기")
                            Slider(value: contextMaxSizeBinding, in: 5...50, step: 5)
                            Text("\(viewModel.settings.contextMaxSize / 1024)KB")
                                .font(.caption.monospacedDigit())
                                .frame(width: 40)
                        }
                    }
                }

                // MARK: - Family Profiles
                Section("가족 구성원") {
                    let profiles = contextService.loadProfiles()
                    if profiles.isEmpty {
                        Text("가족 구성원을 추가하면 사용자별 기억이 분리됩니다.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(profiles) { profile in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(profile.name)
                                            .font(.body)
                                        if viewModel.settings.defaultUserId == profile.id {
                                            Text("기본")
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(.blue.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    if !profile.aliases.isEmpty {
                                        Text("별칭: \(profile.aliases.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !profile.description.isEmpty {
                                        Text(profile.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    editingUserMemoryProfile = profile
                                } label: {
                                    Image(systemName: "brain")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .help("개인 기억 편집")
                                Button(role: .destructive) {
                                    deleteProfile(profile)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Picker("기본 사용자", selection: defaultUserBinding) {
                            Text("없음").tag(nil as UUID?)
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(profile.id as UUID?)
                            }
                        }

                        Button {
                            showFamilyMemoryEditor = true
                        } label: {
                            HStack {
                                Image(systemName: "house")
                                Text("가족 공유 기억 편집")
                            }
                        }
                    }

                    Button {
                        showAddProfile = true
                    } label: {
                        Label("구성원 추가", systemImage: "plus.circle")
                    }
                }

                // MARK: - MCP Servers
                Section("MCP 서버") {
                    if viewModel.settings.mcpServers.isEmpty {
                        Text("등록된 MCP 서버가 없습니다.")
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(viewModel.settings.mcpServers) { server in
                            MCPServerRow(
                                server: server,
                                isConnected: viewModel.mcpService.connectedServers[server.id] != nil,
                                onToggle: { enabled in
                                    var updated = server
                                    updated.isEnabled = enabled
                                    viewModel.settings.updateMCPServer(updated)
                                    if enabled {
                                        Task {
                                            do {
                                                try await viewModel.mcpService.connect(config: updated)
                                            } catch {
                                                Log.mcp.error("MCP 서버 연결 실패 (\(updated.name, privacy: .public)): \(error, privacy: .public)")
                                            }
                                        }
                                    } else {
                                        Task {
                                            await viewModel.mcpService.disconnect(serverId: server.id)
                                        }
                                    }
                                },
                                onDelete: {
                                    Task {
                                        await viewModel.mcpService.disconnect(serverId: server.id)
                                    }
                                    viewModel.settings.removeMCPServer(id: server.id)
                                }
                            )
                        }
                    }
                    Button {
                        showAddMCPServer = true
                    } label: {
                        Label("서버 추가", systemImage: "plus.circle")
                    }

                    if !viewModel.mcpService.availableTools.isEmpty {
                        DisclosureGroup("사용 가능한 도구 (\(viewModel.mcpService.availableTools.count)개)") {
                            ForEach(viewModel.mcpService.availableTools) { tool in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name)
                                        .font(.body.monospaced())
                                    if let desc = tool.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                // MARK: - Wake Word
                Section("웨이크워드") {
                    Toggle("웨이크워드 활성화", isOn: wakeWordBinding)
                    if viewModel.settings.wakeWordEnabled {
                        HStack {
                            Text("웨이크워드")
                            Spacer()
                            TextField("웨이크워드", text: $viewModel.settings.wakeWord)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                        }
                    }
                }

                // MARK: - Cloud
                if let supabase = viewModel.supabaseServiceForView {
                    CloudSettingsView(supabaseService: supabase)
                }

                if case .signedIn = viewModel.supabaseService.authState,
                   let device = viewModel.deviceServiceForView {
                    DeviceSettingsView(deviceService: device)
                }

                // MARK: - About
                Section("정보") {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text("v\(changelogService.currentVersion) (\(changelogService.currentBuild))")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showChangelog = true
                    } label: {
                        HStack {
                            Text("새로운 기능")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 750)
        .onAppear {
            openaiKey = viewModel.settings.apiKey
            anthropicKey = viewModel.settings.anthropicApiKey
            zaiKey = viewModel.settings.zaiApiKey
            tavilyKey = viewModel.settings.tavilyApiKey
            falaiKey = viewModel.settings.falaiApiKey
        }
        .sheet(isPresented: $showSystemEditor) {
            SystemEditorView(contextService: contextService)
        }
        .sheet(isPresented: $showMemoryEditor) {
            MemoryEditorView(contextService: contextService)
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogView(changelogService: changelogService, showFullChangelog: true)
        }
        .sheet(isPresented: $showAddMCPServer) {
            AddMCPServerView { config in
                viewModel.settings.addMCPServer(config)
                if config.isEnabled {
                    Task {
                        do {
                            try await viewModel.mcpService.connect(config: config)
                        } catch {
                            Log.mcp.error("MCP 서버 연결 실패 (\(config.name, privacy: .public)): \(error, privacy: .public)")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddProfile) {
            AddProfileView(contextService: contextService)
        }
        .sheet(isPresented: $showFamilyMemoryEditor) {
            FamilyMemoryEditorView(contextService: contextService)
        }
        .sheet(item: $editingUserMemoryProfile) { profile in
            UserMemoryEditorView(contextService: contextService, profile: profile)
        }
    }

    private var diffusionStepsBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.settings.ttsDiffusionSteps) },
            set: { viewModel.settings.ttsDiffusionSteps = Int($0) }
        )
    }

    private var contextMaxSizeBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.settings.contextMaxSize) / 1024.0 },
            set: { viewModel.settings.contextMaxSize = Int($0 * 1024) }
        )
    }

    private var defaultUserBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.settings.defaultUserId },
            set: { viewModel.settings.defaultUserId = $0 }
        )
    }

    private func deleteProfile(_ profile: UserProfile) {
        var profiles = contextService.loadProfiles()
        profiles.removeAll { $0.id == profile.id }
        contextService.saveProfiles(profiles)
        if viewModel.settings.defaultUserId == profile.id {
            viewModel.settings.defaultUserId = nil
        }
    }

    private var wakeWordBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.wakeWordEnabled },
            set: { enabled in
                viewModel.settings.wakeWordEnabled = enabled
                if enabled {
                    viewModel.startWakeWordIfNeeded()
                } else {
                    viewModel.stopWakeWord()
                }
            }
        )
    }
}

struct SystemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    let contextService: ContextServiceProtocol

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("시스템 프롬프트 편집")
                    .font(.headline)
                Spacer()
                Button("저장") {
                    contextService.saveSystem(content)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            Divider()
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding(8)
            Divider()
            HStack {
                Text("AI의 페르소나와 행동 지침을 정의합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(contextService.systemPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(8)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            content = contextService.loadSystem()
        }
    }
}

struct MemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    let contextService: ContextServiceProtocol

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("사용자 기억 편집")
                    .font(.headline)
                Spacer()
                Button("저장") {
                    contextService.saveMemory(content)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            Divider()
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding(8)
            Divider()
            HStack {
                Text("대화 종료 시 자동으로 기억할 정보가 추가됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(contextService.memoryPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(8)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            content = contextService.loadMemory()
        }
    }
}

// MARK: - MCP Server Row

struct MCPServerRow: View {
    let server: MCPServerConfig
    let isConnected: Bool
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color.green : (server.isEnabled ? Color.orange : Color.gray))
                        .frame(width: 8, height: 8)
                    Text(server.name)
                        .font(.body)
                }
                Text(server.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Add MCP Server View

struct AddMCPServerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var url: String = "http://"
    @State private var isEnabled: Bool = true

    let onAdd: (MCPServerConfig) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MCP 서버 추가")
                    .font(.headline)
                Spacer()
                Button("추가") {
                    let config = MCPServerConfig(
                        name: name.isEmpty ? "MCP Server" : name,
                        command: url,
                        isEnabled: isEnabled
                    )
                    onAdd(config)
                    dismiss()
                }
                .disabled(url.isEmpty || !isValidURL)
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                TextField("이름", text: $name, prompt: Text("MCP Server"))
                TextField("URL", text: $url, prompt: Text("http://localhost:8080"))
                    .textFieldStyle(.roundedBorder)
                if !url.isEmpty && !isValidURL {
                    Text("올바른 HTTP/HTTPS URL을 입력하세요")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("활성화", isOn: $isEnabled)
            }
            .formStyle(.grouped)
            .padding()

            Spacer()

            Divider()

            HStack {
                Text("현재 HTTP 기반 MCP 서버만 지원합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 400, height: 300)
    }

    private var isValidURL: Bool {
        guard let url = URL(string: url) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

// MARK: - Add Profile View

struct AddProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var aliasesText: String = ""
    @State private var description: String = ""
    let contextService: ContextServiceProtocol

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("가족 구성원 추가")
                    .font(.headline)
                Spacer()
                Button("추가") {
                    let aliases = aliasesText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let profile = UserProfile(name: name, aliases: aliases, description: description)
                    var profiles = contextService.loadProfiles()
                    profiles.append(profile)
                    contextService.saveProfiles(profiles)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                TextField("이름", text: $name, prompt: Text("예: 엄마, 아빠, 민수"))
                TextField("별칭", text: $aliasesText, prompt: Text("현철, 아빠"))
                TextField("설명", text: $description, prompt: Text("예: 가족 중 어머니"))
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 400, height: 250)
    }
}

// MARK: - Family Memory Editor View

struct FamilyMemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    let contextService: ContextServiceProtocol

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("가족 공유 기억 편집")
                    .font(.headline)
                Spacer()
                Button("저장") {
                    contextService.saveFamilyMemory(content)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            Divider()
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding(8)
            Divider()
            HStack {
                Text("가족 전체에 해당하는 공유 기억입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            content = contextService.loadFamilyMemory()
        }
    }
}

// MARK: - User Memory Editor View

struct UserMemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    let contextService: ContextServiceProtocol
    let profile: UserProfile

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(profile.name)의 개인 기억 편집")
                    .font(.headline)
                Spacer()
                Button("저장") {
                    contextService.saveUserMemory(userId: profile.id, content: content)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            Divider()
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding(8)
            Divider()
            HStack {
                Text("\(profile.name)에 대해 기억하고 있는 개인 정보입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            content = contextService.loadUserMemory(userId: profile.id)
        }
    }
}
