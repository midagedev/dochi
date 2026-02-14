import SwiftUI

/// 대화 목록 상단 헤더: 검색 + 필터 + 일괄 선택
struct ConversationListHeaderView: View {
    @Binding var searchText: String
    @Binding var filter: ConversationFilter
    @Binding var showFilterPopover: Bool
    @Bindable var viewModel: DochiViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("대화 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }

                // Filter button
                Button {
                    showFilterPopover.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(filter.isActive ? .blue : .secondary)
                        if filter.isActive {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("필터")

                // Multi-select button
                Button {
                    viewModel.toggleMultiSelectMode()
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 13))
                        .foregroundStyle(viewModel.isMultiSelectMode ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("일괄 선택 (⌘⇧M)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))
        }
    }
}
