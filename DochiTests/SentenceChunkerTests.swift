import XCTest
@testable import Dochi

final class SentenceChunkerTests: XCTestCase {
    func testEmitsCompleteSentencesOnBoundaries() {
        var chunker = SentenceChunker()
        XCTAssertEqual(chunker.append("안녕하세요"), [])
        XCTAssertEqual(chunker.append(". 반갑"), ["안녕하세요."])
        XCTAssertEqual(chunker.append("습니다!"), ["반갑습니다!"])
    }

    func testDoesNotSplitDecimals() {
        var chunker = SentenceChunker()
        let result = chunker.append("원주율은 3.14입니다.")
        XCTAssertEqual(result, ["원주율은 3.14입니다."])
    }

    func testFlushReturnsRemainingBuffer() {
        var chunker = SentenceChunker()
        _ = chunker.append("끝맺음 없는 문장")
        XCTAssertEqual(chunker.flush(), "끝맺음 없는 문장")
        XCTAssertNil(chunker.flush())
    }
}
