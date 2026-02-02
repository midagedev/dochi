import SwiftUI
import UniformTypeIdentifiers

struct ContextView: View {
    @EnvironmentObject var viewModel: DochiViewModel

    var body: some View {
        ForEach(viewModel.settings.contextFiles, id: \.absoluteString) { file in
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(file.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    removeFile(file)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }

        Button {
            addFile()
        } label: {
            Label("파일 추가", systemImage: "plus")
        }
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .json, .yaml, .xml, .html, .sourceCode]

        if panel.runModal() == .OK {
            for url in panel.urls {
                if !viewModel.settings.contextFiles.contains(url) {
                    viewModel.settings.contextFiles.append(url)
                }
            }
        }
    }

    private func removeFile(_ url: URL) {
        viewModel.settings.contextFiles.removeAll { $0 == url }
    }
}
