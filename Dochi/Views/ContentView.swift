import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: DochiViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Conversation area
            ConversationView(
                messages: viewModel.currentConversation?.messages ?? [],
                streamingText: viewModel.streamingText
            )

            Divider()

            // Input area
            HStack(spacing: 8) {
                TextField("메시지를 입력하세요...", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .onSubmit {
                        viewModel.sendMessage()
                    }

                if viewModel.interactionState == .processing {
                    Button("취소") {
                        viewModel.cancelRequest()
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button("전송") {
                        viewModel.sendMessage()
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}
