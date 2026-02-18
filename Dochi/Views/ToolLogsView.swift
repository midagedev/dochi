import SwiftUI
import AppKit

struct ToolLogsView: View {
    let conversations: [Conversation]
    let selectedConversationID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var resultFilter: ToolLogResultFilter = .all
    @State private var scopeFilter: ToolLogScopeFilter

    init(conversations: [Conversation], selectedConversationID: UUID?) {
        self.conversations = conversations
        self.selectedConversationID = selectedConversationID
        _scopeFilter = State(initialValue: selectedConversationID == nil ? .all : .current)
    }

    enum ToolLogScopeFilter: String, CaseIterable, Identifiable {
        case current = "현재 대화"
        case all = "전체 대화"

        var id: String { rawValue }
    }

    enum ToolLogResultFilter: String, CaseIterable, Identifiable {
        case all = "전체"
        case success = "성공"
        case error = "실패"

        var id: String { rawValue }
    }

    private var currentConversation: Conversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    private var sourceConversations: [Conversation] {
        switch scopeFilter {
        case .current:
            if let currentConversation {
                return [currentConversation]
            }
            return []
        case .all:
            return conversations
        }
    }

    private var entries: [ToolLogEntry] {
        Self.buildEntries(from: sourceConversations)
    }

    private var filteredEntries: [ToolLogEntry] {
        entries.filter { entry in
            switch resultFilter {
            case .all:
                break
            case .success:
                guard !entry.isError else { return false }
            case .error:
                guard entry.isError else { return false }
            }

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            let q = trimmed.lowercased()
            return entry.toolName.lowercased().contains(q)
                || entry.toolCallId.lowercased().contains(q)
                || entry.argumentsJSON.lowercased().contains(q)
                || entry.result.lowercased().contains(q)
                || entry.conversationTitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("툴 호출 상세 로그")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("닫기") {
                dismiss()
            }
        }
        .padding(12)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField("도구명/호출ID/인자/결과 검색", text: $query)
                .textFieldStyle(.roundedBorder)

            Picker("범위", selection: $scopeFilter) {
                ForEach(ToolLogScopeFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)

            Picker("결과", selection: $resultFilter) {
                ForEach(ToolLogResultFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if filteredEntries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                Text(entries.isEmpty ? "기록된 툴 호출이 없습니다." : "조건에 맞는 로그가 없습니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filteredEntries) { entry in
                ToolLogRowView(entry: entry, showConversationContext: scopeFilter == .all)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
            }
            .listStyle(.plain)
        }
    }

    private var headerSubtitle: String {
        switch scopeFilter {
        case .current:
            if let currentConversation {
                return "\(currentConversation.title) · \(filteredEntries.count)건"
            }
            return "현재 대화가 없습니다."
        case .all:
            return "전체 대화 \(conversations.count)개 · \(filteredEntries.count)건"
        }
    }

    private struct PendingToolCall {
        let timestamp: Date
        let toolName: String
        let argumentsJSON: String
    }

    private static func buildEntries(from conversations: [Conversation]) -> [ToolLogEntry] {
        var entries: [ToolLogEntry] = []

        for conversation in conversations {
            var pending: [String: PendingToolCall] = [:]

            for message in conversation.messages {
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    for call in toolCalls {
                        pending[call.id] = PendingToolCall(
                            timestamp: message.timestamp,
                            toolName: call.name,
                            argumentsJSON: call.argumentsJSON
                        )
                    }
                }

                guard message.role == .tool else { continue }

                let callId = message.toolCallId ?? ""
                let pendingCall = pending.removeValue(forKey: callId)
                let toolName = pendingCall?.toolName ?? "unknown"
                let argumentsJSON = pendingCall?.argumentsJSON ?? "{}"
                let result = message.content

                let lower = result.lowercased()
                let isError = result.hasPrefix("오류:")
                    || lower.contains("error")
                    || lower.contains("실패")

                entries.append(
                    ToolLogEntry(
                        id: "\(conversation.id.uuidString)-\(callId)-\(message.id.uuidString)",
                        conversationId: conversation.id,
                        conversationTitle: conversation.title,
                        timestamp: message.timestamp,
                        toolCallId: callId,
                        toolName: toolName,
                        argumentsJSON: argumentsJSON,
                        result: result,
                        isError: isError
                    )
                )
            }

            for (callId, pendingCall) in pending {
                entries.append(
                    ToolLogEntry(
                        id: "\(conversation.id.uuidString)-\(callId)-pending",
                        conversationId: conversation.id,
                        conversationTitle: conversation.title,
                        timestamp: pendingCall.timestamp,
                        toolCallId: callId,
                        toolName: pendingCall.toolName,
                        argumentsJSON: pendingCall.argumentsJSON,
                        result: "(도구 실행 결과를 찾지 못했습니다.)",
                        isError: false
                    )
                )
            }
        }

        return entries.sorted { $0.timestamp > $1.timestamp }
    }
}

private struct ToolLogEntry: Identifiable {
    let id: String
    let conversationId: UUID
    let conversationTitle: String
    let timestamp: Date
    let toolCallId: String
    let toolName: String
    let argumentsJSON: String
    let result: String
    let isError: Bool
}

private struct ToolLogRowView: View {
    let entry: ToolLogEntry
    let showConversationContext: Bool
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if showConversationContext {
                        detailSection(title: "대화", text: "\(entry.conversationTitle)\n\(entry.conversationId.uuidString)")
                    }
                    detailSection(title: "입력 인자", text: entry.argumentsJSON)
                    detailSection(title: "결과", text: entry.result)
                }
                .transition(.opacity)
            }
        }
        .padding(10)
        .background(entry.isError ? Color.red.opacity(0.05) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(entry.isError ? Color.red.opacity(0.2) : Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(entry.isError ? .red : .green)
                .font(.system(size: 12))

            Text(entry.toolName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            if showConversationContext {
                Text(entry.conversationTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(shortCallId(entry.toolCallId))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(timestampText(entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }

            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.background.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func shortCallId(_ callId: String) -> String {
        guard callId.count > 18 else { return callId }
        return String(callId.prefix(18)) + "..."
    }

    private func timestampText(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
