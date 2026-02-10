import SwiftUI

struct InputBar: View {
    @EnvironmentObject var viewModel: DochiViewModel

    @State private var inputText: String = ""
    @State private var glowPulse = false
    @State private var glowFlash = false
    @State private var previousTranscript = ""

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            if viewModel.isConnected { micButton }

            if isListening {
                listeningContent
            } else {
                textInputContent
            }
        }
        .padding(barPadding)
        .background(.bar)
        .overlay(listeningGlow)
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
            glowFlash = true
            withAnimation(.easeOut(duration: 0.3)) { glowFlash = false }
        }
    }

    // MARK: - Subviews

    private var micButton: some View {
        Button {
            if isListening { viewModel.stopListening() } else { viewModel.startListening() }
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
        HStack(spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("듣는 중...").compact(AppFont.caption).foregroundStyle(.secondary)
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
        HStack(spacing: AppSpacing.m) {
            // Input field container for better affordance
            HStack {
                TextField("메시지를 입력하세요...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit { submitText() }
                    .accessibilityIdentifier("input.textField")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .fill(AppColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.border, lineWidth: 1)
            )

            if isResponding {
                Button { viewModel.cancelResponse() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("응답 취소")
            } else {
                Button { submitText() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary : Color.blue
                        )
                }
                .buttonStyle(.borderless)
                .disabled(sendDisabled)
                .accessibilityIdentifier("input.send")
            }
        }
    }

    @ViewBuilder
    private var listeningGlow: some View {
        if isListening {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .fill(Color.orange.opacity(0.06))
                .shadow(
                    color: .orange.opacity(glowFlash ? 0.6 : (glowPulse ? 0.4 : 0.1)),
                    radius: glowFlash ? 16 : (glowPulse ? 12 : 4)
                )
        }
    }

    // MARK: - Helpers

    private var isListening: Bool { viewModel.state == .listening }

    private var isResponding: Bool {
        switch viewModel.state {
        case .processing, .executingTool, .speaking: return true
        case .idle, .listening: return false
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

    private var barPadding: CGFloat { viewModel.settings.uiDensity == .compact ? AppSpacing.s : 16 }
}
