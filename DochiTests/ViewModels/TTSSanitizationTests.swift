import XCTest
@testable import Dochi

@MainActor
final class TTSSanitizationTests: XCTestCase {

    // MARK: - Code Blocks

    func testCodeBlockReturnsEmpty() {
        let result = TTSSanitizer.sanitize("```swift\nlet x = 1\n```")

        XCTAssertEqual(result, "")
    }

    // MARK: - Markdown Links

    func testImageMarkdownRemoved() {
        let result = TTSSanitizer.sanitize("Here is an image ![alt](https://example.com/img.png)")

        XCTAssertFalse(result.contains("!["))
        XCTAssertFalse(result.contains("https://"))
    }

    func testLinkMarkdownKeepsText() {
        let result = TTSSanitizer.sanitize("Visit [Google](https://google.com) now")

        XCTAssertTrue(result.contains("Google"))
        XCTAssertFalse(result.contains("https://"))
    }

    // MARK: - Inline Code

    func testInlineCodeStripped() {
        let result = TTSSanitizer.sanitize("Use `print()` to debug")

        XCTAssertTrue(result.contains("print()"))
        XCTAssertFalse(result.contains("`"))
    }

    // MARK: - Bold and Italic

    func testBoldStripped() {
        let result = TTSSanitizer.sanitize("This is **bold** text")

        XCTAssertTrue(result.contains("bold"))
        XCTAssertFalse(result.contains("**"))
    }

    func testItalicStripped() {
        let result = TTSSanitizer.sanitize("This is *italic* text")

        XCTAssertTrue(result.contains("italic"))
    }

    // MARK: - Headers

    func testHeaderStripped() {
        let result = TTSSanitizer.sanitize("## Section Title")

        XCTAssertTrue(result.contains("Section Title"))
        XCTAssertFalse(result.contains("#"))
    }

    // MARK: - Special Characters

    func testColonReplacedWithComma() {
        let result = TTSSanitizer.sanitize("Time: 3pm")

        XCTAssertTrue(result.contains(","))
        XCTAssertFalse(result.contains(":"))
    }

    // MARK: - Whitespace

    func testMultipleSpacesCollapsed() {
        let result = TTSSanitizer.sanitize("Hello    world")

        XCTAssertEqual(result, "Hello world")
    }

    func testTrimsWhitespace() {
        let result = TTSSanitizer.sanitize("  Hello  ")

        XCTAssertEqual(result, "Hello")
    }

    // MARK: - List Items

    func testBulletListStripped() {
        let result = TTSSanitizer.sanitize("- Item one")

        XCTAssertEqual(result, "Item one")
    }

    // MARK: - Blockquote

    func testBlockquoteStripped() {
        let result = TTSSanitizer.sanitize("> Quote text")

        XCTAssertTrue(result.contains("Quote text"))
        XCTAssertFalse(result.contains(">"))
    }

    // MARK: - Horizontal Rule

    func testHorizontalRuleRemoved() {
        let result = TTSSanitizer.sanitize("---")

        XCTAssertEqual(result, "")
    }

    // MARK: - Plain Text

    func testPlainTextUnchanged() {
        let result = TTSSanitizer.sanitize("안녕하세요")

        XCTAssertEqual(result, "안녕하세요")
    }

    func testEmptyStringReturnsEmpty() {
        let result = TTSSanitizer.sanitize("")

        XCTAssertEqual(result, "")
    }
}
