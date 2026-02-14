import SwiftUI

struct KanbanWorkspaceView: View {
    @State private var boards: [KanbanBoard] = []
    @State private var selectedBoardId: UUID?
    @State private var showCreateBoardSheet = false

    private var selectedBoard: KanbanBoard? {
        guard let selectedBoardId else { return nil }
        return boards.first(where: { $0.id == selectedBoardId })
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("칸반 보드")
                        .font(.headline)
                    Spacer()
                    Button {
                        showCreateBoardSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("보드 추가")
                }
                .padding(12)

                Divider()

                List(selection: $selectedBoardId) {
                    ForEach(boards) { board in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(board.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text("\(board.cards.count)개 카드")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .tag(board.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 220, idealWidth: 260)

            if let board = selectedBoard {
                KanbanBoardEditorView(
                    board: board,
                    onChanged: { refreshBoards() },
                    onDeleteBoard: { deleteBoard(board.id) }
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("칸반 보드를 선택하세요")
                        .font(.system(size: 14, weight: .medium))
                    Text("왼쪽에서 보드를 선택하거나 새로 생성하세요.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showCreateBoardSheet) {
            CreateBoardSheet { name, columns in
                _ = KanbanManager.shared.createBoard(name: name, columns: columns)
                refreshBoards(selectByName: name)
            }
        }
        .onAppear {
            refreshBoards()
        }
    }

    private func refreshBoards(selectByName: String? = nil) {
        let listed = KanbanManager.shared.listBoards()
        boards = listed

        if let selectByName, let board = listed.first(where: { $0.name == selectByName }) {
            selectedBoardId = board.id
            return
        }

        if let selectedBoardId, listed.contains(where: { $0.id == selectedBoardId }) {
            return
        }
        selectedBoardId = listed.first?.id
    }

    private func deleteBoard(_ boardId: UUID) {
        KanbanManager.shared.deleteBoard(id: boardId)
        refreshBoards()
    }
}

private struct KanbanBoardEditorView: View {
    let board: KanbanBoard
    let onChanged: () -> Void
    let onDeleteBoard: () -> Void

    @State private var showCreateCardSheet = false
    @State private var editingCard: KanbanCard?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("\(board.cards.count)개 카드 · 컬럼 \(board.columns.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button("카드 추가") {
                    showCreateCardSheet = true
                }
                .buttonStyle(.borderedProminent)

                Button("보드 삭제", role: .destructive) {
                    onDeleteBoard()
                }
                .buttonStyle(.bordered)
            }
            .padding(12)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(board.columns, id: \.self) { column in
                        columnView(column)
                    }
                }
                .padding(12)
            }
        }
        .sheet(isPresented: $showCreateCardSheet) {
            KanbanCardFormSheet(board: board, card: nil) { draft in
                _ = KanbanManager.shared.addCard(
                    boardId: board.id,
                    title: draft.title,
                    column: draft.column,
                    priority: draft.priority,
                    description: draft.description,
                    labels: draft.labels,
                    assignee: draft.assignee
                )
                onChanged()
            }
        }
        .sheet(item: $editingCard) { card in
            KanbanCardFormSheet(board: board, card: card) { draft in
                _ = KanbanManager.shared.updateCard(
                    boardId: board.id,
                    cardId: card.id,
                    title: draft.title,
                    description: draft.description,
                    priority: draft.priority,
                    labels: draft.labels,
                    assignee: draft.assignee
                )
                if draft.column != card.column {
                    _ = KanbanManager.shared.moveCard(boardId: board.id, cardId: card.id, toColumn: draft.column)
                }
                onChanged()
            }
        }
    }

