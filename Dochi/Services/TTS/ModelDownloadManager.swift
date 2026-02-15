import Foundation
import os

/// Describes a Piper ONNX TTS model available for download.
struct PiperModelInfo: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let language: String
    let gender: String
    let quality: PiperModelQuality
    let sizeBytes: Int64
    let downloadURL: String

    /// File names expected inside the model directory after download.
    var expectedFiles: [String] {
        ["\(id).onnx", "\(id).onnx.json"]
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum PiperModelQuality: String, Codable, Sendable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: "저품질"
        case .medium: "중간"
        case .high: "고품질"
        }
    }

    var icon: String {
        switch self {
        case .low: "speaker.wave.1"
        case .medium: "speaker.wave.2"
        case .high: "speaker.wave.3"
        }
    }
}

enum CatalogState: Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

enum ModelInstallState: Sendable {
    case notInstalled
    case downloading(progress: Double)
    case installed
}

/// Manages Piper ONNX model catalog, download, and local storage.
@MainActor
@Observable
final class ModelDownloadManager {
    // MARK: - Published State

    private(set) var availableModels: [PiperModelInfo] = []
    private(set) var installedModelIds: Set<String> = []
    private(set) var catalogState: CatalogState = .idle
    private(set) var downloadProgress: [String: Double] = [:]

    // MARK: - Private

