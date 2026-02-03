import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var zaiKey: String = ""
    @State private var showSystemEditor = false
    @State private var showMemoryEditor = false
    @State private var showChangelog = false

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
        .frame(width: 500, height: 650)
        .onAppear {
            openaiKey = viewModel.settings.apiKey
            anthropicKey = viewModel.settings.anthropicApiKey
            zaiKey = viewModel.settings.zaiApiKey
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
