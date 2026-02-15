import SwiftUI

struct ExternalToolListView: View {
    let manager: ExternalToolSessionManagerProtocol
    @Binding var selectedSessionId: UUID?
    @Binding var selectedProfileId: UUID?
    @State private var showProfileEditor = false
    @State private var editingProfile: ExternalToolProfile?
    @State private var searchText = ""

    private var runningSessions: [ExternalToolSession] {
        manager.sessions.filter { $0.status != .dead }
    }

    private var stoppedSessions: [ExternalToolSession] {
        manager.sessions.filter { $0.status == .dead }
    }

    private var unlaunchedProfiles: [ExternalToolProfile] {
        let activeProfileIds = Set(manager.sessions.map(\.profileId))
        return manager.profiles.filter { !activeProfileIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if manager.profiles.isEmpty {
                emptyStateView
            } else {
                listContent
            }

            Divider()

            // Add profile button
            Button {
                editingProfile = nil
                showProfileEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                    Text("프로파일 추가")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showProfileEditor) {
            ExternalToolProfileEditorView(
                manager: manager,
                existingProfile: editingProfile,
                onSave: { profile in
                    manager.saveProfile(profile)
                    showProfileEditor = false
                },
                onCancel: {
                    showProfileEditor = false
                }
            )
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hammer")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("등록된 외부 AI 도구가 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Claude Code, Codex, aider 등을 추가하여\n도치에서 통합 관리하세요.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("프로파일 추가") {
                editingProfile = nil
                showProfileEditor = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Running sessions
                if !runningSessions.isEmpty {
                    sectionHeader("실행 중")
                    ForEach(runningSessions) { session in
                        sessionRow(session: session)
                    }
                }

                // Stopped sessions
                if !stoppedSessions.isEmpty {
                    sectionHeader("중지됨")
                    ForEach(stoppedSessions) { session in
                        sessionRow(session: session)
                    }
                }

                // Unlaunched profiles
                if !unlaunchedProfiles.isEmpty {
                    sectionHeader("프로파일")
                    ForEach(unlaunchedProfiles) { profile in
                        profileRow(profile: profile)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func sessionRow(session: ExternalToolSession) -> some View {
        let profile = manager.profiles.first(where: { $0.id == session.profileId })
        let isSelected = selectedSessionId == session.id

        Button {
            selectedSessionId = session.id
            selectedProfileId = nil
        } label: {
            HStack(spacing: 8) {
                statusIndicator(session.status)
                    .frame(width: 10)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(profile?.name ?? "알 수 없음")
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer()
                        Text(session.status.displayText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Text(profile?.workingDirectory ?? "~")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        if profile?.isRemote == true {
                            Text("SSH")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        } else {
                            Text("로컬")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func profileRow(profile: ExternalToolProfile) -> some View {
        let isSelected = selectedProfileId == profile.id

        Button {
            selectedProfileId = profile.id
            selectedSessionId = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                Text("\(profile.name) (미시작)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("시작") {
                Task { try? await manager.startSession(profileId: profile.id) }
            }
            Button("편집") {
                editingProfile = profile
                showProfileEditor = true
            }
            Divider()
            Button("삭제", role: .destructive) {
                manager.deleteProfile(id: profile.id)
            }
        }
    }

    @ViewBuilder
    private func statusIndicator(_ status: ExternalToolStatus) -> some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .opacity(status == .unknown ? 0.5 : 1.0)
    }
}

// MARK: - ExternalToolStatus Helpers

extension ExternalToolStatus {
    var color: Color {
        switch self {
        case .idle: return .green
        case .busy: return .blue
        case .waiting: return .orange
        case .error: return .red
        case .dead: return .gray
        case .unknown: return .gray
        }
    }

    var displayText: String {
        switch self {
        case .idle: return "유휴"
        case .busy: return "작업 중"
        case .waiting: return "입력 대기"
        case .error: return "에러"
        case .dead: return "종료"
        case .unknown: return "확인 중"
        }
    }
}
