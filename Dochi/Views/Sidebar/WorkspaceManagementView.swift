import SwiftUI

struct WorkspaceManagementView: View {
    @Bindable var viewModel: DochiViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newWorkspaceName = ""
    @State private var showDeleteConfirmation = false
    @State private var workspaceToDelete: UUID?

    private var workspaceIds: [UUID] {
        viewModel.contextService.listLocalWorkspaces()
    }

    private let defaultWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("워크스페이스 관리")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Workspace list
            List {
                Section("로컬 워크스페이스") {
                    ForEach(workspaceIds, id: \.self) { wsId in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wsId == defaultWorkspaceId ? "기본 워크스페이스" : wsId.uuidString.prefix(8) + "…")
                                    .font(.system(size: 13))
                                Text(wsId.uuidString)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if wsId == viewModel.sessionContext.workspaceId {
                                Text("현재")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }

                            if wsId != defaultWorkspaceId {
                                Button(role: .destructive) {
                                    workspaceToDelete = wsId
                                    showDeleteConfirmation = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .help("삭제")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.switchWorkspace(id: wsId)
                        }
                    }
                }

                Section("새 워크스페이스") {
                    HStack {
                        TextField("워크스페이스 이름", text: $newWorkspaceName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))

                        Button("생성") {
                            createWorkspace()
                        }
                        .disabled(newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 500, height: 400)
        .confirmationDialog(
            "이 워크스페이스를 삭제하시겠습니까?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let wsId = workspaceToDelete {
                    deleteWorkspace(wsId)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("워크스페이스의 모든 에이전트와 메모리가 삭제됩니다.")
        }
    }

    private func createWorkspace() {
        let id = UUID()
        viewModel.contextService.createLocalWorkspace(id: id)
        newWorkspaceName = ""
        viewModel.switchWorkspace(id: id)
    }

    private func deleteWorkspace(_ wsId: UUID) {
        if viewModel.sessionContext.workspaceId == wsId {
            viewModel.switchWorkspace(id: defaultWorkspaceId)
        }
        viewModel.contextService.deleteLocalWorkspace(id: wsId)
        workspaceToDelete = nil
    }
}
