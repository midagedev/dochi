import SwiftUI

/// G-3: 동기화 충돌 목록 시트 (600x500pt)
struct SyncConflictListView: View {
    let conflicts: [SyncConflict]
    let onResolve: (UUID, ConflictResolution) -> Void
    let onResolveAll: (ConflictResolution) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedConflict: SyncConflict?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("동기화 충돌")
                    .font(.headline)
                Text("(\(conflicts.count)건)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

            if conflicts.isEmpty {
                emptyState
            } else {
                // 일괄 해결 버튼
                HStack(spacing: 8) {
                    Button("모두 로컬 유지") {
                        onResolveAll(.keepLocal)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("모두 원격 유지") {
                        onResolveAll(.keepRemote)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // 충돌 목록
                List(conflicts) { conflict in
                    conflictRow(conflict)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedConflict = conflict
                        }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 600, height: 500)
        .sheet(item: $selectedConflict) { conflict in
            SyncConflictDetailView(
                conflict: conflict,
                onResolve: { resolution in
                    onResolve(conflict.id, resolution)
                    selectedConflict = nil
                }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("충돌이 없습니다")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("모든 데이터가 동기화되었습니다.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func conflictRow(_ conflict: SyncConflict) -> some View {
        HStack(spacing: 10) {
            // 엔티티 아이콘
            Image(systemName: conflict.entityType.iconName)
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(conflict.entityTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("로컬: \(conflict.localUpdatedAt, style: .relative)", systemImage: "laptopcomputer")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Label("원격: \(conflict.remoteUpdatedAt, style: .relative)", systemImage: "cloud")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 개별 해결 버튼
            HStack(spacing: 4) {
                Button("로컬") {
                    onResolve(conflict.id, .keepLocal)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("원격") {
                    onResolve(conflict.id, .keepRemote)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
