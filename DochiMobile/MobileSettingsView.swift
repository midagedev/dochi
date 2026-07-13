import AgentRuntimeMemory
import SwiftUI

struct MobileSettingsView: View {
    private enum AccessibilityTarget: Hashable {
        case model
        case compatibleURL
        case apiKey
    }

    let controller: MobileAgentController
    @Bindable var preferences: MobileAgentPreferences

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var apiKey = ""
    @State private var isLoadingKey = false
    @State private var isSaving = false
    @State private var keyStatusMessage: String?
    @State private var configurationError: String?
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityTarget?

    var body: some View {
        NavigationStack {
            Form {
                avatarSection
                providerSection
                behaviorSection
                privacySection
                aboutSection
            }
            .navigationTitle("도치 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .disabled(isSaving || controller.isMemoryManagementBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { applyAndDismiss() }
                        .fontWeight(.semibold)
                        .disabled(isSaving || controller.isMemoryManagementBusy)
                }
            }
        }
        .task(id: preferences.providerKind) { await loadAPIKey() }
        .alert("설정을 저장하지 못했어요", isPresented: configurationErrorPresentation) {
            Button("확인") {}
        } message: {
            Text(configurationError ?? "입력한 내용을 확인해 주세요.")
        }
        .interactiveDismissDisabled(isSaving || controller.isMemoryManagementBusy)
    }

    private var avatarSection: some View {
        Section {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVStack(spacing: 10) {
                    avatarButtons(horizontal: true)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 14) {
                    avatarButtons(horizontal: false)
                }
            }
        } header: {
            Text("아바타")
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("대화 내용과 무관하게 언제든 바꿀 수 있어요.")
        }
    }

    @ViewBuilder
    private func avatarButtons(horizontal: Bool) -> some View {
        ForEach(MobileAvatar.all) { avatar in
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                    preferences.avatarName = avatar.assetName
                }
            } label: {
                if horizontal {
                    HStack(spacing: 14) {
                        avatarArtwork(avatar)
                        Text(avatar.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if preferences.avatarName == avatar.assetName {
                            Text("선택됨")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.indigo)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                    .contentShape(Rectangle())
                } else {
                    VStack(spacing: 7) {
                        avatarArtwork(avatar)
                        Text(avatar.displayName)
                            .font(.caption2)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 76, minHeight: 102)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("아바타 \(avatar.displayName)")
            .accessibilityValue(preferences.avatarName == avatar.assetName ? "선택됨" : "선택 안 됨")
            .accessibilityAddTraits(preferences.avatarName == avatar.assetName ? .isSelected : [])
            .accessibilityHint("도치의 대화 아바타로 선택합니다.")
            .accessibilityInputLabels([avatar.displayName, "\(avatar.displayName) 아바타"])
        }
    }

    private func avatarArtwork(_ avatar: MobileAvatar) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(avatar.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            preferences.avatarName == avatar.assetName ? Color.indigo : Color.secondary.opacity(0.22),
                            lineWidth: preferences.avatarName == avatar.assetName ? 3 : 1
                        )
                }
                .accessibilityHidden(true)

            if preferences.avatarName == avatar.assetName {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .indigo)
                    .background(Circle().fill(.white))
                    .offset(x: 5, y: -5)
                    .accessibilityHidden(true)
            }
        }
    }

    private var providerSection: some View {
        Section {
            Picker("프로바이더", selection: providerBinding) {
                ForEach(MobileProviderKind.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .accessibilityIdentifier("mobile-provider-picker")
            .accessibilityHint("도치가 답변할 모델 서비스를 선택합니다.")

            TextField("모델 이름", text: $preferences.model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("모델 이름")
                .accessibilityIdentifier("mobile-model-name-field")
                .accessibilityHint("선택한 프로바이더에서 사용할 정확한 모델 식별자를 입력합니다.")
                .accessibilityFocused($accessibilityFocus, equals: .model)

            if preferences.currentProvider == .openAICompatible {
                VStack(alignment: .leading, spacing: 7) {
                    TextField("https://server.example/v1", text: $preferences.compatibleBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("OpenAI 호환 서버 주소")
                        .accessibilityHint("외부 서버는 HTTPS, 이 기기의 loopback 서버는 HTTP를 사용할 수 있습니다.")
                        .accessibilityFocused($accessibilityFocus, equals: .compatibleURL)

                    Label(compatibleURLStatus.text, systemImage: compatibleURLStatus.isValid ? "checkmark.shield" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(compatibleURLStatus.isValid ? Color.secondary : Color.orange)
                        .accessibilityElement(children: .combine)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                SecureField(
                    preferences.currentProvider == .openAICompatible ? "API 키 (선택 사항)" : "API 키",
                    text: $apiKey
                )
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isLoadingKey || isSaving)
                .accessibilityLabel("\(preferences.currentProvider.displayName) API 키")
                .accessibilityIdentifier("mobile-provider-api-key-field")
                .accessibilityHint("키는 Keychain에만 저장되며 대화 파일에는 기록되지 않습니다.")
                .accessibilityFocused($accessibilityFocus, equals: .apiKey)

                HStack {
                    if isLoadingKey {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("API 키 불러오는 중")
                    }
                    if let keyStatusMessage {
                        Text(keyStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(apiKey.isEmpty ? "저장된 키 삭제" : "키 저장") {
                        saveAPIKey()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingKey || isSaving)
                    .frame(minHeight: 44)
                    .accessibilityInputLabels(["API 키 저장", "키 저장"])
                }
            }
        } header: {
            Text("모델")
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("API 키는 iOS Keychain에 저장합니다. OpenAI 호환 주소는 HTTPS만 허용하며, HTTP는 localhost와 127.0.0.0/8 또는 ::1에서만 허용합니다.")
                .accessibilityIdentifier("mobile-provider-key-guidance")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("음성으로 입력", isOn: $preferences.speechInputEnabled)
                .accessibilityHint("켜면 대화 입력란에 마이크 버튼이 나타납니다. 권한은 실제로 사용할 때 요청합니다.")
            Toggle("답변 읽어주기", isOn: $preferences.speakReplies)
                .accessibilityHint("도치의 최종 답변을 기기의 한국어 음성으로 읽습니다.")
            Toggle("완료 진동", isOn: $preferences.hapticsEnabled)
                .accessibilityHint("답변이 끝났을 때 짧은 햅틱 피드백을 제공합니다.")
        } header: {
            Text("음성과 피드백")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("기억 사용", isOn: $preferences.memoryEnabled)
                .accessibilityIdentifier("mobile-memory-toggle")
                .accessibilityHint("도치가 기억을 찾고 저장할 수 있게 합니다. 이 스위치를 꺼도 이미 저장된 기억은 삭제되지 않습니다.")

            Toggle("파일 메모리 사용", isOn: $preferences.fileMemoryEnabled)
                .disabled(
                    !preferences.memoryEnabled
                        || controller.fileMemoryStatus.isSynchronizing
                )
                .accessibilityIdentifier("mobile-file-memory-toggle")
                .accessibilityHint("켜면 관련 Markdown·텍스트 파일 발췌가 선택한 모델 프로바이더로 전송될 수 있습니다. 발췌마다 별도 승인을 요청하지 않습니다.")

            Picker("파일 위치", selection: $preferences.fileMemoryLocation) {
                ForEach(MobileFileMemoryLocation.allCases) { location in
                    Text(location.displayName).tag(location.rawValue)
                }
            }
            .disabled(
                !preferences.memoryEnabled
                    || !preferences.fileMemoryEnabled
                    || controller.fileMemoryStatus.isSynchronizing
            )
            .accessibilityIdentifier("mobile-file-memory-location")

            LabeledContent("파일 메모리 상태") {
                Text(controller.fileMemoryStatus.displayText)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                Task { await controller.refreshFileMemory() }
            } label: {
                Label("파일 메모리 새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(
                controller.isRunning
                    || controller.fileMemoryStatus.isSynchronizing
                    || !preferences.memoryEnabled
                    || !preferences.fileMemoryEnabled
            )
            .accessibilityIdentifier("mobile-file-memory-refresh")

            NavigationLink {
                MobileMemoryManagementView(controller: controller)
            } label: {
                Label("저장된 기억 관리", systemImage: "externaldrive.badge.person.crop")
            }
            .accessibilityIdentifier("memory-management-link")
            .accessibilityHint("현재 사용자에게 속한 과거 대화의 기억까지 확인하고 영구 삭제할 수 있습니다.")
        } header: {
            Text("기억과 개인정보")
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("'기억 사용'을 꺼도 저장된 데이터는 삭제되지 않습니다. 영구 삭제는 '저장된 기억 관리'에서 별도로 확인한 뒤 실행합니다. Markdown·텍스트 파일은 원본이고 보호된 SQLite는 검색용 색인입니다. '파일 메모리 사용'을 켜는 것은 관련 파일 발췌가 답변 생성을 위해 선택한 모델 프로바이더로 전송될 수 있음에 동의하는 것입니다. 발췌를 전송할 때마다 별도 승인을 요청하지 않습니다. '파일 위치'는 원본을 읽을 기기 또는 iCloud Drive 저장소만 정하는 별도 설정이며 모델 전송 동의가 아닙니다. iCloud Drive를 명시적으로 선택했는데 사용할 수 없으면 기기 색인을 문맥에서 제외하고, 선택한 iCloud의 마지막 색인만 유지할 수 있습니다. 민감한 내용을 장기 저장할 때는 도치가 별도로 승인을 요청합니다. 사용자가 보낸 메시지 텍스트, 승인된 장기 기억 문맥, 파일 메모리로 허용한 관련 발췌는 답변 생성을 위해 선택한 모델 프로바이더로 전송됩니다. 음성 입력의 오디오 원본은 해당 모델 프로바이더로 전송하지 않습니다.")
                .accessibilityIdentifier("mobile-memory-privacy-guidance")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("런타임", value: "AgentRuntimeKit")
            LabeledContent("대화 ID", value: String(preferences.sessionID.prefix(8)))
                .accessibilityLabel("현재 대화 식별자")
                .accessibilityValue(String(preferences.sessionID.prefix(8)))
        } header: {
            Text("정보")
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("대화, provider continuation, 도구 결과는 파일 보호가 적용된 기기 저장소에 보관됩니다.")
        }
    }

    private var providerBinding: Binding<MobileProviderKind> {
        Binding(
            get: { preferences.currentProvider },
            set: { provider in
                keyStatusMessage = nil
                preferences.selectProvider(provider)
            }
        )
    }

    private var compatibleURLStatus: (isValid: Bool, text: String) {
        do {
            let endpoint = try MobileCompatibleEndpoint.chatCompletionsEndpoint(
                from: preferences.compatibleBaseURL
            )
            return (true, "요청 주소: \(endpoint.absoluteString)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private var configurationErrorPresentation: Binding<Bool> {
        Binding(
            get: { configurationError != nil },
            set: { isPresented in
                if !isPresented { configurationError = nil }
            }
        )
    }

    private func loadAPIKey() async {
        let provider = preferences.currentProvider
        isLoadingKey = true
        keyStatusMessage = nil
        do {
            let loaded = try await controller.loadAPIKey(for: provider)
            guard preferences.currentProvider == provider else { return }
            apiKey = loaded
            keyStatusMessage = loaded.isEmpty ? "저장된 키가 없습니다." : "Keychain에서 불러왔습니다."
        } catch {
            guard preferences.currentProvider == provider else { return }
            apiKey = ""
            keyStatusMessage = "키를 불러오지 못했습니다."
        }
        if preferences.currentProvider == provider { isLoadingKey = false }
    }

    private func saveAPIKey() {
        let provider = preferences.currentProvider
        let value = apiKey
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await controller.saveAPIKey(value, for: provider)
                guard preferences.currentProvider == provider else { return }
                keyStatusMessage = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "저장된 키를 삭제했습니다."
                    : "Keychain에 안전하게 저장했습니다."
            } catch {
                configurationError = error.localizedDescription
                accessibilityFocus = .apiKey
            }
        }
    }

    private func applyAndDismiss() {
        guard !preferences.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            configurationError = MobileAgentError.emptyModel.localizedDescription
            accessibilityFocus = .model
            return
        }
        if preferences.currentProvider == .openAICompatible, !compatibleURLStatus.isValid {
            configurationError = compatibleURLStatus.text
            accessibilityFocus = .compatibleURL
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await controller.applyPreferences()
                dismiss()
            } catch {
                configurationError = error.localizedDescription
            }
        }
    }
}

struct MobileMemoryManagementView: View {
    let controller: MobileAgentController

    @State private var deletionRequest: MobileMemoryDeletionRequest?

    var body: some View {
        List {
            if controller.isRunning {
                Section {
                    Label(
                        "도치의 답변이 끝난 뒤 기억을 조회하거나 삭제할 수 있습니다.",
                        systemImage: "hourglass"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("기억 관리 일시 중지")
                    .accessibilityValue("도치가 답변하는 중입니다. 답변이 끝난 뒤 다시 시도해 주세요.")
                }
            }

            if let error = controller.memoryManagementErrorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("기억 관리 오류")
                        .accessibilityValue(error)
                    Button("오류 닫기") { controller.dismissMemoryManagementError() }
                        .frame(minHeight: 44)
                        .accessibilityInputLabels(["기억 오류 닫기", "오류 닫기"])
                }
            }

            if let notice = controller.memoryManagementNoticeMessage {
                Section {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("기억 관리 결과")
                        .accessibilityValue(notice)
                }
            }

            memoryRecordsSection

            Section {
                Label("영구 삭제 범위 격리", systemImage: "lock.shield")
                    .accessibilityIdentifier("memory-purge-isolation-guidance")
            } footer: {
                Text("영구 삭제는 현재 Dochi Mobile 사용자에게 속한 기억과 관련 로컬 기록에만 적용됩니다. 다른 앱, 다른 사용자, 앱 전체 범위의 기억은 유지합니다.")
                    .accessibilityIdentifier("memory-purge-isolation-detail")
            }

            if !controller.ownedMemoryRecords.isEmpty {
                Section {
                    Button("이 사용자의 모든 기억 영구 삭제", role: .destructive) {
                        deletionRequest = .all(count: controller.ownedMemoryRecords.count)
                    }
                    .frame(minHeight: 44)
                    .disabled(isOperationDisabled)
                    .accessibilityIdentifier("purge-all-owned-memories")
                    .accessibilityHint("확인 후 현재 앱과 사용자에게 속한 모든 기억을 복구할 수 없게 삭제합니다.")
                } footer: {
                    Text("다른 앱, 다른 사용자, 앱 전체 범위의 기억은 삭제하지 않습니다. 관련 로컬 이벤트와 검색 색인도 함께 영구 삭제됩니다.")
                }
            }
        }
        .accessibilityIdentifier("memory-management-list")
        .navigationTitle("저장된 기억")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(controller.isMemoryManagementBusy)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if controller.isLoadingOwnedMemories {
                    ProgressView()
                        .accessibilityLabel("저장된 기억 새로 고치는 중")
                } else {
                    Button {
                        Task { await controller.refreshOwnedMemories() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isOperationDisabled)
                    .accessibilityLabel("저장된 기억 새로 고침")
                    .accessibilityInputLabels(["기억 새로 고침", "새로 고침"])
                }
            }
        }
        .task { await controller.refreshOwnedMemories() }
        .refreshable { await controller.refreshOwnedMemories() }
        .confirmationDialog(
            deletionRequest?.title ?? "기억을 영구 삭제할까요?",
            isPresented: deletionConfirmationPresentation,
            titleVisibility: .visible,
            presenting: deletionRequest
        ) { request in
            Button(request.actionTitle, role: .destructive) {
                deletionRequest = nil
                Task {
                    switch request {
                    case .record(let record):
                        await controller.purgeOwnedMemory(record)
                    case .all:
                        await controller.purgeAllOwnedMemories()
                    }
                }
            }
            Button("취소", role: .cancel) { deletionRequest = nil }
        } message: { request in
            Text(request.message)
        }
    }

    @ViewBuilder
    private var memoryRecordsSection: some View {
        if controller.isLoadingOwnedMemories, controller.ownedMemoryRecords.isEmpty {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("저장된 기억을 불러오는 중…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("저장된 기억 불러오는 중")
            }
        } else if controller.ownedMemoryRecords.isEmpty {
            Section {
                ContentUnavailableView(
                    "저장된 기억이 없습니다",
                    systemImage: "brain.head.profile",
                    description: Text("현재 사용자에게 속한 기억이 생기면 과거 대화 범위까지 여기에 표시됩니다.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        } else {
            Section("저장된 기억 \(controller.ownedMemoryRecords.count)개") {
                ForEach(controller.ownedMemoryRecords) { record in
                    MobileMemoryRecordView(
                        record: record,
                        isPurging: controller.purgingMemoryID == record.id,
                        isDisabled: isOperationDisabled
                    ) {
                        deletionRequest = .record(record)
                    }
                }
            }
        }
    }

    private var isOperationDisabled: Bool {
        controller.isRunning || controller.isMemoryManagementBusy
    }

    private var deletionConfirmationPresentation: Binding<Bool> {
        Binding(
            get: { deletionRequest != nil },
            set: { isPresented in
                if !isPresented { deletionRequest = nil }
            }
        )
    }
}

private struct MobileMemoryRecordView: View {
    let record: MemoryRecord
    let isPurging: Bool
    let isDisabled: Bool
    let requestDeletion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(record.content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("기억 내용")
                .accessibilityValue(record.content)

            VStack(alignment: .leading, spacing: 6) {
                metadataLabel(
                    "범위",
                    value: MobileMemoryPresentation.scopeLabel(record.scope),
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                metadataLabel(
                    "종류",
                    value: MobileMemoryPresentation.kindLabel(record.kind),
                    systemImage: "tag"
                )
                metadataLabel(
                    "상태",
                    value: MobileMemoryPresentation.statusLabel(record),
                    systemImage: "circle.dotted"
                )
                metadataLabel(
                    "수정",
                    value: MobileMemoryPresentation.updatedLabel(record.updatedAt),
                    systemImage: "clock"
                )
            }

            Button(role: .destructive, action: requestDeletion) {
                if isPurging {
                    Label("영구 삭제 중…", systemImage: "trash")
                } else {
                    Label("이 기억 영구 삭제", systemImage: "trash")
                }
            }
            .frame(minHeight: 44)
            .disabled(isDisabled)
            .accessibilityLabel("기억 영구 삭제")
            .accessibilityValue(MobileMemoryPresentation.deletionPreview(record.content))
            .accessibilityHint("확인 후 이 기억과 관련 로컬 기록을 복구할 수 없게 삭제합니다.")
            .accessibilityInputLabels([
                "\(MobileMemoryPresentation.deletionPreview(record.content, maximumLength: 24)) 기억 삭제",
                "기억 삭제",
            ])
        }
        .padding(.vertical, 6)
    }

    private func metadataLabel(_ label: String, value: String, systemImage: String) -> some View {
        Label("\(label): \(value)", systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}

private enum MobileMemoryDeletionRequest: Identifiable {
    case record(MemoryRecord)
    case all(count: Int)

    var id: String {
        switch self {
        case .record(let record): "record-\(record.id.uuidString)"
        case .all: "all"
        }
    }

    var title: String {
        switch self {
        case .record: "이 기억을 영구 삭제할까요?"
        case .all: "모든 저장된 기억을 영구 삭제할까요?"
        }
    }

    var actionTitle: String {
        switch self {
        case .record: "이 기억 영구 삭제"
        case .all: "모두 영구 삭제"
        }
    }

    var message: String {
        switch self {
        case .record(let record):
            "‘\(MobileMemoryPresentation.deletionPreview(record.content))’ 기억과 관련 로컬 이벤트를 복구할 수 없게 삭제합니다."
        case .all(let count):
            "현재 Dochi Mobile 사용자에게 속한 기억 \(count)개와 관련 로컬 이벤트를 복구할 수 없게 삭제합니다. 다른 앱, 다른 사용자, 앱 전체 범위는 유지합니다."
        }
    }
}
