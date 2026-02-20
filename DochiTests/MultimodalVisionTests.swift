import XCTest
@testable import Dochi

final class MultimodalVisionTests: XCTestCase {

    // MARK: - ImageContent Encoding / Decoding

    func testImageContentCodable() throws {
        let content = ImageContent(
            base64Data: "iVBORw0KGgoAAAANSUhEUg==",
            mimeType: "image/png",
            width: 100,
            height: 50
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        let decoded = try JSONDecoder().decode(ImageContent.self, from: data)

        XCTAssertEqual(decoded.base64Data, content.base64Data)
        XCTAssertEqual(decoded.mimeType, content.mimeType)
        XCTAssertEqual(decoded.width, 100)
        XCTAssertEqual(decoded.height, 50)
    }

    func testImageContentEquatable() {
        let a = ImageContent(base64Data: "abc", mimeType: "image/jpeg", width: 200, height: 150)
        let b = ImageContent(base64Data: "abc", mimeType: "image/jpeg", width: 200, height: 150)
        let c = ImageContent(base64Data: "def", mimeType: "image/jpeg", width: 200, height: 150)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Message with imageData

    func testMessageWithImageDataInit() {
        let images = [ImageContent(base64Data: "test", mimeType: "image/jpeg", width: 100, height: 100)]
        let msg = Message(role: .user, content: "이미지 분석", imageData: images)

        XCTAssertEqual(msg.imageData?.count, 1)
        XCTAssertEqual(msg.imageData?[0].mimeType, "image/jpeg")
        XCTAssertEqual(msg.content, "이미지 분석")
    }

    func testMessageWithoutImageDataInit() {
        let msg = Message(role: .user, content: "텍스트만")

        XCTAssertNil(msg.imageData)
    }

    func testMessageImageDataCodableRoundTrip() throws {
        let images = [
            ImageContent(base64Data: "base64data1", mimeType: "image/png", width: 200, height: 150),
            ImageContent(base64Data: "base64data2", mimeType: "image/jpeg", width: 300, height: 200),
        ]
        let original = Message(role: .user, content: "두 이미지 비교", imageData: images)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        XCTAssertEqual(decoded.imageData?.count, 2)
        XCTAssertEqual(decoded.imageData?[0].base64Data, "base64data1")
        XCTAssertEqual(decoded.imageData?[0].mimeType, "image/png")
        XCTAssertEqual(decoded.imageData?[1].base64Data, "base64data2")
        XCTAssertEqual(decoded.imageData?[1].mimeType, "image/jpeg")
        XCTAssertEqual(decoded.content, "두 이미지 비교")
    }

    /// Backward compatibility: messages without imageData should decode fine.
    func testMessageWithoutImageDataBackwardCompat() throws {
        // Simulate legacy JSON without imageData field
        let legacyJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "role": "user",
            "content": "안녕하세요",
            "timestamp": "2025-01-01T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let msg = try decoder.decode(Message.self, from: legacyJSON.data(using: .utf8)!)

        XCTAssertEqual(msg.content, "안녕하세요")
        XCTAssertNil(msg.imageData)
    }

    // MARK: - LLMProvider.supportsVision

    func testOpenAIVisionSupport() {
        let provider = LLMProvider.openai
        XCTAssertTrue(provider.supportsVision(model: "gpt-4o"))
        XCTAssertTrue(provider.supportsVision(model: "gpt-4o-mini"))
        XCTAssertTrue(provider.supportsVision(model: "gpt-4-turbo"))
        XCTAssertTrue(provider.supportsVision(model: "gpt-4o-2024-08-06"))
        XCTAssertFalse(provider.supportsVision(model: "o3-mini"))
    }

    func testAnthropicVisionSupport() {
        let provider = LLMProvider.anthropic
        XCTAssertTrue(provider.supportsVision(model: "claude-sonnet-4-5-20250514"))
        XCTAssertTrue(provider.supportsVision(model: "claude-3-5-haiku-20241022"))
        XCTAssertTrue(provider.supportsVision(model: "claude-opus-4-20250514"))
        XCTAssertFalse(provider.supportsVision(model: "claude-2.1"))
    }

    func testOllamaVisionSupport() {
        let provider = LLMProvider.ollama
        XCTAssertTrue(provider.supportsVision(model: "llava:latest"))
        XCTAssertTrue(provider.supportsVision(model: "bakllava:7b"))
        XCTAssertTrue(provider.supportsVision(model: "moondream:1.8b"))
        XCTAssertFalse(provider.supportsVision(model: "llama3:8b"))
        XCTAssertFalse(provider.supportsVision(model: "mistral"))
    }

    func testZAIVisionSupport() {
        let provider = LLMProvider.zai
        XCTAssertTrue(provider.supportsVision(model: "glm-5"))
        XCTAssertFalse(provider.supportsVision(model: "glm-4.7"))
    }

    // MARK: - Image Processing

    func testImageProcessorResize() {
        // Create a test image larger than maxLongEdge
        let largeImage = NSImage(size: NSSize(width: 4096, height: 3072))
        largeImage.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: NSSize(width: 4096, height: 3072)).fill()
        largeImage.unlockFocus()

        let resized = ImageProcessor.resize(largeImage, maxEdge: 2048)

        // The longest edge should be <= 2048
        let longestEdge = max(resized.size.width, resized.size.height)
        XCTAssertLessThanOrEqual(longestEdge, 2048)
        // Aspect ratio should be preserved
        let originalAspect = 4096.0 / 3072.0
        let resizedAspect = resized.size.width / resized.size.height
        XCTAssertEqual(originalAspect, resizedAspect, accuracy: 0.01)
    }

    func testImageProcessorResizeSmallImage() {
        // Create a test image smaller than maxLongEdge
        let smallImage = NSImage(size: NSSize(width: 640, height: 480))
        smallImage.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: NSSize(width: 640, height: 480)).fill()
        smallImage.unlockFocus()

        let result = ImageProcessor.resize(smallImage, maxEdge: 2048)

        // Should return the same size (no resize needed)
        XCTAssertEqual(result.size.width, 640)
        XCTAssertEqual(result.size.height, 480)
    }

