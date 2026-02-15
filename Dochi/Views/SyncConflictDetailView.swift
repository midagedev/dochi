import SwiftUI

/// G-3: 동기화 충돌 상세 비교 뷰
struct SyncConflictDetailView: View {
    let conflict: SyncConflict
    let onResolve: (ConflictResolution) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mergedText: String = ""
    @State private var showMergeEditor: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: conflict.entityType.iconName)
                    .foregroundStyle(.orange)
                Text(conflict.entityTitle)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // 좌우 비교
            HStack(spacing: 0) {
                // 로컬
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 12))
                        Text("로컬")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.blue)

                    Text("수정: \(conflict.localUpdatedAt, style: .date) \(conflict.localUpdatedAt, style: .time)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(conflict.localPreview)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(8)
                    .background(.secondary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button("로컬 유지") {
                        onResolve(.keepLocal)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }
                .padding()
                .frame(maxWidth: .infinity)

                Divider()

                // 원격
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "cloud")
                            .font(.system(size: 12))
                        Text("원격")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.green)

                    Text("수정: \(conflict.remoteUpdatedAt, style: .date) \(conflict.remoteUpdatedAt, style: .time)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(conflict.remotePreview)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(8)
                    .background(.secondary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button("원격 유지") {
                        onResolve(.keepRemote)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }

            Divider()

            // 수동 병합 (메모리 충돌에서만)
            if conflict.entityType == .memory {
                if showMergeEditor {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("수동 병합")
                            .font(.system(size: 12, weight: .semibold))

                        TextEditor(text: $mergedText)
                            .font(.system(size: 12))
                            .frame(height: 100)
                            .border(Color.secondary.opacity(0.2))

                        HStack {
                            Spacer()
                            Button("병합 적용") {
                                onResolve(.merge)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding()
                } else {
                    Button("수동 병합...") {
                        mergedText = conflict.localPreview + "\n---\n" + conflict.remotePreview
                        showMergeEditor = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}
