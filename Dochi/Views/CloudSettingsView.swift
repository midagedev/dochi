import SwiftUI

struct CloudSettingsView: View {
    @ObservedObject var supabaseService: SupabaseService
    @State private var showLogin = false
    @State private var showCreateWorkspace = false
    @State private var showJoinWorkspace = false
    @State private var showSetupConfig = false
    @State private var workspaces: [Workspace] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !supabaseService.isConfigured {
                configurationNeededView
            } else {
                switch supabaseService.authState {
                case .signedOut:
                    signedOutView
                case .signedIn(_, let email):
                    signedInView(email: email)
                }
            }
        }
    }

    // MARK: - Configuration Needed

    private var configurationNeededView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supabase 설정이 필요합니다")
                .foregroundStyle(.secondary)
            Button("설정") {
                showSetupConfig = true
            }
        }
        .sheet(isPresented: $showSetupConfig) {
            SupabaseConfigView(supabaseService: supabaseService)
        }
    }

    // MARK: - Signed Out

    private var signedOutView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("멀티 디바이스 동기화를 위해 로그인하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                showLogin = true
            } label: {
                Label("로그인", systemImage: "person.crop.circle")
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView(supabaseService: supabaseService)
        }
    }

    // MARK: - Signed In

    private func signedInView(email: String?) -> some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(email ?? "로그인됨")
                        .font(.body)
                    if let ws = supabaseService.selectedWorkspace {
                        Text("워크스페이스: \(ws.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("로그아웃", role: .destructive) {
                    Task {
                        do {
                            try await supabaseService.signOut()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderless)
            }

            workspaceSection

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Workspace Section

    private var workspaceSection: some View {
        Group {
            if !workspaces.isEmpty {
                ForEach(workspaces) { ws in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ws.name)
                                .font(.body)
                            if let code = ws.inviteCode {
                                Text("초대 코드: \(code)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        if supabaseService.selectedWorkspace?.id == ws.id {
                            Text("현재")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        } else {
                            Button("선택") {
                                supabaseService.setCurrentWorkspace(ws)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                        Button {
                            Task {
                                do {
                                    let newCode = try await supabaseService.regenerateInviteCode(workspaceId: ws.id)
                                    // Update local list
                                    if let idx = workspaces.firstIndex(where: { $0.id == ws.id }) {
                                        workspaces[idx].inviteCode = newCode
                                    }
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("초대 코드 재발급", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }

            HStack {
                Button {
                    showCreateWorkspace = true
                } label: {
                    Label("워크스페이스 생성", systemImage: "plus.circle")
                }

                Button {
                    showJoinWorkspace = true
                } label: {
                    Label("초대 코드로 참가", systemImage: "person.badge.plus")
                }
            }
            Button("새로고침") { loadWorkspaces() }
        }
        .onAppear { loadWorkspaces() }
        .sheet(isPresented: $showCreateWorkspace) {
            CreateWorkspaceView(supabaseService: supabaseService) {
                loadWorkspaces()
            }
        }
        .sheet(isPresented: $showJoinWorkspace) {
            JoinWorkspaceView(supabaseService: supabaseService) {
                loadWorkspaces()
            }
        }
    }

    private func loadWorkspaces() {
        Task {
            do {
                workspaces = try await supabaseService.listWorkspaces()
            } catch {
                Log.cloud.error("워크스페이스 목록 로드 실패: \(error, privacy: .public)")
            }
        }
    }
}

// MARK: - Login View

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var supabaseService: SupabaseService
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isSignUp ? "회원가입" : "로그인")
                    .font(.headline)
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            VStack(spacing: 16) {
                // Apple Sign In
                Button {
                    performAppleSignIn()
                } label: {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("Apple로 로그인")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)

                Divider()

                // Email
                TextField("이메일", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)

                SecureField("비밀번호", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isSignUp ? .newPassword : .password)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    performEmailAuth()
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(isSignUp ? "가입" : "로그인")
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)

                Button(isSignUp ? "이미 계정이 있으신가요?" : "계정이 없으신가요?") {
                    isSignUp.toggle()
                    errorMessage = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .font(.caption)
            }
            .padding()

            Spacer()
        }
        .frame(width: 360, height: 400)
    }

    private func performAppleSignIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await supabaseService.signInWithApple()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func performEmailAuth() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if isSignUp {
                    try await supabaseService.signUpWithEmail(email: email, password: password)
                } else {
                    try await supabaseService.signInWithEmail(email: email, password: password)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Create Workspace View

struct CreateWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var supabaseService: SupabaseService
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    var onCreated: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("워크스페이스 생성")
                    .font(.headline)
                Spacer()
                Button("생성") {
                    create()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                TextField("워크스페이스 이름", text: $name, prompt: Text("예: 우리 가족"))
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .padding()

            Spacer()
        }
        .frame(width: 360, height: 200)
    }

    private func create() {
        isLoading = true
        Task {
            do {
                _ = try await supabaseService.createWorkspace(name: name)
                onCreated()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Join Workspace View

struct JoinWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var supabaseService: SupabaseService
    @State private var inviteCode = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    var onJoined: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("워크스페이스 참가")
                    .font(.headline)
                Spacer()
                Button("참가") {
                    join()
                }
                .disabled(inviteCode.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                TextField("초대 코드", text: $inviteCode, prompt: Text("예: ABCD1234"))
                    .textFieldStyle(.roundedBorder)
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .padding()

            Spacer()
        }
        .frame(width: 360, height: 200)
    }

    private func join() {
        isLoading = true
        Task {
            do {
                _ = try await supabaseService.joinWorkspace(inviteCode: inviteCode.trimmingCharacters(in: .whitespaces))
                onJoined()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Supabase Config View

struct SupabaseConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var supabaseService: SupabaseService
    @State private var url = ""
    @State private var anonKey = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Supabase 설정")
                    .font(.headline)
                Spacer()
                Button("저장") {
                    supabaseService.configure(url: url, anonKey: anonKey)
                    dismiss()
                }
                .disabled(url.isEmpty || anonKey.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            Form {
                TextField("Supabase URL", text: $url, prompt: Text("https://xxxxx.supabase.co"))
                    .textFieldStyle(.roundedBorder)
                SecureField("Anon Key", text: $anonKey, prompt: Text("sb_publishable_..."))
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .padding()

            HStack {
                Text("설정 후 앱을 재시작해주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 400, height: 260)
    }
}
