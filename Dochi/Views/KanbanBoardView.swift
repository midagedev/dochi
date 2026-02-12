import SwiftUI

// MARK: - Kanban Board View

struct KanbanBoardView: View {
    let board: KanbanBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(board.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(board.cards.count)개 카드")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Columns
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(board.columns, id: \.self) { column in
                        KanbanColumnView(
                            columnName: column,
                            cards: board.cards.filter { $0.column == column }
                                .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
                        )
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Column View

struct KanbanColumnView: View {
    let columnName: String
    let cards: [KanbanCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(columnName)
                    .font(.headline)
                Spacer()
                Text("\(cards.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 4)

            if cards.isEmpty {
                Text("비어있음")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            } else {
                ForEach(cards) { card in
                    KanbanCardView(card: card)
                }
            }

            Spacer()
        }
        .frame(width: 240)
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
    }
}

// MARK: - Card View

struct KanbanCardView: View {
    let card: KanbanCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(card.priority.icon)
                    .font(.caption)
                Text(card.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }

            if !card.description.isEmpty {
                Text(card.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                ForEach(card.labels, id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(4)
                }
                Spacer()
                if let assignee = card.assignee {
                    Text("@\(assignee)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}
