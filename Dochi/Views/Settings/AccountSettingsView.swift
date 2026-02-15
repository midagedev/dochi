import SwiftUI

struct AccountSettingsView: View {
    var supabaseService: SupabaseServiceProtocol?
    var settings: AppSettings
    var syncEngine: SyncEngine?

    @State private var supabaseURL = ""
    @State private var supabaseAnonKey = ""
    @State private var configureError: String?
    @State private var showLoginSheet = false
    @State private var loginMode: LoginSheet.Mode = .signIn
    @State private var isSyncing = false
    @State private var syncStatus: String?
    @State private var lastSyncTime: Date?
    @State private var showInitialSyncWizard = false
    @State private var showConflictSheet = false

    var body: some View {
        Form {
            Section {
                DisclosureGroup("서버 설정") {
                    TextField("URL", text: $supabaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    SecureField("Anon Key", text: $supabaseAnonKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    HStack {
                        Button("연결") {
                            configureSupabase()
                        }
                        .disabled(supabaseURL.isEmpty || supabaseAnonKey.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if let error = configureError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if supabaseService?.isConfigured == true {
                            Label("연결됨", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(
                    title: "Supabase 연결",
                    helpContent: "클라우드 동기화를 위한 Supabase 서버를 연결합니다. 대화, 메모리, 설정을 여러 기기에서 동기화할 수 있습니다. 자체 Supabase 프로젝트를 만들어 사용합니다."
                )
            }

            Section("인증") {
                if let service = supabaseService, service.authState.isSignedIn {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(authEmail ?? "로그인됨")
                            .font(.system(size: 13))
                        Spacer()
                        Button("로그아웃") {
                            Task {
                                try? await service.signOut()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        Button("로그인") {
                            loginMode = .signIn
                            showLoginSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("회원가입") {
                            loginMode = .signUp
                            showLoginSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .disabled(supabaseService?.isConfigured != true)
                }
            }

            Section("동기화") {
                // SyncState 표시
                if let engine = syncEngine {
                    HStack(spacing: 8) {
                        Image(systemName: engine.syncState.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(syncStateColor(engine.syncState))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.syncState.displayText)
                                .font(.system(size: 12, weight: .medium))
                            if let lastSync = engine.lastSuccessfulSync {
                                Text("마지막: \(lastSync, style: .relative)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if engine.pendingLocalChanges > 0 {
                            Text("대기 \(engine.pendingLocalChanges)건")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    // 충돌 건수
                    if !engine.syncConflicts.isEmpty {
                        Button {
                            showConflictSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("충돌 \(engine.syncConflicts.count)건 해결하기")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        if let time = lastSyncTime {
                            Text("마지막 동기화: \(time, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("아직 동기화하지 않음")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let status = syncStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        syncNow()
                    } label: {
                        HStack(spacing: 4) {
                            if isSyncing {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                            Text("수동 동기화")
                        }
                    }
                    .disabled(isSyncing || supabaseService?.authState.isSignedIn != true)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if syncEngine != nil {
                        Button("전체 동기화") {
                            Task {
                                isSyncing = true
                                await syncEngine?.fullSync()
                                isSyncing = false
                            }
                        }
                        .disabled(isSyncing || supabaseService?.authState.isSignedIn != true)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // 동기화 설정 (G-3)
            Section("동기화 설정") {
                Toggle("자동 동기화", isOn: Binding(
                    get: { settings.autoSyncEnabled },
                    set: { settings.autoSyncEnabled = $0 }
                ))
                .font(.system(size: 13))

                Toggle("실시간 동기화", isOn: Binding(
                    get: { settings.realtimeSyncEnabled },
                    set: { settings.realtimeSyncEnabled = $0 }
                ))
                .font(.system(size: 13))
                .disabled(!settings.autoSyncEnabled)

                DisclosureGroup("동기화 대상") {
                    Toggle("대화", isOn: Binding(
                        get: { settings.syncConversations },
                        set: { settings.syncConversations = $0 }
                    ))
                    .font(.system(size: 12))

                    Toggle("메모리", isOn: Binding(
                        get: { settings.syncMemory },
                        set: { settings.syncMemory = $0 }
                    ))
                    .font(.system(size: 12))

                    Toggle("칸반", isOn: Binding(
                        get: { settings.syncKanban },
                        set: { settings.syncKanban = $0 }
                    ))
                    .font(.system(size: 12))

                    Toggle("프로필", isOn: Binding(
                        get: { settings.syncProfiles },
                        set: { settings.syncProfiles = $0 }
                    ))
                    .font(.system(size: 12))
                }
                .font(.system(size: 13))

                Picker("충돌 전략", selection: Binding(
                    get: { settings.conflictResolutionStrategy },
                    set: { settings.conflictResolutionStrategy = $0 }
                )) {
                    Text("최근 수정 우선").tag("lastWriteWins")
                    Text("수동 선택").tag("manual")
                }
                .font(.system(size: 13))
            }

            // 데이터 관리 (G-3)
            Section("데이터 관리") {
                Button("초기 업로드") {
                    showInitialSyncWizard = true
                }
                .disabled(supabaseService?.authState.isSignedIn != true)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            supabaseURL = settings.supabaseURL
            supabaseAnonKey = settings.supabaseAnonKey
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet(
                supabaseService: supabaseService,
                mode: loginMode
            )
        }
        .sheet(isPresented: $showInitialSyncWizard) {
            if let engine = syncEngine {
                InitialSyncWizardView(
                    syncEngine: engine,
                    onComplete: {}
                )
            }
        }
        .sheet(isPresented: $showConflictSheet) {
            if let engine = syncEngine {
                SyncConflictListView(
                    conflicts: engine.syncConflicts,
                    onResolve: { id, resolution in
                        engine.resolveConflict(id: id, resolution: resolution)
                    },
                    onResolveAll: { resolution in
                        engine.resolveAllConflicts(resolution: resolution)
                    }
                )
            }
        }
    }

    private var authEmail: String? {
        guard let service = supabaseService else { return nil }
        if case .signedIn(_, let email) = service.authState {
            return email
        }
        return nil
    }

    private func configureSupabase() {
        guard let url = URL(string: supabaseURL.trimmingCharacters(in: .whitespaces)) else {
            configureError = "유효하지 않은 URL"
            return
        }
        let key = supabaseAnonKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            configureError = "Anon Key를 입력하세요"
            return
        }

        settings.supabaseURL = supabaseURL
        settings.supabaseAnonKey = supabaseAnonKey
        supabaseService?.configure(url: url, anonKey: key)
        configureError = nil
    }

    private func syncStateColor(_ state: SyncState) -> Color {
        switch state {
        case .idle: .green
        case .syncing: .blue
        case .conflict: .orange
        case .error: .red
        case .offline: .gray
        case .disabled: .gray
        }
    }

    private func syncNow() {
        isSyncing = true
        syncStatus = "동기화 중..."
        Task {
            if let engine = syncEngine {
                await engine.sync()
                lastSyncTime = engine.lastSuccessfulSync
                syncStatus = engine.syncState == .idle ? "완료" : engine.syncState.displayText
            } else if let service = supabaseService {
                do {
                    try await service.syncContext()
                    try await service.syncConversations()
                    lastSyncTime = Date()
                    syncStatus = "완료"
                } catch {
                    syncStatus = "실패: \(error.localizedDescription)"
                }
            }
            isSyncing = false
        }
    }
}