    func testImageProcessorProcessForLLM() {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(origin: .zero, size: NSSize(width: 100, height: 100)).fill()
        image.unlockFocus()

        let content = ImageProcessor.processForLLM(image)

        XCTAssertNotNil(content)
        XCTAssertEqual(content?.mimeType, "image/jpeg")
        XCTAssertEqual(content?.width, 100)
        XCTAssertEqual(content?.height, 100)
        XCTAssertFalse(content?.base64Data.isEmpty ?? true)
    }

    func testImageProcessorProcessForLLMPNG() {
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.yellow.setFill()
        NSRect(origin: .zero, size: NSSize(width: 50, height: 50)).fill()
        image.unlockFocus()

        let content = ImageProcessor.processForLLM(image, preferPNG: true)

        XCTAssertNotNil(content)
        XCTAssertEqual(content?.mimeType, "image/png")
    }

    func testImageProcessorMimeType() {
        XCTAssertEqual(ImageProcessor.mimeType(for: "png"), "image/png")
        XCTAssertEqual(ImageProcessor.mimeType(for: "jpg"), "image/jpeg")
        XCTAssertEqual(ImageProcessor.mimeType(for: "jpeg"), "image/jpeg")
        XCTAssertEqual(ImageProcessor.mimeType(for: "gif"), "image/gif")
        XCTAssertEqual(ImageProcessor.mimeType(for: "heic"), "image/heic")
        XCTAssertEqual(ImageProcessor.mimeType(for: "tiff"), "image/tiff")
        XCTAssertEqual(ImageProcessor.mimeType(for: "unknown"), "image/jpeg")
    }

    // MARK: - ImageAttachment Constants

    func testImageAttachmentConstants() {
        XCTAssertEqual(ImageAttachment.maxCount, 4)
        XCTAssertEqual(ImageAttachment.maxSizeBytes, 20 * 1024 * 1024)
        XCTAssertEqual(ImageAttachment.maxLongEdge, 2048)
        XCTAssertEqual(ImageAttachment.jpegQuality, 0.85)
    }

    func testImageAttachmentSupportedExtensions() {
        XCTAssertTrue(ImageAttachment.supportedExtensions.contains("png"))
        XCTAssertTrue(ImageAttachment.supportedExtensions.contains("jpg"))
        XCTAssertTrue(ImageAttachment.supportedExtensions.contains("jpeg"))
        XCTAssertTrue(ImageAttachment.supportedExtensions.contains("gif"))
        XCTAssertTrue(ImageAttachment.supportedExtensions.contains("heic"))
        XCTAssertTrue(ImageAttachment.supportedExtensions.contains("tiff"))
        XCTAssertFalse(ImageAttachment.supportedExtensions.contains("bmp"))
    }

    // MARK: - ViewModel Image Management

    @MainActor
    func testViewModelAddRemoveImage() throws {
        let vm = makeTestViewModel()

        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: NSSize(width: 100, height: 100)).fill()
        image.unlockFocus()

        vm.addImage(image, fileName: "test.jpg")
        XCTAssertEqual(vm.pendingImages.count, 1)
        XCTAssertEqual(vm.pendingImages[0].fileName, "test.jpg")

        let id = vm.pendingImages[0].id
        vm.removeImage(id: id)
        XCTAssertTrue(vm.pendingImages.isEmpty)
    }

    @MainActor
    func testViewModelImageLimit() throws {
        let vm = makeTestViewModel()

        for i in 0..<5 {
            let image = NSImage(size: NSSize(width: 50, height: 50))
            image.lockFocus()
            NSColor.red.setFill()
            NSRect(origin: .zero, size: NSSize(width: 50, height: 50)).fill()
            image.unlockFocus()

            vm.addImage(image, fileName: "img\(i).jpg")
        }

        // Should only have maxCount images
        XCTAssertEqual(vm.pendingImages.count, ImageAttachment.maxCount)
        // Should have an error message for the 5th
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testViewModelClearPendingImages() throws {
        let vm = makeTestViewModel()

        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(origin: .zero, size: NSSize(width: 50, height: 50)).fill()
        image.unlockFocus()

        vm.addImage(image, fileName: "test.png")
        XCTAssertEqual(vm.pendingImages.count, 1)

        vm.clearPendingImages()
        XCTAssertTrue(vm.pendingImages.isEmpty)
    }

    @MainActor
    func testViewModelCurrentModelSupportsVision() throws {
        let vm = makeTestViewModel()
        // Default model from mock settings should be tested
        // Just verify the computed property works without crash
        _ = vm.currentModelSupportsVision
    }

    // MARK: - Helper

    @MainActor
    private func makeTestViewModel() -> DochiViewModel {
        DochiViewModel(
            toolService: MockBuiltInToolService(),
            contextService: MockContextService(),
            conversationService: MockConversationService(),
            keychainService: MockKeychainService(),
            speechService: MockSpeechService(),
            ttsService: MockTTSService(),
            soundService: MockSoundService(),
            settings: AppSettings(),
            sessionContext: SessionContext(workspaceId: UUID())
        )
    }
}
