import SwiftUI

struct PermissionInfoView: View {
    var onProceed: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("마이크/음성 인식 권한")
                    .font(.headline)
                Spacer()
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("음성 입력을 사용하려면 macOS 권한이 필요합니다.")
                    Text("이 안내는 한 번만 표시되며, ‘허용’하면 다음부터 다시 묻지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Button("취소", role: .cancel) { onCancel() }
                Spacer()
                Button("지금 허용") { onProceed() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 420)
        .background(.ultraThinMaterial)
    }
}

