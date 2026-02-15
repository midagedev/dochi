import SwiftUI

struct VoiceSettingsView: View {
    var settings: AppSettings
    var keychainService: KeychainServiceProtocol?
    var ttsService: TTSServiceProtocol?
    var downloadManager: ModelDownloadManager?

    @State private var testPlaying = false
    @State private var gcpAPIKey: String = ""
    @State private var saveStatus: String?

    var body: some View {
        Form {
            Section {
                ForEach(TTSProvider.allCases, id: \.self) { provider in
                    HStack {
                        Image(systemName: settings.currentTTSProvider == provider ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(settings.currentTTSProvider == provider ? .blue : .secondary)
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(.system(size: 13))
                            Text(provider.shortDescription)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.ttsProvider = provider.rawValue
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: "TTS 프로바이더",
                    helpContent: "텍스트를 음성으로 변환하는 엔진을 선택합니다. \"시스템 TTS\"는 추가 설정 없이 사용 가능하며, Google Cloud TTS는 고품질 클라우드 음성을, 로컬 TTS (ONNX)는 오프라인 음성 합성을 제공합니다."
                )
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

            if settings.currentTTSProvider == .onnxLocal {
                Section("ONNX 모델") {
                    if let manager = downloadManager {
                        ONNXModelManagerView(
                            settings: settings,
                            downloadManager: manager
                        )
                    } else {
                        Text("모델 매니저를 사용할 수 없습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text("디퓨전 스텝: \(settings.ttsDiffusionSteps)")
                        Slider(value: Binding(
                            get: { Double(settings.ttsDiffusionSteps) },
                            set: { settings.ttsDiffusionSteps = Int($0) }
                        ), in: 1...10, step: 1)
                    }
                    Text("높을수록 품질이 좋지만 느려집니다 (권장: 3~5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SettingsSectionHeader(
                        title: "ONNX 추론 설정",
                        helpContent: "디퓨전 스텝 수를 조절합니다. 값이 높을수록 음성 품질이 좋아지지만 생성 시간이 길어집니다."
                    )
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

            // TTS offline fallback — only show when non-local provider is selected
            if !settings.currentTTSProvider.isLocal {
                Section {
                    Toggle("TTS 오프라인 폴백", isOn: Binding(
                        get: { settings.ttsOfflineFallbackEnabled },
                        set: { settings.ttsOfflineFallbackEnabled = $0 }
                    ))

                    Text("클라우드 TTS 실패 시 로컬 ONNX 모델로 자동 전환합니다. ONNX 모델이 설치되어 있지 않으면 시스템 TTS가 사용됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    SettingsSectionHeader(
                        title: "TTS 오프라인 폴백",
                        helpContent: "네트워크 장애 등으로 클라우드 TTS가 작동하지 않을 때 로컬 음성 합성으로 자동 전환합니다."
                    )
                }
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
