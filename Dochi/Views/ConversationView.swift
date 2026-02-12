import SwiftUI

struct ConversationView: View {
    let messages: [Message]
    let streamingText: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    MessageBubbleView(message: message)
                }

                if !streamingText.isEmpty {
                    MessageBubbleView(
                        message: Message(
                            role: .assistant,
                            content: streamingText
                        )
                    )
                }
            }
            .padding()
        }
    }
}
