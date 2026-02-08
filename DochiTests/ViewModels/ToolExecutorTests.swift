import XCTest
@testable import Dochi

@MainActor
final class ToolExecutorTests: XCTestCase {

    // MARK: - extractImageURLs

    func testExtractImageURLsFromMarkdown() {
        let content = "Here is an image ![photo](https://example.com/image.png) and text"

        let urls = ToolExecutor.extractImageURLs(from: content)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.absoluteString, "https://example.com/image.png")
    }

    func testExtractMultipleImageURLs() {
        let content = "![a](https://example.com/1.png) and ![b](https://example.com/2.png)"

        let urls = ToolExecutor.extractImageURLs(from: content)

        XCTAssertEqual(urls.count, 2)
    }

    func testExtractImageURLsNoImages() {
        let content = "Just plain text with no images"

        let urls = ToolExecutor.extractImageURLs(from: content)

        XCTAssertTrue(urls.isEmpty)
    }

    func testExtractImageURLsIgnoresRegularLinks() {
        let content = "Visit [Google](https://google.com)"

        let urls = ToolExecutor.extractImageURLs(from: content)

        XCTAssertTrue(urls.isEmpty)
    }

    func testExtractImageURLsEmptyAlt() {
        let content = "![](https://example.com/image.png)"

        let urls = ToolExecutor.extractImageURLs(from: content)

        XCTAssertEqual(urls.count, 1)
    }

    func testExtractImageURLsEmptyString() {
        let urls = ToolExecutor.extractImageURLs(from: "")

        XCTAssertTrue(urls.isEmpty)
    }
}
