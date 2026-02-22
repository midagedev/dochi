import XCTest
@testable import Dochi

final class ReminderListParserTests: XCTestCase {
    func testParseSkipsHeaderAndParsesDueDate() {
        let content = """
        '미리알림' 미리알림 목록:
        정리하기 (마감: 2026-02-23 10:00)
        리뷰 작성
        """

        let parsed = ReminderListParser.parse(content: content)

        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0], ReminderListItem(title: "정리하기", dueDateText: "2026-02-23 10:00", isCompleted: false))
        XCTAssertEqual(parsed[1], ReminderListItem(title: "리뷰 작성", dueDateText: nil, isCompleted: false))
    }

    func testParseRecognizesCompletedPrefix() {
        let content = """
        작업 목록:
        [완료] 문서 업데이트 (마감: 2026-02-21)
        """

        let parsed = ReminderListParser.parse(content: content)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0], ReminderListItem(title: "문서 업데이트", dueDateText: "2026-02-21", isCompleted: true))
    }

    func testParseReturnsEmptyForNoReminderMessage() {
        let content = "'미리알림' 목록에 미리알림이 없습니다."
        XCTAssertTrue(ReminderListParser.parse(content: content).isEmpty)
    }
}
