import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            Text(message.content)
                .padding(10)
                .background(backgroundColor)
                .cornerRadius(12)
                .foregroundStyle(foregroundColor)

            if message.role == .assistant || message.role == .system {
                Spacer()
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: .blue.opacity(0.8)
        case .assistant: .secondary.opacity(0.15)
        case .system: .orange.opacity(0.15)
        case .tool: .green.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}
