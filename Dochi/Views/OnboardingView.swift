import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var openaiKey = ""
    @State private var anthropicKey = ""

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i <= step ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)

            Spacer()

            Group {
                switch step {
                case 0:
                    welcomeStep
                case 1:
                    apiKeyStep
                default:
                    completeStep
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Navigation buttons
            HStack {
                if step > 0 {
                    Button("이전") {
                        withAnimation { step -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if step < 2 {
                    Button(step == 1 ? "다음" : "시작하기") {
                        if step == 1 {
                            applyApiKeys()
                        }
                        withAnimation { step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("완료") {
                        setupDefaultAgent()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("도치에 오신 걸 환영합니다!")
                .font(.title2.bold())

            Text("AI 음성 비서 도치를 설정해봅시다.\n간단한 설정만 하면 바로 사용할 수 있어요.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("API 키 설정")
                .font(.title2.bold())

            Text("하나 이상의 API 키를 입력하세요.\n나중에 설정에서 변경할 수 있습니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI API 키")
                        .font(.caption.bold())
                    SecureField("sk-...", text: $openaiKey)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Anthropic API 키")
                        .font(.caption.bold())
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal, 40)
        }
        .padding(.horizontal, 40)
    }

    private var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("준비 완료!")
                .font(.title2.bold())

            Text("\"도치야\"라고 불러보세요.\n도치가 응답할 준비가 되어 있습니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func applyApiKeys() {
        if !openaiKey.isEmpty {
            viewModel.settings.apiKey = openaiKey
        }
        if !anthropicKey.isEmpty {
            viewModel.settings.anthropicApiKey = anthropicKey
        }
    }

    private func setupDefaultAgent() {
        let contextService = viewModel.settings.contextService
        let agents = contextService.listAgents()
        if agents.isEmpty {
            contextService.createAgent(
                name: Constants.Agent.defaultName,
                wakeWord: Constants.Agent.defaultWakeWord,
                description: Constants.Agent.defaultDescription
            )
            if contextService.loadBaseSystemPrompt().isEmpty {
                contextService.saveBaseSystemPrompt(Constants.Agent.defaultBaseSystemPrompt)
            }
        }
    }
}