    private func columnView(_ column: String) -> some View {
        let cards = board.cards
            .filter { $0.column == column }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column)
                    .font(.headline)
                Spacer()
                Text("\(cards.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            if cards.isEmpty {
                Text("비어 있음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(cards) { card in
                    cardRow(card)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 300)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func cardRow(_ card: KanbanCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(card.priority.icon)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)

                    if !card.description.isEmpty {
                        Text(card.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()

                Menu {
                    Menu("컬럼 이동") {
                        ForEach(board.columns, id: \.self) { column in
                            Button(column) {
                                _ = KanbanManager.shared.moveCard(
                                    boardId: board.id,
                                    cardId: card.id,
                                    toColumn: column
                                )
                                onChanged()
                            }
                        }
                    }

                    Button("수정") {
                        editingCard = card
                    }

                    Button("삭제", role: .destructive) {
                        _ = KanbanManager.shared.deleteCard(boardId: board.id, cardId: card.id)
                        onChanged()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 6) {
                if !card.labels.isEmpty {
                    ForEach(card.labels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Spacer()

                if let assignee = card.assignee, !assignee.isEmpty {
                    Text("@\(assignee)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct KanbanCardDraft {
    var title: String
    var description: String
    var column: String
    var priority: KanbanCard.Priority
    var labels: [String]
    var assignee: String?
}

private struct KanbanCardFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    let board: KanbanBoard
    let card: KanbanCard?
    let onSubmit: (KanbanCardDraft) -> Void

    @State private var title: String
    @State private var description: String
    @State private var selectedColumn: String
    @State private var selectedPriority: KanbanCard.Priority
    @State private var labelsText: String
    @State private var assignee: String

    init(board: KanbanBoard, card: KanbanCard?, onSubmit: @escaping (KanbanCardDraft) -> Void) {
        self.board = board
        self.card = card
        self.onSubmit = onSubmit

        _title = State(initialValue: card?.title ?? "")
        _description = State(initialValue: card?.description ?? "")
        _selectedColumn = State(initialValue: card?.column ?? board.columns.first ?? "백로그")
        _selectedPriority = State(initialValue: card?.priority ?? .medium)
        _labelsText = State(initialValue: (card?.labels ?? []).joined(separator: ", "))
        _assignee = State(initialValue: card?.assignee ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(card == nil ? "카드 추가" : "카드 수정")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            Form {
                Section("기본 정보") {
                    TextField("제목", text: $title)
                    Picker("컬럼", selection: $selectedColumn) {
                        ForEach(board.columns, id: \.self) { column in
                            Text(column).tag(column)
                        }
                    }
                    Picker("우선순위", selection: $selectedPriority) {
                        Text("Low").tag(KanbanCard.Priority.low)
                        Text("Medium").tag(KanbanCard.Priority.medium)
                        Text("High").tag(KanbanCard.Priority.high)
                        Text("Urgent").tag(KanbanCard.Priority.urgent)
                    }
                }

                Section("상세") {
                    TextField("설명", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("라벨 (쉼표로 구분)", text: $labelsText)
                    TextField("담당자", text: $assignee)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("취소") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button(card == nil ? "추가" : "저장") {
                            onSubmit(
                                KanbanCardDraft(
                                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                                    column: selectedColumn,
                                    priority: selectedPriority,
                                    labels: parseLabels(labelsText),
                                    assignee: normalizedAssignee
                                )
                            )
                            dismiss()
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 12)
        }
        .frame(width: 420, height: 360)
    }

    private var normalizedAssignee: String? {
        let trimmed = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseLabels(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct CreateBoardSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var columnsRaw = "백로그, 준비, 진행 중, 검토, 완료"

    let onCreate: (String, [String]?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("새 보드")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            Form {
                Section("기본") {
                    TextField("보드 이름", text: $name)
                    TextField("컬럼 (쉼표 구분)", text: $columnsRaw)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("취소") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("생성") {
                            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedName.isEmpty else { return }
                            let columns = parseColumns(columnsRaw)
                            onCreate(trimmedName, columns.isEmpty ? nil : columns)
                            dismiss()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 12)
        }
        .frame(width: 380, height: 240)
    }

    private func parseColumns(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
