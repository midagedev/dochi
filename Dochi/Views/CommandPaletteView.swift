import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private struct Command: Identifiable { let id = UUID(); let title: String; let icon: String; let action: () -> Void }

    private var commands: [Command] {
        [
            Command(title: "설정 열기", icon: "gear") { viewModel.showSettingsSheet = true },
            Command(title: "새 대화", icon: "plus") { viewModel.clearConversation() },
            Command(title: viewModel.isConnected ? "연결 해제" : "연결", icon: "dot.radiowaves.left.and.right") { viewModel.toggleConnection() }
        ] + viewModel.conversations.prefix(10).map { conv in
            Command(title: "대화 열기: \(conv.title)", icon: "text.bubble") { viewModel.loadConversation(conv) }
        }
    }

    private var filtered: [Command] {
        let q = query.lowercased()
        return q.isEmpty ? commands : commands.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("명령 검색...", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(AppSpacing.s)
            .background(AppColor.surface)

            Divider()

            List(filtered) { cmd in
                Button {
                    cmd.action()
                    viewModel.showCommandPalette = false
                } label: {
                    HStack {
                        Image(systemName: cmd.icon)
                        Text(cmd.title).compact(AppFont.body)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.bordered)
            .frame(width: 600, height: 420)
        }
        .background(AppColor.background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .shadow(radius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.border.opacity(0.6), lineWidth: 1)
        )
        .onExitCommand { viewModel.showCommandPalette = false }
    }
}

