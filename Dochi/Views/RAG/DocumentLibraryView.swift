import SwiftUI
import UniformTypeIdentifiers

/// 문서 라이브러리 시트: 파일 추가, 폴더 선택, 인덱싱 관리
struct DocumentLibraryView: View {
    let documentIndexer: DocumentIndexer

    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var showFolderImporter = false
    @State private var documents: [RAGDocument] = []
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var filteredDocuments: [RAGDocument] {
        if searchText.isEmpty {
            return documents
        }
        return documents.filter { $0.fileName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("문서 라이브러리")
                    .font(.headline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Toolbar
            HStack(spacing: 8) {
                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("검색...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                // Add buttons
                Menu {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("파일 추가", systemImage: "doc.badge.plus")
                    }

                    Button {
                        showFolderImporter = true
                    } label: {
                        Label("폴더 추가", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Document list
            if filteredDocuments.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)

                    if documents.isEmpty {
                        Text("문서가 없습니다")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("파일이나 폴더를 추가하여 RAG 검색을 시작하세요")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("일치하는 문서가 없습니다")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredDocuments) { doc in
                            DocumentRow(document: doc) {
                                documentIndexer.removeDocument(id: doc.id)
                                refreshDocuments()
                            } onReindex: {
                                Task {
                                    try? await documentIndexer.indexFile(at: URL(fileURLWithPath: doc.filePath))
                                    refreshDocuments()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Indexing state & footer
            HStack {
                if case .indexing(let progress, let fileName) = documentIndexer.indexingState {
                    ProgressView(value: progress)
                        .frame(width: 100)
                    Text("\(fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(documents.count)건의 문서")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            refreshDocuments()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [
                UTType.pdf,
                UTType.plainText,
                UTType(filenameExtension: "md") ?? .plainText
            ],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
    }

    private func refreshDocuments() {
        documents = documentIndexer.documents
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            errorMessage = nil
            Task {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        try await documentIndexer.indexFile(at: url)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                refreshDocuments()
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folderURL = urls.first else { return }
            errorMessage = nil
            guard folderURL.startAccessingSecurityScopedResource() else { return }
            Task {
                defer { folderURL.stopAccessingSecurityScopedResource() }
                await documentIndexer.indexFolder(at: folderURL)
                refreshDocuments()
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - DocumentRow

private struct DocumentRow: View {
    let document: RAGDocument
    let onDelete: () -> Void
    let onReindex: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // File type icon
            Image(systemName: fileIcon)
                .font(.system(size: 16))
                .foregroundStyle(fileColor)
                .frame(width: 24)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(document.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(document.fileSizeDisplay)
                    Text("\(document.chunkCount)청크")

                    if let date = document.lastIndexedAt {
                        Text(date, style: .relative)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Status
            HStack(spacing: 4) {
                Image(systemName: document.indexingStatus.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                Text(document.indexingStatus.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Actions (visible on hover)
            if isHovering {
                HStack(spacing: 4) {
                    Button {
                        onReindex()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("재인덱싱")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("삭제")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.secondary.opacity(0.06) : Color.clear)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var fileIcon: String {
        switch document.fileType {
        case .pdf: return "doc.richtext"
        case .markdown: return "doc.text"
        case .text: return "doc.plaintext"
        }
    }

    private var fileColor: Color {
        switch document.fileType {
        case .pdf: return .red
        case .markdown: return .blue
        case .text: return .gray
        }
    }

    private var statusColor: Color {
        switch document.indexingStatus {
        case .indexed: return .green
        case .indexing: return .blue
        case .pending: return .orange
        case .failed: return .red
        case .outdated: return .yellow
        }
    }
}
