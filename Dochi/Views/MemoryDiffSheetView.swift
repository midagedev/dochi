import SwiftUI

/// 메모리 변경 이력 diff 시트
struct MemoryDiffSheetView: View {
    let changelog: [ChangelogEntry]
    var onRevert: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text("메모리 변경 이력")
                    .font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            if changelog.isEmpty {
                emptyState
            } else {
                changelogList
            }
        }
        .frame(width: 560, height: 480)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("변경 이력이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("대화 종료 시 메모리가 자동으로 정리되면 이곳에 기록됩니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var changelogList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(changelog) { entry in
                    changelogEntryRow(entry)
                    Divider()
                        .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func changelogEntryRow(_ entry: ChangelogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Timestamp and summary
            HStack {
                Text(entry.timestamp, style: .relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("(\(entry.factsExtracted)건 추출, \(entry.duplicatesSkipped)건 중복)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()

                if let onRevert {
                    Button {
                        onRevert(entry.id)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9))
                            Text("되돌리기")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }

            // Changes
            ForEach(entry.changes) { change in
                HStack(spacing: 6) {
                    changeTypeIcon(change.type)
                        .frame(width: 14)

                    Text(scopeLabel(change.scope))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(scopeColor(change.scope).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(change.content)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
            }

            // Conflicts
            if !entry.conflicts.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("모순 \(entry.conflicts.count)건")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func changeTypeIcon(_ type: MemoryChange.ChangeType) -> some View {
        switch type {
        case .added:
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        case .updated:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
        case .removed:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        case .archived:
            Image(systemName: "archivebox")
                .font(.system(size: 10))
                .foregroundStyle(.purple)
        }
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
