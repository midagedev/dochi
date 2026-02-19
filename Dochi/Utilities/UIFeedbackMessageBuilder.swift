import Foundation

enum UIFeedbackMessageBuilder {
    static func imageAttachmentFailure(count: Int) -> String {
        if count <= 1 {
            return "이미지 첨부에 실패했습니다."
        }
        return "이미지 \(count)개 첨부에 실패했습니다."
    }

    static func imageAttachmentFailure(failedNames: [String]) -> String {
        let uniqueNames = Array(NSOrderedSet(array: failedNames).compactMap { $0 as? String })
        guard !uniqueNames.isEmpty else {
            return imageAttachmentFailure(count: 1)
        }
        if uniqueNames.count == 1 {
            return "이미지 첨부에 실패했습니다: \(uniqueNames[0])"
        }
        let preview = uniqueNames.prefix(3).joined(separator: ", ")
        if uniqueNames.count > 3 {
            return "이미지 \(uniqueNames.count)개 첨부에 실패했습니다: \(preview) 외 \(uniqueNames.count - 3)개"
        }
        return "이미지 \(uniqueNames.count)개 첨부에 실패했습니다: \(preview)"
    }

    static func appOpenFailure(appName: String) -> String {
        "\(appName) 열기에 실패했습니다."
    }
}
