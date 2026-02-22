import XCTest
import MCP
@testable import Dochi

final class MCPServiceContentExtractionTests: XCTestCase {

    func testSummarizedToolContentReturnsEmbeddedResourceText() {
        let content: Tool.Content = .resource(
            uri: "file:///tmp/readme.txt",
            mimeType: "text/plain",
            text: "hello-world"
        )

        let summary = MCPService.summarizedToolContent(content)

        XCTAssertEqual(summary, "hello-world")
    }

    func testSummarizedToolContentFormatsResourceWithoutText() {
        let content: Tool.Content = .resource(
            uri: "file:///tmp/archive.bin",
            mimeType: "application/octet-stream",
            text: nil
        )

        let summary = MCPService.summarizedToolContent(content)

        XCTAssertEqual(
            summary,
            "[resource: file:///tmp/archive.bin, application/octet-stream]"
        )
    }

    func testSummarizedToolContentFormatsImage() {
        let content: Tool.Content = .image(
            data: "YWJjZA==",
            mimeType: "image/png",
            metadata: nil
        )

        let summary = MCPService.summarizedToolContent(content)

        XCTAssertEqual(summary, "[image: image/png, 8 bytes]")
    }

    func testSummarizedToolContentFormatsAudio() {
        let content: Tool.Content = .audio(
            data: "YWJjZA==",
            mimeType: "audio/wav"
        )

        let summary = MCPService.summarizedToolContent(content)

        XCTAssertEqual(summary, "[audio: audio/wav, 8 bytes]")
    }
}
