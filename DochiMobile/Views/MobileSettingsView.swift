import SwiftUI

struct MobileSettingsView: View {
    @AppStorage("mobile_api_key") private var apiKey = ""
    @AppStorage("mobile_model") private var model = "claude-sonnet-4-5-20250929"
    @AppStorage("mobile_provider") private var provider = "anthropic"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("API 설정") {
                    SecureField("API 키", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    Picker("프로바이더", selection: $provider) {
                        Text("Anthropic").tag("anthropic")
                        Text("OpenAI").tag("openai")
                    }

                    TextField("모델", text: $model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("정보") {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}
