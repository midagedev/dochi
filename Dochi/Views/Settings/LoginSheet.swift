import SwiftUI

struct LoginSheet: View {
    var supabaseService: SupabaseServiceProtocol?
    @State var mode: Mode

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var successMessage: String?

    enum Mode: String, CaseIterable {
        case signIn = "로그인"
        case signUp = "회원가입"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("계정")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            VStack(spacing: 16) {
                // Mode picker
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                TextField("이메일", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)

                SecureField("비밀번호", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if let success = successMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                }

                Button {
                    submit()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        Text(mode.rawValue)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)

            Spacer()
        }
        .frame(width: 360, height: 320)
    }

    private func submit() {
        guard let service = supabaseService else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                switch mode {
                case .signIn:
                    try await service.signInWithEmail(email: email, password: password)
                    dismiss()
                case .signUp:
                    try await service.signUpWithEmail(email: email, password: password)
                    if service.authState.isSignedIn {
                        dismiss()
                    } else {
                        successMessage = "확인 이메일을 발송했습니다. 이메일을 확인 후 로그인하세요."
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
