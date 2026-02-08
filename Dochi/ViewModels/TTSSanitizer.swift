import Foundation

/// 마크다운 서식 기호를 제거하여 TTS에 적합한 텍스트로 변환
enum TTSSanitizer {
    static func sanitize(_ text: String) -> String {
        var s = text

        if s.hasPrefix("```") { return "" }

        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`([^`]*)`"#, with: "$1", options: .regularExpression)

        s = s.replacingOccurrences(of: #"\*{1,3}([^*]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"_{1,3}([^_]+)_{1,3}"#, with: "$1", options: .regularExpression)

        s = s.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[-*+]\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[-*_]{3,}$"#, with: "", options: .regularExpression)

        s = s.replacingOccurrences(of: "*", with: "")
        s = s.replacingOccurrences(of: ":", with: ",")

        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
