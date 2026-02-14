import SwiftUI

struct SidebarHeaderView: View {
    @Bindable var viewModel: DochiViewModel
    @State private var showWorkspaceManagement = false
    @State private var showAgentCreation = false
    @State private var showAgentDetail = false
    @State private var showFamilySettings = false

    private var workspaceIds: [UUID] {
        viewModel.contextService.listLocalWorkspaces()
    }

    private var currentWorkspaceId: UUID {
        viewModel.sessionContext.workspaceId
    }

    private var agents: [String] {
        viewModel.contextService.listAgents(workspaceId: currentWorkspaceId)
    }

    private var profiles: [UserProfile] {
        viewModel.userProfiles
    }

    var body: some View {
        VStack(spacing: 6) {
            // Workspace picker row
            HStack(spacing: 4) {
                Menu {
                    ForEach(workspaceIds, id: \.self) { wsId in
                        Button {
                            viewModel.switchWorkspace(id: wsId)
                        } label: {
                            HStack {
                                Text(wsId == UUID(uuidString: "00000000-0000-0000-0000-000000000000") ? "기본 워크스페이스" : wsId.uuidString.prefix(8) + "…")
                                if wsId == currentWorkspaceId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(currentWorkspaceId == UUID(uuidString: "00000000-0000-0000-0000-000000000000") ? "기본 워크스페이스" : String(currentWorkspaceId.uuidString.prefix(8)) + "…")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button {
                    showWorkspaceManagement = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("워크스페이스 관리")
            }

            // Agent picker row
            HStack(spacing: 4) {
                Menu {
                    ForEach(agents, id: \.self) { agentName in
                        Button {
                            viewModel.switchAgent(name: agentName)
                        } label: {
                            HStack {
                                Text(agentName)
                                if agentName == viewModel.settings.activeAgentName {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    if agents.isEmpty {
                        Text("에이전트 없음")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(viewModel.settings.activeAgentName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button {
                    showAgentDetail = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("에이전트 설정")

                Button {
                    showAgentCreation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("에이전트 추가")
            }

            // User picker row
            HStack(spacing: 4) {
                Menu {
                    ForEach(profiles) { profile in
                        Button {
                            viewModel.switchUser(profile: profile)
                        } label: {
                            HStack {
                                Text(profile.name)
                                if viewModel.sessionContext.currentUserId == profile.id.uuidString {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    if profiles.isEmpty {
                        Text("등록된 사용자 없음")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(viewModel.currentUserName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button {
                    showFamilySettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("가족 설정")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(isPresented: $showWorkspaceManagement) {
            WorkspaceManagementView(viewModel: viewModel)
        }
        .sheet(isPresented: $showAgentDetail) {
            AgentDetailView(
                agentName: viewModel.settings.activeAgentName,
                contextService: viewModel.contextService,
                settings: viewModel.settings,
                sessionContext: viewModel.sessionContext,
                onDelete: {
                    viewModel.deleteAgent(name: viewModel.settings.activeAgentName)
                }
            )
        }
        .sheet(isPresented: $showAgentCreation) {
            AgentCreationView(viewModel: viewModel)
        }
        .sheet(isPresented: $showFamilySettings) {
            FamilySettingsView(
                contextService: viewModel.contextService,
                settings: viewModel.settings,
                sessionContext: viewModel.sessionContext,
                onProfilesChanged: { viewModel.reloadProfiles() }
            )
            .frame(width: 500, height: 400)
        }
    }
}
