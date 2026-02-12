import SwiftUI

struct VoiceSettingsView: View {
    var settings: AppSettings
    var ttsService: TTSServiceProtocol?

    @State private var testPlaying = false

    var body: some View {
        Form {
            Section("TTS 음성") {
                Picker("음성", selection: Binding(
                    get: { settings.supertonicVoice },
                    set: { settings.supertonicVoice = $0 }
                )) {
                    ForEach(SupertonicVoice.allCases, id: \.self) { voice in
                        Text(voice.rawValue).tag(voice.rawValue)
                    }
                }

                HStack {
                    Text("속도: \(String(format: "%.1f", settings.ttsSpeed))x")
                    Slider(value: Binding(
                        get: { settings.ttsSpeed },
                        set: { settings.ttsSpeed = $0 }
                    ), in: 0.5...2.0, step: 0.1)
                }
            }

            Section("고급") {
                Stepper(
                    "Diffusion Steps: \(settings.ttsDiffusionSteps)",
                    value: Binding(
                        get: { settings.ttsDiffusionSteps },
                        set: { settings.ttsDiffusionSteps = $0 }
                    ),
                    in: 1...10
                )

                HStack {
                    Text("엔진 상태:")
                        .font(.subheadline)
                    Spacer()
                    engineStateLabel
                }
            }

            Section {
                Button {
                    testTTS()
                } label: {
                    HStack {
                        Image(systemName: testPlaying ? "speaker.wave.3.fill" : "play.circle")
                        Text(testPlaying ? "재생 중..." : "테스트 재생")
                    }
                }
                .disabled(testPlaying)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var engineStateLabel: some View {
        if let tts = ttsService {
            switch tts.engineState {
            case .unloaded:
                Label("미로드", systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .loading:
                Label("로딩 중", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .ready:
                Label("준비됨", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .error(let msg):
                Label("오류: \(msg)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func testTTS() {
        guard let tts = ttsService else { return }
        testPlaying = true
        tts.enqueueSentence("안녕하세요, 저는 도치입니다.")
        Task {
            try? await Task.sleep(for: .seconds(3))
            testPlaying = false
        }
    }
}
