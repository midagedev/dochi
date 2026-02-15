import XCTest
@testable import Dochi

final class ONNXTTSTests: XCTestCase {

    // MARK: - TTSProvider Tests

    func testTTSProviderOnnxLocalCase() {
        let provider = TTSProvider.onnxLocal
        XCTAssertEqual(provider.displayName, "로컬 TTS (ONNX)")
        XCTAssertFalse(provider.requiresAPIKey)
        XCTAssertEqual(provider.keychainAccount, "")
        XCTAssertTrue(provider.isLocal)
    }

    func testTTSProviderSystemIsLocal() {
        XCTAssertTrue(TTSProvider.system.isLocal)
    }

    func testTTSProviderGoogleCloudIsNotLocal() {
        XCTAssertFalse(TTSProvider.googleCloud.isLocal)
    }

    func testTTSProviderShortDescription() {
        for provider in TTSProvider.allCases {
            XCTAssertFalse(provider.shortDescription.isEmpty, "Provider \(provider) should have a short description")
        }
    }

    func testTTSProviderAllCasesIncludesOnnxLocal() {
        XCTAssertTrue(TTSProvider.allCases.contains(.onnxLocal))
        XCTAssertEqual(TTSProvider.allCases.count, 3)
    }

    func testTTSProviderRawValueRoundTrip() {
        let provider = TTSProvider.onnxLocal
        let restored = TTSProvider(rawValue: provider.rawValue)
        XCTAssertEqual(restored, provider)
    }

    // MARK: - AppSettings Tests

    @MainActor
    func testAppSettingsOnnxModelIdDefault() {
        // Clean up to ensure default
        UserDefaults.standard.removeObject(forKey: "onnxModelId")
        let freshSettings = AppSettings()
        XCTAssertEqual(freshSettings.onnxModelId, "")
    }

    @MainActor
    func testAppSettingsTTSOfflineFallbackDefault() {
        UserDefaults.standard.removeObject(forKey: "ttsOfflineFallbackEnabled")
        let settings = AppSettings()
        XCTAssertFalse(settings.ttsOfflineFallbackEnabled)
    }

