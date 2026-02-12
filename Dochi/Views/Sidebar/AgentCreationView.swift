import SwiftUI

struct AgentCreationView: View {
    @Bindable var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var agentName = ""
    @State private var wakeWord = ""
    @State private var agentDescription = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("에이전트 생성")
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

            Form {
                Section("기본 정보") {
                    TextField("이름 (필수)", text: $agentName)
                        .textFieldStyle(.roundedBorder)

                    TextField("웨이크워드 (선택)", text: $wakeWord)
                        .textFieldStyle(.roundedBorder)

                    TextField("설명 (선택)", text: $agentDescription)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("취소") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("생성") {
                            createAgent()
                        }
                        .disabled(agentName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)
        }
        .frame(width: 400, height: 300)
    }

    private func createAgent() {
        let name = agentName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let wsId = viewModel.sessionContext.workspaceId
        let existing = viewModel.contextService.listAgents(workspaceId: wsId)
        if existing.contains(name) {
            errorMessage = "이미 같은 이름의 에이전트가 있습니다."
            return
        }

        let wake = wakeWord.trimmingCharacters(in: .whitespaces)
        let desc = agentDescription.trimmingCharacters(in: .whitespaces)

        viewModel.contextService.createAgent(
            workspaceId: wsId,
            name: name,
            wakeWord: wake.isEmpty ? nil : wake,
            description: desc.isEmpty ? nil : desc
        )

        viewModel.switchAgent(name: name)
        dismiss()
    }
}
