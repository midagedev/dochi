import Foundation
import os

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

/// Manages ONNX model loading, caching, and session creation for TTS inference.
final class ONNXModelManager: @unchecked Sendable {
    enum ModelType: String, CaseIterable {
        case duration = "duration"
        case acoustic = "acoustic"
        case vocoder = "vocoder"
    }

    enum ManagerError: Error, LocalizedError {
        case modelNotFound(ModelType)
        case loadFailed(ModelType, String)
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let type):
                "모델 파일을 찾을 수 없습니다: \(type.rawValue)"
            case .loadFailed(let type, let reason):
                "\(type.rawValue) 모델 로드 실패: \(reason)"
            case .downloadFailed(let reason):
                "모델 다운로드 실패: \(reason)"
            }
        }
    }

    // MARK: - Properties

    private let modelsDirectory: URL
    private(set) var isLoaded = false

    #if canImport(OnnxRuntimeBindings)
    private(set) var durationSession: ORTSession?
    private(set) var acousticSession: ORTSession?
    private(set) var vocoderSession: ORTSession?
    #endif

    // MARK: - Init

    init() {
        self.modelsDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Dochi/models")

        try? FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Model Management

    /// Check if all required model files exist locally.
    func areModelsAvailable() -> Bool {
        for type in ModelType.allCases {
            if !FileManager.default.fileExists(atPath: modelPath(for: type).path) {
                return false
            }
        }
        return true
    }

    /// Load all ONNX model sessions.
    func loadModels() throws {
        guard areModelsAvailable() else {
            Log.tts.warning("ONNX models not available yet — skipping load")
            return
        }

        #if canImport(OnnxRuntimeBindings)
        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)

        durationSession = try ORTSession(
            env: env,
            modelPath: modelPath(for: .duration).path,
            sessionOptions: options
        )
        Log.tts.info("Duration model loaded")

        acousticSession = try ORTSession(
            env: env,
            modelPath: modelPath(for: .acoustic).path,
            sessionOptions: options
        )
        Log.tts.info("Acoustic model loaded")

        vocoderSession = try ORTSession(
            env: env,
            modelPath: modelPath(for: .vocoder).path,
            sessionOptions: options
        )
        Log.tts.info("Vocoder model loaded")
        #endif

        isLoaded = true
        Log.tts.info("All ONNX models loaded successfully")
    }

    /// Unload all model sessions to free memory.
    func unloadModels() {
        #if canImport(OnnxRuntimeBindings)
        durationSession = nil
        acousticSession = nil
        vocoderSession = nil
        #endif
        isLoaded = false
        Log.tts.info("ONNX models unloaded")
    }

    // MARK: - Paths

    func modelPath(for type: ModelType) -> URL {
        modelsDirectory.appendingPathComponent("\(type.rawValue).onnx")
    }

    var modelsDirectoryPath: URL { modelsDirectory }
}
