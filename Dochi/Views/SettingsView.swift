import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var zaiKey: String = ""
    @State private var showInstructionEditor = false
    @State private var showContextEditor = false

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
                // MARK: - Mode
                Section("모드") {
                    Picker("앱 모드", selection: modeBinding) {
                        ForEach(AppMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

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

                // MARK: - Text Mode Settings
                if viewModel.settings.appMode == .text {
                    Section("텍스트 모드 — LLM") {
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

                    Section("텍스트 모드 — TTS") {
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
                }

                // MARK: - Realtime Mode Settings
                if viewModel.settings.appMode == .realtime {
                    Section("리얼타임 모드 — 음성") {
                        Picker("음성", selection: $viewModel.settings.voice) {
                            ForEach(AppSettings.availableVoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                    }
                }

                // MARK: - Instructions
                Section("인스트럭션") {
                    VStack(alignment: .leading) {
                        Text(viewModel.settings.instructions.isEmpty
                             ? "시스템 프롬프트가 설정되지 않았습니다."
                             : viewModel.settings.instructions)
                            .font(.body)
                            .foregroundStyle(
                                viewModel.settings.instructions.isEmpty ? .tertiary : .primary
                            )
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("편집") {
                            showInstructionEditor = true
                        }
                    }
                }

                // MARK: - Long-term Context
                Section("장기 기억") {
                    VStack(alignment: .leading) {
                        let context = ContextService.load()
                        Text(context.isEmpty
                             ? "저장된 컨텍스트가 없습니다. 대화 종료 시 자동으로 기억할 정보가 추가됩니다."
                             : context)
                            .font(.body)
                            .foregroundStyle(context.isEmpty ? .tertiary : .primary)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button("편집") {
                                showContextEditor = true
                            }
                            if !context.isEmpty {
                                Button("초기화", role: .destructive) {
                                    ContextService.save("")
                                }
                            }
                            Spacer()
                            Text("\(ContextService.size / 1024)KB / \(viewModel.settings.contextMaxSize / 1024)KB")
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
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            openaiKey = viewModel.settings.apiKey
            anthropicKey = viewModel.settings.anthropicApiKey
            zaiKey = viewModel.settings.zaiApiKey
        }
        .sheet(isPresented: $showInstructionEditor) {
            InstructionEditorView(instructions: $viewModel.settings.instructions)
        }
        .sheet(isPresented: $showContextEditor) {
            ContextEditorView()
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

    private var modeBinding: Binding<AppMode> {
        Binding(
            get: { viewModel.settings.appMode },
            set: { viewModel.switchMode(to: $0) }
        )
    }
}

struct InstructionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var instructions: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("인스트럭션 편집")
                    .font(.headline)
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            Divider()
            TextEditor(text: $instructions)
                .font(.system(.body, design: .monospaced))
                .padding(8)
        }
        .frame(width: 500, height: 400)
    }
}

struct ContextEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("장기 기억 편집")
                    .font(.headline)
                Spacer()
                Button("저장") {
                    ContextService.save(content)
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
                Text(ContextService.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(8)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            content = ContextService.load()
        }
    }
}
