import SwiftUI

struct ToolsMenuSidebarView: View {
    @Binding var selectedToolSection: ContentView.ToolSection
    @Binding var selectedToolSessionId: UUID?
    @Binding var selectedToolProfileId: UUID?

    private let groupedSections: [(title: String, items: [ContentView.ToolSection])] = [
        ("개발 오케스트레이션", [.orchestration]),
        ("개인 생산성", [.kanban, .reminders]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("도구 메뉴")
                        .font(.system(size: 13, weight: .semibold))
                    Text("왼쪽에서는 메뉴를 선택하고, 상세 콘텐츠는 오른쪽에서 확인합니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                ForEach(groupedSections, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)

                        ForEach(group.items) { section in
                            toolSectionRow(section)
                        }
                    }
                }

                Spacer(minLength: 12)
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func toolSectionRow(_ section: ContentView.ToolSection) -> some View {
        let isSelected = selectedToolSection == section
        Button {
            selectedToolSection = section
            if section != .orchestration {
                selectedToolSessionId = nil
                selectedToolProfileId = nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(section.shortDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}
