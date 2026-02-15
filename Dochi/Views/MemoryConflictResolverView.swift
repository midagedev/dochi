import SwiftUI

/// 메모리 모순 해결 시트
struct MemoryConflictResolverView: View {
    let conflicts: [MemoryConflict]
    var onResolve: (([UUID: MemoryConflictResolution]) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var resolutions: [UUID: MemoryConflictResolution] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("메모리 모순 해결")
                    .font(.headline)
                Spacer()

                Text("\(conflicts.count)건")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            if conflicts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conflicts) { conflict in
                            conflictCard(conflict)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Footer
            HStack {
                Button("전체 기존 유지") {
                    for conflict in conflicts {
                        resolutions[conflict.id] = .keepExisting
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("전체 새 항목 적용") {
                    for conflict in conflicts {
                        resolutions[conflict.id] = .useNew
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("취소") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("적용") {
                    onResolve?(resolutions)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(resolutions.count < conflicts.count)
            }
            .padding()
        }
        .frame(width: 520, height: 400)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("해결할 모순이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func conflictCard(_ conflict: MemoryConflict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Scope badge
            HStack {
                Text(scopeLabel(conflict.scope))
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scopeColor(conflict.scope).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(conflict.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Existing fact
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("기존")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(conflict.existingFact)
                        .font(.system(size: 11))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // New fact
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("새 항목")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text(conflict.newFact)
                        .font(.system(size: 11))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.blue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Resolution picker
            Picker("", selection: Binding(
                get: { resolutions[conflict.id] ?? .keepExisting },
                set: { resolutions[conflict.id] = $0 }
            )) {
                Text("기존 유지").tag(MemoryConflictResolution.keepExisting)
                Text("새 항목 적용").tag(MemoryConflictResolution.useNew)
                Text("둘 다 유지").tag(MemoryConflictResolution.keepBoth)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
        .padding(10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    resolutions[conflict.id] != nil
                        ? Color.green.opacity(0.3)
                        : Color.secondary.opacity(0.15),
                    lineWidth: 1
                )
        )
    }

    private func scopeLabel(_ scope: MemoryScope) -> String {
        switch scope {
        case .personal: return "개인"
        case .workspace: return "워크스페이스"
        case .agent: return "에이전트"
        }
    }

    private func scopeColor(_ scope: MemoryScope) -> Color {
        switch scope {
        case .personal: return .blue
        case .workspace: return .green
        case .agent: return .purple
        }
    }
}
