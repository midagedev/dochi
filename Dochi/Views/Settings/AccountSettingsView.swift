import SwiftUI

struct AccountSettingsView: View {
    var supabaseService: SupabaseServiceProtocol?
    var settings: AppSettings

    @State private var supabaseURL = ""
    @State private var supabaseAnonKey = ""
    @State private var configureError: String?
    @State private var showLoginSheet = false
    @State private var loginMode: LoginSheet.Mode = .signIn
    @State private var isSyncing = false
    @State private var syncStatus: String?
    @State private var lastSyncTime: Date?

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

    private func syncNow() {
        guard let service = supabaseService else { return }
        isSyncing = true
        syncStatus = "동기화 중..."
        Task {
            do {
                try await service.syncContext()
                try await service.syncConversations()
                lastSyncTime = Date()
                syncStatus = "완료"
            } catch {
                syncStatus = "실패: \(error.localizedDescription)"
            }
            isSyncing = false
        }
    }
}
