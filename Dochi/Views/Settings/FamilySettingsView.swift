import SwiftUI

struct FamilySettingsView: View {
    let contextService: ContextServiceProtocol
    let settings: AppSettings
    let sessionContext: SessionContext
    var onProfilesChanged: (() -> Void)?

    @State private var profiles: [UserProfile] = []
    @State private var newMemberName: String = ""
    @State private var editingId: UUID?
    @State private var editingName: String = ""

    var body: some View {
        Form {
            Section("구성원 목록") {
                if profiles.isEmpty {
                    Text("등록된 구성원이 없습니다")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        HStack(spacing: 8) {
                            if editingId == profile.id {
                                TextField("이름", text: $editingName, onCommit: {
                                    commitEdit(profile: profile)
                                })
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)

                                Button("완료") {
                                    commitEdit(profile: profile)
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 12))

                                Text(profile.name)
                                    .font(.system(size: 13))

                                if !profile.aliases.isEmpty {
                                    Text("(\(profile.aliases.joined(separator: ", ")))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }

                                if sessionContext.currentUserId == profile.id.uuidString {
                                    Text("현재")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }

                                Spacer()

                                Button {
                                    editingId = profile.id
                                    editingName = profile.name
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("이름 편집")

                                Button(role: .destructive) {
                                    deleteProfile(profile)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.borderless)
                                .disabled(sessionContext.currentUserId == profile.id.uuidString)
                                .help(sessionContext.currentUserId == profile.id.uuidString ? "현재 사용자는 삭제할 수 없습니다" : "삭제")
                            }
                        }
                    }
                }
            }

            Section("구성원 추가") {
                HStack {
                    TextField("이름", text: $newMemberName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit {
                            addMember()
                        }

                    Button("추가") {
                        addMember()
                    }
                    .disabled(newMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("현재 사용자") {
                if let userId = sessionContext.currentUserId,
                   let current = profiles.first(where: { $0.id.uuidString == userId }) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(current.name)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("설정되지 않음")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            profiles = contextService.loadProfiles()
        }
    }

    private func addMember() {
        let name = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let profile = UserProfile(name: name)
        profiles.append(profile)
        contextService.saveProfiles(profiles)
        newMemberName = ""
        onProfilesChanged?()
        Log.app.info("Added family member: \(name)")
    }

    private func commitEdit(profile: UserProfile) {
        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            editingId = nil
            return
        }

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].name = name
            contextService.saveProfiles(profiles)
            onProfilesChanged?()
            Log.app.info("Renamed family member to: \(name)")
        }
        editingId = nil
    }

    private func deleteProfile(_ profile: UserProfile) {
        guard sessionContext.currentUserId != profile.id.uuidString else { return }
        profiles.removeAll { $0.id == profile.id }
        contextService.saveProfiles(profiles)
        onProfilesChanged?()
        Log.app.info("Deleted family member: \(profile.name)")
    }
}
