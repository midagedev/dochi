import XCTest
@testable import Dochi

final class UIFeedbackMessageBuilderTests: XCTestCase {
    func testImageAttachmentFailureSingle() {
        XCTAssertEqual(
            UIFeedbackMessageBuilder.imageAttachmentFailure(count: 1),
            "이미지 첨부에 실패했습니다."
        )
    }

    func testImageAttachmentFailureMultiple() {
        XCTAssertEqual(
            UIFeedbackMessageBuilder.imageAttachmentFailure(count: 3),
            "이미지 3개 첨부에 실패했습니다."
        )
    }

    func testAppOpenFailureMessage() {
        XCTAssertEqual(
            UIFeedbackMessageBuilder.appOpenFailure(appName: "단축어 앱"),
            "단축어 앱 열기에 실패했습니다."
        )
    }
}
