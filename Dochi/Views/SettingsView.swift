import SwiftUI

/// Settings for the voice + character front-end: how Dochi listens, how it
/// speaks, how the avatar looks, and where the Hermes backend lives.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let keychainService: KeychainServiceProtocol
    let ttsService: TTSRouter
    let downloadManager: ModelDownloadManager
    @Bindable var viewModel: DochiViewModel

    @State private var testPlaying = false
    @State private var googleCloudAPIKey = ""
    @State private var typecastAPIKey = ""
    @State private var googleCloudSaveStatus: String?
    @State private var googleCloudValidationStatus: String?
    @State private var googleCloudValidationFailed = false
    @State private var isCheckingGoogleCloudKey = false
    @State private var typecastSaveStatus: String?
    @State private var typecastVoices: [TypecastVoiceOption] = []
    @State private var isLoadingTypecastVoices = false
    @State private var typecastVoiceLoadError: String?

    private static let typecastDefaultEmotions = [
        "normal", "happy", "sad", "angry", "whisper", "toneup", "tonedown",
    ]

    var body: some View {
        TabView {
            voiceTab.tabItem { Label("음성", systemImage: "mic") }
            speechTab.tabItem { Label("말하기", systemImage: "speaker.wave.2") }
            avatarTab.tabItem { Label("아바타", systemImage: "person.crop.circle") }
            backendTab.tabItem { Label("Hermes", systemImage: "brain") }
        }
        .frame(width: 560, height: 680)
    }

    // MARK: 음성 (STT + wake word)

    private var voiceTab: some View {
        Form {
            Picker("상호작용 모드", selection: $settings.interactionMode) {
                Text("음성 + 텍스트").tag(InteractionMode.voiceAndText.rawValue)
                Text("텍스트 전용").tag(InteractionMode.textOnly.rawValue)
            }

            Section("웨이크워드") {
                Toggle("웨이크워드 사용", isOn: $settings.wakeWordEnabled)
                Toggle("항상 듣기 (백그라운드)", isOn: $settings.wakeWordAlwaysOn)
                    .disabled(!settings.wakeWordEnabled)
                TextField("웨이크워드", text: $settings.wakeWord)
                    .disabled(!settings.wakeWordEnabled)
            }

            Section("음성 인식") {
                HStack {
                    Text("침묵 후 종료")
                    Slider(value: $settings.sttSilenceTimeout, in: 0.5...5.0, step: 0.5)
                    Text(String(format: "%.1fs", settings.sttSilenceTimeout)).monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: 말하기 (TTS)

    private var speechTab: some View {
        Form {
            Section("TTS 제공자") {
                ForEach(TTSProvider.allCases, id: \.rawValue) { provider in
                    HStack {
                        Image(systemName: settings.currentTTSProvider == provider ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(settings.currentTTSProvider == provider ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                            Text(provider.shortDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.ttsProvider = provider.rawValue
                    }
                }
            }

            if settings.currentTTSProvider == .googleCloud {
                googleCloudSection
            }

            if settings.currentTTSProvider == .typecast {
                typecastSection
            }

            if settings.currentTTSProvider == .onnxLocal {
                onnxSection
            }

            Section("속도 / 피치") {
                HStack {
                    Text("속도")
                    Slider(value: $settings.ttsSpeed, in: 0.5...2.0, step: 0.1)
                    Text(String(format: "%.1f×", settings.ttsSpeed)).monospacedDigit()
                }

                HStack {
                    Text("피치")
                    Slider(value: $settings.ttsPitch, in: -10.0...10.0, step: 0.5)
                    Text(String(format: "%+.1f", settings.ttsPitch)).monospacedDigit()
                }

                Text("Typecast에서는 속도가 audio_tempo로 전달됩니다. 피치는 Google Cloud TTS에서만 사용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !settings.currentTTSProvider.isLocal {
                Section("오프라인 폴백") {
                    Toggle("클라우드 TTS 실패 시 로컬/시스템 TTS 사용", isOn: $settings.ttsOfflineFallbackEnabled)
                    Text("ONNX 모델 ID가 설정되어 있으면 로컬 TTS를 먼저 시도하고, 실패하면 시스템 TTS로 전환합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("상태") {
                LabeledContent("엔진") { engineStateLabel }
                Button {
                    testTTS()
                } label: {
                    Label(testPlaying ? "재생 중..." : "테스트 재생", systemImage: testPlaying ? "speaker.wave.3.fill" : "play.circle")
                }
                .disabled(testPlaying)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            googleCloudAPIKey = keychainService.load(account: TTSProvider.googleCloud.keychainAccount) ?? ""
            typecastAPIKey = keychainService.load(account: TTSProvider.typecast.keychainAccount) ?? ""
            normalizeTypecastSettings()
            if settings.currentTTSProvider == .onnxLocal {
                Task { await loadONNXCatalogIfNeeded() }
            }
            if settings.currentTTSProvider == .typecast, !typecastAPIKey.isEmpty {
                Task { await loadTypecastVoices() }
            }
        }
        .onChange(of: settings.ttsProvider) { _, _ in
            if settings.currentTTSProvider == .onnxLocal {
                Task { await loadONNXCatalogIfNeeded() }
            }
            if settings.currentTTSProvider == .typecast, !typecastAPIKey.isEmpty, typecastVoices.isEmpty {
                Task { await loadTypecastVoices() }
            }
        }
        .onChange(of: settings.typecastModel) { _, _ in
            syncSelectedTypecastVoiceForCurrentModel()
            normalizeTypecastEmotionPreset()
        }
        .onChange(of: settings.typecastVoiceId) { _, _ in
            normalizeTypecastEmotionPreset()
        }
    }

    private var googleCloudSection: some View {
        Section("Google Cloud TTS") {
            Picker("음성", selection: $settings.googleCloudVoiceName) {
                ForEach(GoogleCloudVoice.voicesByTier, id: \.tier.rawValue) { group in
                    Section(group.tier.displayName) {
                        ForEach(group.voices) { voice in
                            Text(voice.displayName).tag(voice.name)
                        }
                    }
                }
            }

            if let selectedGoogleCloudVoice {
                LabeledContent("선택 음성") {
                    Text("\(selectedGoogleCloudVoice.displayName) · \(selectedGoogleCloudVoice.tier.displayName)")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                SecureField("Google Cloud API 키", text: $googleCloudAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button("저장") { saveGoogleCloudKey() }

                Button {
                    Task { await validateGoogleCloudKey() }
                } label: {
                    Label("키 확인", systemImage: "checkmark.shield")
                }
                .disabled(isCheckingGoogleCloudKey || googleCloudAPIKey.isEmpty)

                if !googleCloudAPIKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("입력됨")
                }
            }

            if let status = googleCloudSaveStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isCheckingGoogleCloudKey {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Google Cloud 키 확인 중...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let status = googleCloudValidationStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(googleCloudValidationFailed ? .red : .green)
            }

            Text("Chirp3-HD 음성은 Google 정책상 속도/피치 조절을 받지 않을 수 있습니다. WaveNet/Neural2/Standard는 아래 속도와 피치를 사용합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var typecastSection: some View {
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
                Picker("음성", selection: $settings.typecastVoiceId) {
                    ForEach(typecastVoicesForSelectedModel) { voice in
                        Text(typecastVoiceDisplayName(voice)).tag(voice.voiceId)
                    }
                }
            } else {
                Text("음성 목록을 불러오지 못했거나 선택한 모델(\(settings.typecastModel))과 맞는 음성이 없습니다. Voice ID를 직접 입력할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Voice ID", text: $settings.typecastVoiceId)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            Picker("모델", selection: $settings.typecastModel) {
                Text("ssfm-v30").tag("ssfm-v30")
                Text("ssfm-v21").tag("ssfm-v21")
            }

            Picker("언어", selection: $settings.typecastLanguage) {
                Text("한국어 (kor)").tag("kor")
                Text("영어 (eng)").tag("eng")
                Text("일본어 (jpn)").tag("jpn")
            }

            Picker("감정 모드", selection: $settings.typecastEmotionType) {
                Text("Preset").tag("preset")
                Text("Smart").tag("smart")
            }

            if settings.typecastEmotionType == "preset" {
                Picker("감정 프리셋", selection: $settings.typecastEmotionPreset) {
                    ForEach(typecastEmotionPresetsForCurrentSelection, id: \.self) { emotion in
                        Text(emotion).tag(emotion)
                    }
                }

                HStack {
                    Text("감정 강도")
                    Slider(value: $settings.typecastEmotionIntensity, in: 0.0...2.0, step: 0.1)
                    Text(String(format: "%.1f", settings.typecastEmotionIntensity)).monospacedDigit()
                }
            } else {
                Text("Smart 모드는 Typecast가 문맥 기반으로 감정을 추론합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("볼륨")
                Slider(
                    value: Binding(
                        get: { Double(settings.typecastVolume) },
                        set: { settings.typecastVolume = Int($0.rounded()) }
                    ),
                    in: 0...200,
                    step: 1
                )
                Text("\(settings.typecastVolume)").monospacedDigit()
            }

            HStack {
                Text("오디오 피치")
                Slider(
                    value: Binding(
                        get: { Double(settings.typecastAudioPitch) },
                        set: { settings.typecastAudioPitch = Int($0.rounded()) }
                    ),
                    in: -12...12,
                    step: 1
                )
                Text("\(settings.typecastAudioPitch)").monospacedDigit()
            }

            Picker("출력 포맷", selection: $settings.typecastAudioFormat) {
                Text("WAV").tag("wav")
                Text("MP3").tag("mp3")
            }

            HStack {
                SecureField("Typecast API 키", text: $typecastAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button("저장") { saveTypecastKey() }

                if !typecastAPIKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("입력됨")
                }
            }

            if let status = typecastSaveStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var onnxSection: some View {
        Section("로컬 TTS (ONNX)") {
            VStack(alignment: .leading, spacing: 10) {
                onnxCatalogView
            }

            Picker("로컬 음색", selection: $settings.supertonicVoice) {
                ForEach(SupertonicVoice.allCases, id: \.rawValue) { voice in
                    Text(voice.rawValue).tag(voice.rawValue)
                }
            }

            HStack {
                Text("디퓨전 스텝")
                Slider(
                    value: Binding(
                        get: { Double(settings.ttsDiffusionSteps) },
                        set: { settings.ttsDiffusionSteps = Int($0.rounded()) }
                    ),
                    in: 1...10,
                    step: 1
                )
                Text("\(settings.ttsDiffusionSteps)").monospacedDigit()
            }

            Text("모델 파일은 ~/Library/Application Support/Dochi/models 아래의 모델 ID 폴더에서 찾습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var onnxCatalogView: some View {
        switch downloadManager.catalogState {
        case .idle:
            Button {
                Task { await downloadManager.loadCatalog() }
            } label: {
                Label("한국어 ONNX 모델 탐색", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)

            if !settings.onnxModelId.isEmpty {
                TextField("ONNX 모델 ID", text: $settings.onnxModelId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("모델 카탈로그 로딩 중...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("카탈로그 로드 실패", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("다시 시도") {
                    Task { await downloadManager.loadCatalog() }
                }
            }

        case .loaded:
            if !downloadManager.installedModelIds.isEmpty {
                Picker("사용할 모델", selection: $settings.onnxModelId) {
                    Text("선택 안 함").tag("")
                    ForEach(downloadManager.availableModels.filter { downloadManager.installedModelIds.contains($0.id) }) { model in
                        Text(model.name).tag(model.id)
                    }
                }
            } else {
                TextField("ONNX 모델 ID", text: $settings.onnxModelId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            ForEach(downloadManager.availableModels) { model in
                onnxModelRow(model)
            }

            if !downloadManager.installedModelIds.isEmpty {
                Text("설치된 모델 용량: \(downloadManager.formattedTotalSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func onnxModelRow(_ model: PiperModelInfo) -> some View {
        let state = downloadManager.installState(for: model.id)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 12, weight: .medium))
                    if case .installed = state {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 6) {
                    Label(model.language, systemImage: "globe")
                    Label(model.gender, systemImage: "person")
                    Label(model.quality.displayName, systemImage: model.quality.icon)
                    Text(model.formattedSize)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer()

            switch state {
            case .notInstalled:
                Button {
                    Task { await downloadManager.downloadModel(model.id) }
                } label: {
                    Label("다운로드", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)

            case .downloading(let progress):
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .frame(width: 60)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button {
                        downloadManager.cancelDownload(model.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

            case .installed:
                Button(role: .destructive) {
                    downloadManager.deleteModel(model.id)
                    if settings.onnxModelId == model.id {
                        settings.onnxModelId = ""
                    }
                } label: {
                    Label("삭제", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 아바타

    private var avatarTab: some View {
        Form {
            Section {
                Toggle("3D 아바타 표시", isOn: $settings.avatarEnabled)
            }

            if settings.avatarEnabled {
                Section("캐릭터 선택") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132, maximum: 160), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(AvatarModelCatalog.models) { model in
                            AvatarModelSelectionCard(
                                model: model,
                                isSelected: settings.avatarModelName == model.id
                            ) {
                                settings.avatarModelName = model.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("화면 맞춤") {
                    HStack {
                        Text("카메라 줌")
                        Slider(value: $settings.avatarCameraZoom, in: AppSettings.avatarCameraZoomRange, step: 0.05)
                        Text(String(format: "%.1f", settings.avatarCameraZoom)).monospacedDigit()
                    }
                }

                if let selectedModel = AvatarModelCatalog.model(for: settings.avatarModelName) {
                    Section("선택한 캐릭터") {
                        LabeledContent("모델") {
                            Text("\(selectedModel.displayName) · \(selectedModel.originalName)")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("제작자") {
                            Text(selectedModel.creator)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("\(selectedModel.license) · 앱 번들 사용 가능", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            if let sourceURL = URL(string: selectedModel.sourceURL) {
                                Link("원본 VRM", destination: sourceURL)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Hermes 백엔드

    private var backendTab: some View {
        Form {
            Section("Hermes 브리지 연결") {
                TextField("호스트", text: $settings.hermesBridgeHost)
                TextField("포트", value: $settings.hermesBridgePort, format: .number.grouping(.never))
                LabeledContent("상태") { connectionStatusText }
                Button("재연결") { viewModel.reconnectBackend() }
            }
            Section {
                Text("""
                Dochi는 음성·캐릭터 인터페이스입니다. 추론·기억·도구는 Hermes Agent가 담당합니다. \
                터미널에서 `python -m dochi_hermes_bridge` 를 실행해 브리지를 켜세요. \
                (Hermes 미설치 시 `--echo` 로 음성 파이프라인을 테스트할 수 있습니다.)
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var engineStateLabel: some View {
        switch ttsService.engineState {
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
        case .error(let message):
            Label("오류: \(message)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var selectedGoogleCloudVoice: GoogleCloudVoice? {
        GoogleCloudVoice.koreanVoices.first { $0.name == settings.googleCloudVoiceName }
    }

    private func loadONNXCatalogIfNeeded() async {
        if case .idle = downloadManager.catalogState {
            await downloadManager.loadCatalog()
        }
    }

    private func validateGoogleCloudKey() async {
        let apiKey = googleCloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            googleCloudValidationStatus = "Google Cloud API 키를 먼저 입력하세요."
            googleCloudValidationFailed = true
            return
        }

        isCheckingGoogleCloudKey = true
        googleCloudValidationStatus = nil
        googleCloudValidationFailed = false
        defer { isCheckingGoogleCloudKey = false }

        do {
            var components = URLComponents(string: "https://texttospeech.googleapis.com/v1/voices")!
            components.queryItems = [
                URLQueryItem(name: "languageCode", value: "ko-KR"),
                URLQueryItem(name: "key", value: apiKey),
            ]
            guard let url = components.url else {
                throw GoogleCloudKeyValidationError.invalidURL
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw GoogleCloudKeyValidationError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown"
                throw GoogleCloudKeyValidationError.httpError(statusCode: http.statusCode, message: message)
            }

            let decoded = try JSONDecoder().decode(GoogleCloudVoicesResponse.self, from: data)
            googleCloudValidationStatus = "키 확인 완료 · ko-KR 음성 \(decoded.voices.count)개 접근 가능"
            googleCloudValidationFailed = false
        } catch {
            googleCloudValidationStatus = "키 확인 실패: \(error.localizedDescription)"
            googleCloudValidationFailed = true
        }
    }

    private var typecastVoicesForSelectedModel: [TypecastVoiceOption] {
        typecastVoices.filter { voice in
            voice.models.contains { $0.version == settings.typecastModel }
        }
    }

    private var selectedTypecastVoice: TypecastVoiceOption? {
        typecastVoices.first { $0.voiceId == settings.typecastVoiceId }
    }

    private var typecastEmotionPresetsForCurrentSelection: [String] {
        guard let selectedTypecastVoice else { return Self.typecastDefaultEmotions }
        let emotions = selectedTypecastVoice.models
            .first { $0.version == settings.typecastModel }?
            .emotions
            .filter { !$0.isEmpty } ?? []
        return emotions.isEmpty ? Self.typecastDefaultEmotions : emotions
    }

    private func typecastVoiceDisplayName(_ voice: TypecastVoiceOption) -> String {
        let gender = voice.gender?.trimmingCharacters(in: .whitespacesAndNewlines)
        let age = voice.age?.trimmingCharacters(in: .whitespacesAndNewlines)
        let genderText = gender?.isEmpty == false ? gender! : "unknown"
        let ageText = age?.isEmpty == false ? age! : "unknown"
        return "\(voice.voiceName) (\(genderText), \(ageText))"
    }

    private func normalizeTypecastSettings() {
        if !["preset", "smart"].contains(settings.typecastEmotionType) {
            settings.typecastEmotionType = "preset"
        }
        if !["wav", "mp3"].contains(settings.typecastAudioFormat) {
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

    private func saveGoogleCloudKey() {
        do {
            if googleCloudAPIKey.isEmpty {
                try keychainService.delete(account: TTSProvider.googleCloud.keychainAccount)
            } else {
                try keychainService.save(account: TTSProvider.googleCloud.keychainAccount, value: googleCloudAPIKey)
            }
            googleCloudSaveStatus = "저장 완료"
            Log.app.info("Google Cloud TTS API key saved")
        } catch {
            googleCloudSaveStatus = "저장 실패: \(error.localizedDescription)"
            Log.app.error("Google Cloud TTS API key save failed: \(error.localizedDescription)")
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            googleCloudSaveStatus = nil
        }
    }

    private func saveTypecastKey() {
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

    private func testTTS() {
        testPlaying = true

        Task {
            if case .unloaded = ttsService.engineState {
                try? await ttsService.loadEngine()
            }
            ttsService.enqueueSentence("안녕하세요, 저는 도치입니다.")

            while ttsService.isSpeaking {
                try? await Task.sleep(for: .milliseconds(200))
            }
            testPlaying = false
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

    private struct GoogleCloudVoicesResponse: Decodable {
        let voices: [GoogleCloudVoiceInfo]
    }

    private struct GoogleCloudVoiceInfo: Decodable {
        let name: String
    }

    private enum GoogleCloudKeyValidationError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Google Cloud 음성 목록 URL을 만들 수 없습니다."
            case .invalidResponse:
                return "Google Cloud 응답이 올바르지 않습니다."
            case let .httpError(statusCode, message):
                return "Google Cloud API 오류 (\(statusCode)): \(message)"
            }
        }
    }

    @ViewBuilder
    private var connectionStatusText: some View {
        switch viewModel.hermesConnection {
        case .connected(let persona): Text(persona.map { "연결됨 · \($0)" } ?? "연결됨").foregroundStyle(.green)
        case .connecting: Text("연결 중…").foregroundStyle(.orange)
        case .disconnected: Text("연결 끊김").foregroundStyle(.secondary)
        case .failed(let message): Text("실패: \(message)").foregroundStyle(.red)
        }
    }
}
