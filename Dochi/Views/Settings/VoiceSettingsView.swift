import SwiftUI

struct VoiceSettingsView: View {
    var settings: AppSettings
    var keychainService: KeychainServiceProtocol?
    var ttsService: TTSServiceProtocol?

    @State private var testPlaying = false
    @State private var gcpAPIKey: String = ""
    @State private var saveStatus: String?

    var body: some View {
        Form {
            Section("TTS 프로바이더") {
                Picker("프로바이더", selection: Binding(
                    get: { settings.ttsProvider },
                    set: { settings.ttsProvider = $0 }
                )) {
                    ForEach(TTSProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            if settings.currentTTSProvider == .googleCloud {
                Section("Google Cloud TTS") {
                    Picker("음성", selection: Binding(
                        get: { settings.googleCloudVoiceName },
                        set: { settings.googleCloudVoiceName = $0 }
                    )) {
                        ForEach(GoogleCloudVoice.voicesByTier, id: \.tier.rawValue) { group in
                            Section(group.tier.displayName) {
                                ForEach(group.voices) { voice in
                                    Text(voice.displayName).tag(voice.name)
                                }
                            }
                        }
                    }

                    HStack {
                        SecureField("Google Cloud API 키", text: $gcpAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("저장") {
                            saveGCPKey()
                        }

                        if let account = keychainService?.load(account: TTSProvider.googleCloud.keychainAccount),
                           !account.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .help("저장됨")
                        }
                    }

                    if let status = saveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("속도 / 피치") {
                HStack {
                    Text("속도: \(String(format: "%.1f", settings.ttsSpeed))x")
                    Slider(value: Binding(
                        get: { settings.ttsSpeed },
                        set: { settings.ttsSpeed = $0 }
                    ), in: 0.5...2.0, step: 0.1)
                }

                HStack {
                    Text("피치: \(String(format: "%+.1f", settings.ttsPitch))")
                    Slider(value: Binding(
                        get: { settings.ttsPitch },
                        set: { settings.ttsPitch = $0 }
                    ), in: -10.0...10.0, step: 0.5)
                }
                Text("0 = 기본, + = 높은 목소리, - = 낮은 목소리")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("상태") {
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
        .onAppear {
            gcpAPIKey = keychainService?.load(account: TTSProvider.googleCloud.keychainAccount) ?? ""
        }
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

    private func saveGCPKey() {
        guard let keychainService else { return }
        do {
            if gcpAPIKey.isEmpty {
                try keychainService.delete(account: TTSProvider.googleCloud.keychainAccount)
            } else {
                try keychainService.save(account: TTSProvider.googleCloud.keychainAccount, value: gcpAPIKey)
            }
            saveStatus = "저장 완료"
            Log.app.info("Google Cloud TTS API key saved")
        } catch {
            saveStatus = "저장 실패: \(error.localizedDescription)"
            Log.app.error("Google Cloud TTS API key save failed: \(error.localizedDescription)")
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            saveStatus = nil
        }
    }

    private func testTTS() {
        guard let ttsService else { return }
        testPlaying = true

        Task {
            if case .unloaded = ttsService.engineState {
                try? await ttsService.loadEngine()
            }
            ttsService.enqueueSentence("안녕하세요, 저는 도치입니다.")

            // Poll until TTS finishes
            while ttsService.isSpeaking {
                try? await Task.sleep(for: .milliseconds(200))
            }
            testPlaying = false
        }
    }
}
