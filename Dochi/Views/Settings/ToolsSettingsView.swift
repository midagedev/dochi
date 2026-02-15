import SwiftUI

struct ToolsSettingsView: View {
    let toolService: BuiltInToolService

    @State private var searchText = ""
    @State private var selectedCategory: ToolCategoryFilter = .all
    @State private var selectedTool: ToolInfo?

    enum ToolCategoryFilter: String, CaseIterable {
        case all = "전체"
        case baseline = "기본 제공"
        case conditional = "조건부"
        case safe = "safe"
        case sensitive = "sensitive"
        case restricted = "restricted"
    }

    private var tools: [ToolInfo] {
        toolService.allToolInfos
    }

    private var filteredTools: [ToolInfo] {
        tools.filter { tool in
            let matchesSearch = searchText.isEmpty
                || tool.name.localizedCaseInsensitiveContains(searchText)
                || tool.description.localizedCaseInsensitiveContains(searchText)

            let matchesCategory: Bool
            switch selectedCategory {
            case .all: matchesCategory = true
            case .baseline: matchesCategory = tool.isBaseline
            case .conditional: matchesCategory = !tool.isBaseline
            case .safe: matchesCategory = tool.category == .safe
            case .sensitive: matchesCategory = tool.category == .sensitive
            case .restricted: matchesCategory = tool.category == .restricted
            }

            return matchesSearch && matchesCategory
        }
    }

    private var groupedTools: [(String, [ToolInfo])] {
        let grouped = Dictionary(grouping: filteredTools) { $0.group }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                SettingsHelpButton(
                    title: "도구",
                    content: "도치가 사용할 수 있는 35개 내장 도구 목록입니다. \"기본 제공\" 도구는 항상 사용 가능하고, \"조건부\" 도구는 AI가 필요할 때 자동으로 활성화합니다. 권한 등급(safe/sensitive/restricted)에 따라 승인이 필요할 수 있습니다."
                )

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("도구 검색...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)

                Picker("", selection: $selectedCategory) {
                    ForEach(ToolCategoryFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Stats
            HStack(spacing: 16) {
                statBadge("전체", count: tools.count, color: .secondary)
                statBadge("기본", count: tools.filter(\.isBaseline).count, color: .blue)
                statBadge("Safe", count: tools.filter { $0.category == .safe }.count, color: .green)
                statBadge("Sensitive", count: tools.filter { $0.category == .sensitive }.count, color: .orange)
                statBadge("Restricted", count: tools.filter { $0.category == .restricted }.count, color: .red)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.03))

            Divider()

            // Tool List
            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedTools, id: \.0) { group, groupTools in
                            Section {
                                ForEach(groupTools) { tool in
                                    toolRow(tool)
                                }
                            } header: {
                                Text(group)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(minWidth: 280)

                // Detail
                if let tool = selectedTool {
                    toolDetailView(tool)
                        .frame(minWidth: 220)
                } else {
                    VStack {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 36))
                            .foregroundStyle(.quaternary)
                        Text("도구를 선택하세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Subviews

    private func statBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func toolRow(_ tool: ToolInfo) -> some View {
        Button {
            selectedTool = tool
        } label: {
            HStack(spacing: 8) {
                categoryIcon(tool.category)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(tool.name)
                            .font(.system(size: 12, design: .monospaced))
                            .fontWeight(.medium)
                            .lineLimit(1)

                        if tool.isBaseline {
                            Text("기본")
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .cornerRadius(3)
                        }
                    }

                    Text(tool.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedTool?.id == tool.id ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func categoryIcon(_ category: ToolCategory) -> some View {
        switch category {
        case .safe:
            Image(systemName: "checkmark.shield.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .sensitive:
            Image(systemName: "exclamationmark.shield.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .restricted:
            Image(systemName: "xmark.shield.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func toolDetailView(_ tool: ToolInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Name
                Text(tool.name)
                    .font(.system(size: 14, design: .monospaced))
                    .fontWeight(.bold)
                    .textSelection(.enabled)

                // Badges
                HStack(spacing: 8) {
                    categoryBadge(tool.category)

                    if tool.isBaseline {
                        badgeView("기본 제공", color: .blue)
                    } else {
                        badgeView("조건부", color: .purple)
                    }

                    badgeView(tool.isEnabled ? "활성" : "비활성", color: tool.isEnabled ? .green : .secondary)
                }

                Divider()

                // Description
                VStack(alignment: .leading, spacing: 4) {
                    Text("설명")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(tool.description)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                // Parameters
                if !tool.parameters.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("파라미터")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(tool.parameters) { param in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(param.name)
                                            .font(.system(size: 11, design: .monospaced))
                                            .fontWeight(.medium)
                                        Text(param.type)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        if param.isRequired {
                                            Text("필수")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    if !param.description.isEmpty {
                                        Text(param.description)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(6)
                    }
                }

                Spacer()
            }
            .padding(16)
        }
    }

    private func categoryBadge(_ category: ToolCategory) -> some View {
        let (text, color): (String, Color) = switch category {
        case .safe: ("Safe", .green)
        case .sensitive: ("Sensitive", .orange)
        case .restricted: ("Restricted", .red)
        }
        return badgeView(text, color: color)
    }

    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}
