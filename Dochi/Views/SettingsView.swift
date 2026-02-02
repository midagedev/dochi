import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var zaiKey: String = ""
    @State private var showInstructionEditor = false

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

                    Section("텍스트 모드 — TTS 음성") {
                        Picker("Supertonic 음성", selection: $viewModel.settings.supertonicVoice) {
                            ForEach(SupertonicVoice.allCases, id: \.self) { voice in
                                Text(voice.displayName).tag(voice)
                            }
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

                // MARK: - Wake Word
                Section("웨이크워드") {
                    HStack {
                        Text("웨이크워드")
                        Spacer()
                        TextField("웨이크워드", text: $viewModel.settings.wakeWord)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
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
