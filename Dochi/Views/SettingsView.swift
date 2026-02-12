import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("일반", systemImage: "gear")
                }

            LLMSettingsView()
                .tabItem {
                    Label("AI 모델", systemImage: "brain")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("일반 설정")
                .font(.headline)
            // TODO: Phase 1
        }
        .padding()
    }
}

struct LLMSettingsView: View {
    var body: some View {
        Form {
            Text("AI 모델 설정")
                .font(.headline)
            // TODO: Phase 1
        }
        .padding()
    }
}
