import SwiftUI

/// UX-8: 대화 상단 접을 수 있는 시스템 프롬프트 배너
struct SystemPromptBannerView: View {
    let contextService: ContextServiceProtocol
    @State private var text: String = ""
    @State private var isExpanded: Bool = UserDefaults.standard.bool(forKey: "systemPromptBannerExpanded")
    @State private var isDirty: Bool = false
    @State private var showSavedFeedback: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if text.isEmpty && !isExpanded {
                emptyBanner
            } else if isExpanded {
                expandedBanner
            } else {
                collapsedBanner
            }
        }
        .onAppear {
            text = contextService.loadBaseSystemPrompt() ?? ""
        }
    }

    // MARK: - Empty State

    private var emptyBanner: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
                persistExpanded(true)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("시스템 프롬프트가 설정되지 않았습니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("작성하기")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.secondary.opacity(0.04))
    }

    // MARK: - Collapsed State

    private var collapsedBanner: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
                persistExpanded(true)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("시스템 프롬프트:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(text.prefix(60).replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.secondary.opacity(0.04))
    }

    // MARK: - Expanded State

    private var expandedBanner: some View {
        VStack(spacing: 4) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("시스템 프롬프트")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if showSavedFeedback {
                    Text("저장됨")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                Text("\(text.count)자")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = false
                        persistExpanded(false)
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            // Editor
            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .frame(minHeight: 80, maxHeight: 200)
                .padding(.horizontal, 12)
                .onChange(of: text) { _, _ in
                    isDirty = true
                }

            // Save button
            if isDirty {
                HStack {
                    Spacer()
                    Button("저장") {
                        contextService.saveBaseSystemPrompt(text)
                        isDirty = false
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSavedFeedback = true
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSavedFeedback = false
                            }
                        }
                        Log.storage.info("System prompt saved from banner")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 12)
            }

            Spacer()
                .frame(height: 4)
        }
        .background(.secondary.opacity(0.04))
    }

    // MARK: - Helpers

    private func persistExpanded(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "systemPromptBannerExpanded")
    }
}