    @MainActor
    func testAppSettingsOnnxModelIdPersistence() {
        let settings = AppSettings()
        settings.onnxModelId = "ko_KR-kss-medium"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "onnxModelId"), "ko_KR-kss-medium")
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "onnxModelId")
    }

    @MainActor
    func testAppSettingsTTSOfflineFallbackPersistence() {
        let settings = AppSettings()
        settings.ttsOfflineFallbackEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "ttsOfflineFallbackEnabled"))
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "ttsOfflineFallbackEnabled")
    }

    @MainActor
    func testAppSettingsCurrentTTSProviderOnnx() {
        let settings = AppSettings()
        settings.ttsProvider = TTSProvider.onnxLocal.rawValue
        XCTAssertEqual(settings.currentTTSProvider, .onnxLocal)
        // Cleanup
        settings.ttsProvider = TTSProvider.system.rawValue
    }

    // MARK: - PiperModelInfo Tests

    func testPiperModelInfoFormattedSize() {
        let model = PiperModelInfo(
            id: "test-model",
            name: "Test",
            language: "ko-KR",
            gender: "여성",
            quality: .medium,
            sizeBytes: 63_000_000,
            downloadURL: "https://example.com/model.onnx"
        )
        XCTAssertFalse(model.formattedSize.isEmpty)
    }

    func testPiperModelInfoExpectedFiles() {
        let model = PiperModelInfo(
            id: "ko_KR-kss-low",
            name: "KSS",
            language: "ko-KR",
            gender: "여성",
            quality: .low,
            sizeBytes: 15_000_000,
            downloadURL: "https://example.com/model.onnx"
        )
        XCTAssertEqual(model.expectedFiles, ["ko_KR-kss-low.onnx", "ko_KR-kss-low.onnx.json"])
    }

    func testPiperModelQualityDisplayName() {
        XCTAssertEqual(PiperModelQuality.low.displayName, "저품질")
        XCTAssertEqual(PiperModelQuality.medium.displayName, "중간")
        XCTAssertEqual(PiperModelQuality.high.displayName, "고품질")
    }

    // MARK: - ModelDownloadManager Tests

    @MainActor
    func testModelDownloadManagerCatalogLoading() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onnx_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ModelDownloadManager(modelsDirectory: tempDir)

        // Initially idle
        if case .idle = manager.catalogState {} else {
            XCTFail("Expected idle state")
        }

        await manager.loadCatalog()

        // After loading, should have models
        if case .loaded = manager.catalogState {} else {
            XCTFail("Expected loaded state")
        }
        XCTAssertFalse(manager.availableModels.isEmpty)
        XCTAssertEqual(manager.availableModels.count, ModelDownloadManager.hardcodedKoreanModels.count)
    }

    @MainActor
    func testModelDownloadManagerInitialState() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onnx_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ModelDownloadManager(modelsDirectory: tempDir)
        XCTAssertTrue(manager.installedModelIds.isEmpty)
        XCTAssertTrue(manager.downloadProgress.isEmpty)
    }

    @MainActor
    func testModelDownloadManagerInstallState() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onnx_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ModelDownloadManager(modelsDirectory: tempDir)

        let state = manager.installState(for: "nonexistent")
        if case .notInstalled = state {} else {
            XCTFail("Expected notInstalled state")
        }
    }

    @MainActor
    func testModelDownloadManagerScanFindsInstalledModels() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onnx_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a fake installed model
        let modelDir = tempDir.appendingPathComponent("test-model")
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let onnxFile = modelDir.appendingPathComponent("test-model.onnx")
        FileManager.default.createFile(atPath: onnxFile.path, contents: Data([0x00]))

        let manager = ModelDownloadManager(modelsDirectory: tempDir)
        XCTAssertTrue(manager.installedModelIds.contains("test-model"))
    }

    @MainActor
    func testModelDownloadManagerDeleteModel() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onnx_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a fake installed model
        let modelDir = tempDir.appendingPathComponent("test-model")
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let onnxFile = modelDir.appendingPathComponent("test-model.onnx")
        FileManager.default.createFile(atPath: onnxFile.path, contents: Data([0x00]))

        let manager = ModelDownloadManager(modelsDirectory: tempDir)
        XCTAssertTrue(manager.installedModelIds.contains("test-model"))

        manager.deleteModel("test-model")
        XCTAssertFalse(manager.installedModelIds.contains("test-model"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path))
    }

    @MainActor
    func testModelDownloadManagerTotalInstalledSize() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onnx_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a fake installed model with known size
        let modelDir = tempDir.appendingPathComponent("test-model")
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let onnxFile = modelDir.appendingPathComponent("test-model.onnx")
        let testData = Data(repeating: 0x42, count: 1024)
        FileManager.default.createFile(atPath: onnxFile.path, contents: testData)

        let manager = ModelDownloadManager(modelsDirectory: tempDir)
        XCTAssertGreaterThan(manager.totalInstalledSize, 0)
        XCTAssertFalse(manager.formattedTotalSize.isEmpty)
    }

    // MARK: - TTSRouter Tests

    @MainActor
    func testTTSRouterActiveServiceSelection() async throws {
        let settings = AppSettings()
        let keychain = MockKeychainService()
        let router = TTSRouter(settings: settings, keychainService: keychain)

        // Default should be system
        settings.ttsProvider = TTSProvider.system.rawValue
        // The router's engineState reflects the active service
        // Just verify it doesn't crash
        _ = router.engineState
        _ = router.isSpeaking

        // Switch to onnxLocal
        settings.ttsProvider = TTSProvider.onnxLocal.rawValue
        _ = router.engineState

        // Cleanup
        settings.ttsProvider = TTSProvider.system.rawValue
    }

    @MainActor
    func testTTSRouterStopAndClear() {
        let settings = AppSettings()
        let keychain = MockKeychainService()
        let router = TTSRouter(settings: settings, keychainService: keychain)

        // Should not crash when stopping all services
        router.stopAndClear()
    }

    @MainActor
    func testTTSRouterUnloadEngine() {
        let settings = AppSettings()
        let keychain = MockKeychainService()
        let router = TTSRouter(settings: settings, keychainService: keychain)

        // Should not crash when unloading all services
        router.unloadEngine()
    }

    @MainActor
    func testTTSRouterFallbackStateInitial() {
        let settings = AppSettings()
        let keychain = MockKeychainService()
        let router = TTSRouter(settings: settings, keychainService: keychain)

        XCTAssertFalse(router.isFallbackActive)
        XCTAssertNil(router.fallbackProviderName)
    }

    @MainActor
    func testTTSRouterRestoreTTSProviderNoOp() {
        let settings = AppSettings()
        let keychain = MockKeychainService()
        let router = TTSRouter(settings: settings, keychainService: keychain)

        // Should be a no-op when no fallback is active
        router.restoreTTSProvider()
        XCTAssertFalse(router.isFallbackActive)
    }

    // MARK: - SupertonicService Tests

    @MainActor
    func testSupertonicServicePreprocessText() {
        let service = SupertonicService()

        // Test emoji removal
        let cleaned = service.preprocessText("안녕하세요 😊 반갑습니다")
        XCTAssertFalse(cleaned.contains("😊"))
        XCTAssertTrue(cleaned.contains("안녕하세요"))

        // Test quote normalization
        let quotes = service.preprocessText("\u{201C}Hello\u{201D}")
        XCTAssertTrue(quotes.contains("\""))

        // Test whitespace trimming
        let trimmed = service.preprocessText("  테스트  ")
        XCTAssertEqual(trimmed, "테스트")

        // Test empty input
        let empty = service.preprocessText("   ")
        XCTAssertEqual(empty, "")
    }

    @MainActor
    func testSupertonicServiceInitialState() {
        let service = SupertonicService()
        XCTAssertFalse(service.isSpeaking)
        XCTAssertNil(service.loadedModelId)
        if case .unloaded = service.engineState {} else {
            XCTFail("Expected unloaded state")
        }
    }

    @MainActor
    func testSupertonicServiceAreModelsAvailableNoModels() {
        let service = SupertonicService()
        // With a non-existent model ID, should return false
        XCTAssertFalse(service.areModelsAvailable(modelId: "nonexistent-model-id"))
    }

    @MainActor
    func testSupertonicServiceLoadModelMissing() async {
        let service = SupertonicService()
        do {
            try await service.loadModel(modelId: "nonexistent-model-xyz")
            XCTFail("Expected error for missing model")
        } catch {
            // Expected — model not found
            XCTAssertTrue(error is SupertonicError)
        }
    }

    @MainActor
    func testSupertonicServiceLoadModelEmptyId() async throws {
        let service = SupertonicService()
        // Should return early without error for empty ID
        try await service.loadModel(modelId: "")
        XCTAssertNil(service.loadedModelId)
    }

    // MARK: - Hardcoded Catalog Tests

    @MainActor
    func testHardcodedKoreanModels() {
        let models = ModelDownloadManager.hardcodedKoreanModels
        XCTAssertEqual(models.count, 3)

        // All models should be Korean
        for model in models {
            XCTAssertEqual(model.language, "ko-KR")
        }

        // Should have low, medium, high quality
        let qualities = Set(models.map { $0.quality })
        XCTAssertTrue(qualities.contains(.low))
        XCTAssertTrue(qualities.contains(.medium))
        XCTAssertTrue(qualities.contains(.high))

        // All should have non-empty download URLs
        for model in models {
            XCTAssertFalse(model.downloadURL.isEmpty)
            XCTAssertNotNil(URL(string: model.downloadURL))
        }
    }

    // MARK: - SupertonicError Tests

    func testSupertonicErrorDescriptions() {
        let notFound = SupertonicError.modelNotFound("test-model")
        XCTAssertNotNil(notFound.errorDescription)
        XCTAssertTrue(notFound.errorDescription!.contains("test-model"))

        let inference = SupertonicError.inferenceError("timeout")
        XCTAssertNotNil(inference.errorDescription)
        XCTAssertTrue(inference.errorDescription!.contains("timeout"))
    }
}
