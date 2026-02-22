import XCTest
import MCP
@testable import Dochi

final class MCPServiceContentExtractionTests: XCTestCase {

    func testSummarizedToolContentReturnsEmbeddedResourceText() {
        let content: Tool.Content = .resource(
            resource: .text(
                "hello-world",
                uri: "file:///tmp/readme.txt",
                mimeType: "text/plain"
            )
        )

        let summary = MCPService.summarizedToolContent(content)

        XCTAssertEqual(summary, "hello-world")
    }

    func testSummarizedToolContentFormatsBinaryResource() {
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        let content: Tool.Content = .resource(
            resource: .binary(
                bytes,
                uri: "file:///tmp/archive.bin",
                mimeType: "application/octet-stream"
            )
        )

        let summary = MCPService.summarizedToolContent(content)

        XCTAssertEqual(
            summary,
            "[resource: file:///tmp/archive.bin, application/octet-stream, 8 chars(base64)]"
        )
    }

    func testSummarizedToolContentFormatsResourceLink() {
        let content: Tool.Content = .resourceLink(
            uri: "https://example.com/spec",
            name: "spec",
            title: "Spec Document",
            description: "link",
            mimeType: "text/html",
            annotations: nil
        )

        let summary = MCPService.summarizedToolContent(content)

        XCTAssertEqual(summary, "[resource-link: Spec Document, text/html, https://example.com/spec]")
    }

    func testSummarizedToolContentFormatsResourceLinkFallback() {
        let content: Tool.Content = .resourceLink(
            uri: "https://example.com/no-meta",
            name: "fallback-name",
            title: nil,
            description: nil,
            mimeType: nil,
            annotations: nil
        )

        let summary = MCPService.summarizedToolContent(content)

        XCTAssertEqual(summary, "[resource-link: fallback-name, https://example.com/no-meta]")
    }
}
