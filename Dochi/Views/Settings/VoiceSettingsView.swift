import Foundation
import SwiftUI

struct VoiceSettingsView: View {
    var settings: AppSettings
    var keychainService: KeychainServiceProtocol?
    var ttsService: TTSServiceProtocol?
    var downloadManager: ModelDownloadManager?

    @State private var testPlaying = false
    @State private var gcpAPIKey: String = ""
    @State private var typecastAPIKey: String = ""
    @State private var gcpSaveStatus: String?
    @State private var typecastSaveStatus: String?
    @State private var typecastVoices: [TypecastVoiceOption] = []
    @State private var isLoadingTypecastVoices = false
    @State private var typecastVoiceLoadError: String?

    private static let typecastDefaultEmotions = [
        "normal", "happy", "sad", "angry", "whisper", "toneup", "tonedown",
    ]

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
                    helpContent: "텍스트를 음성으로 변환하는 엔진을 선택합니다. \"시스템 TTS\"는 추가 설정 없이 사용 가능하며, Google Cloud/Typecast는 클라우드 음성을, 로컬 TTS (ONNX)는 오프라인 음성 합성을 제공합니다."
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

                    if let status = gcpSaveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if settings.currentTTSProvider == .typecast {
                Section("Typecast TTS") {
                    HStack(spacing: 8) {
                        Button {
                            Task { await loadTypecastVoices() }
                        } label: {
                            Label("음성 목록 새로고침", systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoadingTypecastVoices)

                        if isLoadingTypecastVoices {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let error = typecastVoiceLoadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !typecastVoicesForSelectedModel.isEmpty {
                        Picker("음성", selection: Binding(
                            get: { settings.typecastVoiceId },
                            set: { settings.typecastVoiceId = $0 }
                        )) {
                            ForEach(typecastVoicesForSelectedModel) { voice in
                                Text(typecastVoiceDisplayName(voice)).tag(voice.voiceId)
                            }
                        }
                    } else {
                        Text("선택한 모델(\(settings.typecastModel))에 맞는 음성을 불러오지 못했습니다. Voice ID를 직접 입력하세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Voice ID (직접 입력)", text: Binding(
                        get: { settings.typecastVoiceId },
                        set: { settings.typecastVoiceId = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                    Picker("모델", selection: Binding(
                        get: { settings.typecastModel },
                        set: { settings.typecastModel = $0 }
                    )) {
                        Text("ssfm-v30").tag("ssfm-v30")
                        Text("ssfm-v21").tag("ssfm-v21")
                    }

                    Picker("언어", selection: Binding(
                        get: { settings.typecastLanguage },
                        set: { settings.typecastLanguage = $0 }
                    )) {
                        Text("한국어 (kor)").tag("kor")
                        Text("영어 (eng)").tag("eng")
                        Text("일본어 (jpn)").tag("jpn")
                    }

                    Picker("감정 모드", selection: Binding(
                        get: { settings.typecastEmotionType },
                        set: { settings.typecastEmotionType = $0 }
                    )) {
                        Text("Preset").tag("preset")
                        Text("Smart").tag("smart")
                    }

                    if settings.typecastEmotionType == "preset" {
                        Picker("감정 프리셋", selection: Binding(
                            get: { settings.typecastEmotionPreset },
                            set: { settings.typecastEmotionPreset = $0 }
                        )) {
                            ForEach(typecastEmotionPresetsForCurrentSelection, id: \.self) { emotion in
                                Text(emotion).tag(emotion)
                            }
                        }

                        HStack {
                            Text("감정 강도: \(String(format: "%.1f", settings.typecastEmotionIntensity))")
                            Slider(value: Binding(
                                get: { settings.typecastEmotionIntensity },
                                set: { settings.typecastEmotionIntensity = $0 }
                            ), in: 0.0...2.0, step: 0.1)
                        }
                    } else {
                        Text("Smart 모드는 텍스트 문맥 기반으로 감정을 자동 추론합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("볼륨: \(settings.typecastVolume)")
                        Slider(value: Binding(
                            get: { Double(settings.typecastVolume) },
                            set: { settings.typecastVolume = Int($0.rounded()) }
                        ), in: 0...200, step: 1)
                    }

                    HStack {
                        Text("피치: \(settings.typecastAudioPitch)")
                        Slider(value: Binding(
                            get: { Double(settings.typecastAudioPitch) },
                            set: { settings.typecastAudioPitch = Int($0.rounded()) }
                        ), in: -12...12, step: 1)
                    }

                    Picker("출력 포맷", selection: Binding(
                        get: { settings.typecastAudioFormat },
                        set: { settings.typecastAudioFormat = $0 }
                    )) {
                        Text("WAV").tag("wav")
                        Text("MP3").tag("mp3")
                    }

                    Text("속도 슬라이더 값은 Typecast audio_tempo(0.5~2.0)로 전달됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        SecureField("Typecast API 키", text: $typecastAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("저장") {
                            saveTypecastKey()
                        }

                        if let account = keychainService?.load(account: TTSProvider.typecast.keychainAccount),
                           !account.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .help("저장됨")
                        }
                    }

                    if let status = typecastSaveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if settings.currentTTSProvider == .onnxLocal {
                Section("ONNX 모델") {
                    Label("베타 기능: ONNX 추론이 실패하거나 준비되지 않으면 시스템 TTS로 자동 폴백됩니다.", systemImage: "flask.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

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

                    if settings.onnxModelId.isEmpty {
                        Text("원활한 테스트를 위해 설치된 모델을 하나 선택하세요.")
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
            typecastAPIKey = keychainService?.load(account: TTSProvider.typecast.keychainAccount) ?? ""
            normalizeTypecastSettings()
            if settings.currentTTSProvider == .typecast, !typecastAPIKey.isEmpty {
                Task { await loadTypecastVoices() }
            }
        }
        .onChange(of: settings.typecastModel) { _ in
            syncSelectedTypecastVoiceForCurrentModel()
            normalizeTypecastEmotionPreset()
        }
        .onChange(of: settings.typecastVoiceId) { _ in
            normalizeTypecastEmotionPreset()
        }
        .onChange(of: settings.ttsProvider) { _ in
            if settings.currentTTSProvider == .typecast, !typecastAPIKey.isEmpty, typecastVoices.isEmpty {
                Task { await loadTypecastVoices() }
            }
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

    private var typecastVoicesForSelectedModel: [TypecastVoiceOption] {
        typecastVoices.filter { voice in
            voice.models.contains(where: { $0.version == settings.typecastModel })
        }
    }

    private var selectedTypecastVoice: TypecastVoiceOption? {
        typecastVoices.first { $0.voiceId == settings.typecastVoiceId }
    }

    private var typecastEmotionPresetsForCurrentSelection: [String] {
        guard let selectedTypecastVoice else { return Self.typecastDefaultEmotions }
        let emotions = selectedTypecastVoice.models
            .first(where: { $0.version == settings.typecastModel })?
            .emotions
            .filter { !$0.isEmpty } ?? []
        return emotions.isEmpty ? Self.typecastDefaultEmotions : emotions
    }

    private func typecastVoiceDisplayName(_ voice: TypecastVoiceOption) -> String {
        let gender = (voice.gender?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (voice.gender ?? "unknown") : "unknown"
        let age = (voice.age?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (voice.age ?? "unknown") : "unknown"
        return "\(voice.voiceName) (\(gender), \(age))"
    }

    private func normalizeTypecastSettings() {
        let allowedEmotionTypes = ["preset", "smart"]
        if !allowedEmotionTypes.contains(settings.typecastEmotionType) {
            settings.typecastEmotionType = "preset"
        }

        let allowedFormats = ["wav", "mp3"]
        if !allowedFormats.contains(settings.typecastAudioFormat) {
            settings.typecastAudioFormat = "wav"
        }

        if settings.typecastLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.typecastLanguage = "kor"
        }

        settings.typecastEmotionIntensity = min(max(settings.typecastEmotionIntensity, 0.0), 2.0)
        settings.typecastVolume = min(max(settings.typecastVolume, 0), 200)
        settings.typecastAudioPitch = min(max(settings.typecastAudioPitch, -12), 12)
        normalizeTypecastEmotionPreset()
    }

    private func normalizeTypecastEmotionPreset() {
        let allowed = typecastEmotionPresetsForCurrentSelection
        if !allowed.contains(settings.typecastEmotionPreset) {
            settings.typecastEmotionPreset = allowed.first ?? "normal"
        }
    }

    private func syncSelectedTypecastVoiceForCurrentModel() {
        guard !typecastVoicesForSelectedModel.isEmpty else { return }
        let current = settings.typecastVoiceId
        let supported = typecastVoicesForSelectedModel.contains { $0.voiceId == current }
        if !supported {
            settings.typecastVoiceId = typecastVoicesForSelectedModel[0].voiceId
        }
    }

    private func loadTypecastVoices() async {
        guard let keychainService else {
            typecastVoiceLoadError = "키체인 서비스를 찾을 수 없습니다."
            return
        }

        let apiKey = keychainService.load(account: TTSProvider.typecast.keychainAccount) ?? ""
        guard !apiKey.isEmpty else {
            typecastVoiceLoadError = "Typecast API 키를 먼저 저장하세요."
            return
        }

        isLoadingTypecastVoices = true
        typecastVoiceLoadError = nil
        defer { isLoadingTypecastVoices = false }

        do {
            var request = URLRequest(url: URL(string: "https://api.typecast.ai/v2/voices")!)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TypecastVoiceLoadError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown"
                throw TypecastVoiceLoadError.httpError(statusCode: http.statusCode, message: message)
            }

            let decoded = try JSONDecoder().decode([TypecastVoiceOption].self, from: data)
            typecastVoices = decoded.sorted { lhs, rhs in
                lhs.voiceName.localizedCaseInsensitiveCompare(rhs.voiceName) == .orderedAscending
            }
            syncSelectedTypecastVoiceForCurrentModel()
            normalizeTypecastEmotionPreset()

            if typecastVoicesForSelectedModel.isEmpty {
                typecastVoiceLoadError = "선택한 모델(\(settings.typecastModel))을 지원하는 음성이 없습니다."
            }
        } catch {
            typecastVoiceLoadError = "음성 목록 로드 실패: \(error.localizedDescription)"
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
            gcpSaveStatus = "저장 완료"
            Log.app.info("Google Cloud TTS API key saved")
        } catch {
            gcpSaveStatus = "저장 실패: \(error.localizedDescription)"
            Log.app.error("Google Cloud TTS API key save failed: \(error.localizedDescription)")
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            gcpSaveStatus = nil
        }
    }

    private func saveTypecastKey() {
        guard let keychainService else { return }
        do {
            if typecastAPIKey.isEmpty {
                try keychainService.delete(account: TTSProvider.typecast.keychainAccount)
            } else {
                try keychainService.save(account: TTSProvider.typecast.keychainAccount, value: typecastAPIKey)
            }
            typecastSaveStatus = "저장 완료"
            Log.app.info("Typecast TTS API key saved")
            Task { await loadTypecastVoices() }
        } catch {
            typecastSaveStatus = "저장 실패: \(error.localizedDescription)"
            Log.app.error("Typecast TTS API key save failed: \(error.localizedDescription)")
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            typecastSaveStatus = nil
        }
    }

    private struct TypecastVoiceOption: Identifiable, Decodable {
        let voiceId: String
        let voiceName: String
        let models: [TypecastVoiceModel]
        let gender: String?
        let age: String?
        let useCases: [String]

        var id: String { voiceId }

        enum CodingKeys: String, CodingKey {
            case voiceId = "voice_id"
            case voiceName = "voice_name"
            case models
            case gender
            case age
            case useCases = "use_cases"
        }
    }

    private struct TypecastVoiceModel: Decodable {
        let version: String
        let emotions: [String]
    }

    private enum TypecastVoiceLoadError: LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Typecast 음성 목록 응답이 올바르지 않습니다."
            case let .httpError(statusCode, message):
                return "Typecast API 오류 (\(statusCode)): \(message)"
            }
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
