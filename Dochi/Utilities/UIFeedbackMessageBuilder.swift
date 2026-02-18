import Foundation

enum UIFeedbackMessageBuilder {
    static func imageAttachmentFailure(count: Int) -> String {
        if count <= 1 {
            return "이미지 첨부에 실패했습니다."
        }
        return "이미지 \(count)개 첨부에 실패했습니다."
    }

    static func appOpenFailure(appName: String) -> String {
        "\(appName) 열기에 실패했습니다."
    }
}