    private let modelsDirectory: URL
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]

    // MARK: - Init

    init() {
        self.modelsDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi/models")

        try? FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )

        scanInstalledModels()
    }

    /// Test-only initializer with custom directory.
    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory

        try? FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )

        scanInstalledModels()
    }

    // MARK: - Catalog

    /// Load the model catalog. Uses hardcoded Piper Korean model info.
    func loadCatalog() async {
        catalogState = .loading
        Log.tts.info("Loading ONNX model catalog...")

        // Hardcoded Piper Korean models (based on rhasspy/piper voices)
        availableModels = Self.hardcodedKoreanModels

        catalogState = .loaded
        Log.tts.info("ONNX model catalog loaded: \(self.availableModels.count) models")
    }

    // MARK: - Download

    /// Download a model by its ID.
    func downloadModel(_ modelId: String) async {
        guard let model = availableModels.first(where: { $0.id == modelId }) else {
            Log.tts.error("Model not found in catalog: \(modelId)")
            return
        }

        guard activeDownloads[modelId] == nil else {
            Log.tts.warning("Download already in progress for: \(modelId)")
            return
        }

        guard let url = URL(string: model.downloadURL) else {
            Log.tts.error("Invalid download URL for model: \(modelId)")
            return
        }

        let modelDir = modelsDirectory.appendingPathComponent(modelId)
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        downloadProgress[modelId] = 0.0
        Log.tts.info("Starting download for model: \(modelId)")

        do {
            let (tempURL, _) = try await downloadWithProgress(url: url, modelId: modelId)

            // Move downloaded file to model directory
            let onnxPath = modelDir.appendingPathComponent("\(modelId).onnx")
            if FileManager.default.fileExists(atPath: onnxPath.path) {
                try FileManager.default.removeItem(at: onnxPath)
            }
            try FileManager.default.moveItem(at: tempURL, to: onnxPath)

            // Create a minimal config JSON (placeholder for actual Piper config)
            let configPath = modelDir.appendingPathComponent("\(modelId).onnx.json")
            let configData = try JSONSerialization.data(withJSONObject: [
                "model_id": modelId,
                "language": model.language,
                "sample_rate": 22050,
                "num_speakers": 1,
            ])
            try configData.write(to: configPath)

            installedModelIds.insert(modelId)
            downloadProgress.removeValue(forKey: modelId)
            activeDownloads.removeValue(forKey: modelId)
            Log.tts.info("Model downloaded and installed: \(modelId)")
        } catch {
            downloadProgress.removeValue(forKey: modelId)
            activeDownloads.removeValue(forKey: modelId)
            if (error as NSError).code == NSURLErrorCancelled {
                Log.tts.info("Download cancelled for model: \(modelId)")
            } else {
                Log.tts.error("Download failed for model \(modelId): \(error.localizedDescription)")
            }
        }
    }

    /// Cancel an in-progress download.
    func cancelDownload(_ modelId: String) {
        activeDownloads[modelId]?.cancel()
        activeDownloads.removeValue(forKey: modelId)
        downloadProgress.removeValue(forKey: modelId)
        Log.tts.info("Download cancelled for model: \(modelId)")
    }

    // MARK: - Delete

    /// Delete an installed model.
    func deleteModel(_ modelId: String) {
        let modelDir = modelsDirectory.appendingPathComponent(modelId)
        do {
            try FileManager.default.removeItem(at: modelDir)
            installedModelIds.remove(modelId)
            Log.tts.info("Model deleted: \(modelId)")
        } catch {
            Log.tts.error("Failed to delete model \(modelId): \(error.localizedDescription)")
        }
    }

    // MARK: - Query

    /// Get the install state for a given model.
    func installState(for modelId: String) -> ModelInstallState {
        if let progress = downloadProgress[modelId] {
            return .downloading(progress: progress)
        }
        if installedModelIds.contains(modelId) {
            return .installed
        }
        return .notInstalled
    }

    /// Returns the directory path for a given model.
    func modelDirectory(for modelId: String) -> URL {
        modelsDirectory.appendingPathComponent(modelId)
    }

    /// Total disk space used by installed models.
    var totalInstalledSize: Int64 {
        var total: Int64 = 0
        for modelId in installedModelIds {
            let dir = modelsDirectory.appendingPathComponent(modelId)
            if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        total += Int64(size)
                    }
                }
            }
        }
        return total
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalInstalledSize, countStyle: .file)
    }

    // MARK: - Private

    private func scanInstalledModels() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for dir in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let modelId = dir.lastPathComponent
            let onnxFile = dir.appendingPathComponent("\(modelId).onnx")
            if fm.fileExists(atPath: onnxFile.path) {
                installedModelIds.insert(modelId)
            }
        }

        Log.tts.info("Scanned installed ONNX models: \(self.installedModelIds.count) found")
    }

    private func downloadWithProgress(url: URL, modelId: String) async throws -> (URL, URLResponse) {
        let delegate = DownloadProgressDelegate { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress[modelId] = progress
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)

        activeDownloads[modelId] = task

        return try await withCheckedThrowingContinuation { continuation in
            delegate.completion = { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        }
    }

    // MARK: - Hardcoded Catalog

    static let hardcodedKoreanModels: [PiperModelInfo] = [
        PiperModelInfo(
            id: "ko_KR-kss-low",
            name: "KSS (저품질)",
            language: "ko-KR",
            gender: "여성",
            quality: .low,
            sizeBytes: 15_000_000,
            downloadURL: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ko/ko_KR/kss/low/ko_KR-kss-low.onnx"
        ),
        PiperModelInfo(
            id: "ko_KR-kss-medium",
            name: "KSS (중간)",
            language: "ko-KR",
            gender: "여성",
            quality: .medium,
            sizeBytes: 63_000_000,
            downloadURL: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ko/ko_KR/kss/medium/ko_KR-kss-medium.onnx"
        ),
        PiperModelInfo(
            id: "ko_KR-kss-high",
            name: "KSS (고품질)",
            language: "ko-KR",
            gender: "여성",
            quality: .high,
            sizeBytes: 105_000_000,
            downloadURL: "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ko/ko_KR/kss/high/ko_KR-kss-high.onnx"
        ),
    ]
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void
    var completion: ((Result<(URL, URLResponse), Error>) -> Void)?

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Copy to temp location before the session cleans up
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".onnx")
        do {
            try FileManager.default.copyItem(at: location, to: tempURL)
            completion?(.success((tempURL, downloadTask.response!)))
        } catch {
            completion?(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completion?(.failure(error))
        }
    }
}
