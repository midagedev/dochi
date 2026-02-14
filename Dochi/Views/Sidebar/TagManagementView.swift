import SwiftUI

/// 태그 CRUD 시트
struct TagManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: DochiViewModel
    @State private var newTagName: String = ""
    @State private var newTagColor: String = "blue"
    @State private var editingTagId: UUID?
    @State private var editingName: String = ""
    @State private var showDeleteConfirm: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tag")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text("태그 관리")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            // Tag list
            if viewModel.conversationTags.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tag.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("태그를 추가하여 대화를 분류하세요")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(viewModel.conversationTags) { tag in
                        tagRow(tag)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Add new tag
            HStack(spacing: 8) {
                // Color picker
                Menu {
                    ForEach(ConversationTag.availableColors, id: \.self) { color in
                        Button {
                            newTagColor = color
                        } label: {
                            HStack {
                                Circle()
                                    .fill(tagColor(color))
                                    .frame(width: 10, height: 10)
                                Text(colorDisplayName(color))
                                if color == newTagColor {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Circle()
                        .fill(tagColor(newTagColor))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)

                TextField("새 태그 이름", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        addTag()
                    }

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(newTagName.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newTagName.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360, height: 400)
    }

    @ViewBuilder
    private func tagRow(_ tag: ConversationTag) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tagColor(tag.color))
                .frame(width: 10, height: 10)

            if editingTagId == tag.id {
                TextField("태그 이름", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        saveEdit(tag)
                    }
            } else {
                Text(tag.name)
                    .font(.system(size: 13))
            }

            Spacer()

            // Usage count
            let count = tagUsageCount(tag.name)
            Text("\(count)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())

            if editingTagId == tag.id {
                Button {
                    saveEdit(tag)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            } else {
                // Color menu
                Menu {
                    ForEach(ConversationTag.availableColors, id: \.self) { color in
                        Button {
                            var updated = tag
                            updated.color = color
                            viewModel.updateTag(updated)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(tagColor(color))
                                    .frame(width: 10, height: 10)
                                Text(colorDisplayName(color))
                                if color == tag.color {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            // Edit/Delete
            if editingTagId != tag.id {
                Button {
                    editingTagId = tag.id
                    editingName = tag.name
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    showDeleteConfirm = tag.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .alert("태그 삭제", isPresented: Binding(
                    get: { showDeleteConfirm == tag.id },
                    set: { if !$0 { showDeleteConfirm = nil } }
                )) {
                    Button("취소", role: .cancel) {}
                    Button("삭제", role: .destructive) {
                        viewModel.deleteTag(id: tag.id)
                    }
                } message: {
                    Text("'\(tag.name)' 태그를 삭제합니다. 모든 대화에서 이 태그가 제거됩니다.")
                }
            }
        }
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !viewModel.conversationTags.contains(where: { $0.name == name }) else { return }

        let tag = ConversationTag(name: name, color: newTagColor)
        viewModel.addTag(tag)
        newTagName = ""
    }

    private func saveEdit(_ tag: ConversationTag) {
        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            editingTagId = nil
            return
        }
        var updated = tag
        updated.name = name
        viewModel.updateTag(updated)
        editingTagId = nil
    }

    private func tagUsageCount(_ tagName: String) -> Int {
        viewModel.conversations.filter { $0.tags.contains(tagName) }.count
    }

    private func colorDisplayName(_ color: String) -> String {
        switch color {
        case "red": return "빨강"
        case "orange": return "주황"
        case "yellow": return "노랑"
        case "green": return "초록"
        case "blue": return "파랑"
        case "purple": return "보라"
        case "pink": return "분홍"
        case "brown": return "갈색"
        case "gray": return "회색"
        default: return color
        }
    }
}
