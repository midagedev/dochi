import SwiftUI

struct ONNXModelManagerView: View {
    var settings: AppSettings
    var downloadManager: ModelDownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch downloadManager.catalogState {
            case .idle:
                emptyState
            case .loading:
                loadingState
            case .loaded:
                catalogContent
            case .error(let message):
                errorState(message: message)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("ONNX 모델이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("모델을 다운로드하여 오프라인 음성 합성을 사용하세요.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                Task {
                    await downloadManager.loadCatalog()
                }
            } label: {
                Label("한국어 모델 탐색", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Loading

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("모델 카탈로그 로딩 중...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Error

    private func errorState(message: String) -> some View {
        VStack(spacing: 8) {
            Label("카탈로그 로드 실패", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("다시 시도") {
                Task {
                    await downloadManager.loadCatalog()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Catalog Content

    private var catalogContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Installed model picker
            if !downloadManager.installedModelIds.isEmpty {
                installedModelPicker
            }

            // Model cards
            ForEach(downloadManager.availableModels) { model in
                modelCard(for: model)
            }

            // Total size footer
            if !downloadManager.installedModelIds.isEmpty {
                HStack {
                    Text("설치된 모델 용량: \(downloadManager.formattedTotalSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Installed Model Picker

    private var installedModelPicker: some View {
        Picker("사용할 모델", selection: Binding(
            get: { settings.onnxModelId },
            set: { settings.onnxModelId = $0 }
        )) {
            Text("선택 안 함").tag("")
            ForEach(downloadManager.availableModels.filter {
                downloadManager.installedModelIds.contains($0.id)
            }) { model in
                Text(model.name).tag(model.id)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Model Card

    private func modelCard(for model: PiperModelInfo) -> some View {
        let state = downloadManager.installState(for: model.id)

        return HStack(spacing: 10) {
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 12, weight: .medium))

                    if case .installed = state {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 6) {
                    Label(model.language, systemImage: "globe")
                    Label(model.gender, systemImage: "person")
                    Label(model.quality.displayName, systemImage: model.quality.icon)
                    Text(model.formattedSize)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Action
            switch state {
            case .notInstalled:
                Button {
                    Task {
                        await downloadManager.downloadModel(model.id)
                    }
                } label: {
                    Label("다운로드", systemImage: "arrow.down.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .downloading(let progress):
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .frame(width: 60)

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)

                    Button {
                        downloadManager.cancelDownload(model.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("다운로드 취소")
                }

            case .installed:
                Button(role: .destructive) {
                    downloadManager.deleteModel(model.id)
                    // If the deleted model was selected, clear selection
                    if settings.onnxModelId == model.id {
                        settings.onnxModelId = ""
                    }
                } label: {
                    Label("삭제", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
