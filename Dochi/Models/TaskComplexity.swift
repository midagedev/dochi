import Foundation

/// Represents the complexity tier for routing to different models.
enum TaskComplexity: String, Codable, CaseIterable, Sendable {
    case light    // 일상 대화, 간단한 질문
    case standard // 일반적인 작업 (기본값)
    case heavy    // 코딩, 분석, 긴 문서 작업

    var displayName: String {
        switch self {
        case .light: "경량"
        case .standard: "표준"
        case .heavy: "고급"
        }
    }

    var description: String {
        switch self {
        case .light: "인사, 간단한 질문, 일상 대화"
        case .standard: "일반 작업 (기본 모델 사용)"
        case .heavy: "코딩, 데이터 분석, 복잡한 추론"
        }
    }
}

/// Classifies user input into a task complexity tier using keyword heuristics.
enum TaskComplexityClassifier {

    /// Keywords/patterns that suggest heavy (complex) tasks.
    private static let heavyPatterns: [String] = [
        "코드", "코딩", "프로그래밍", "함수", "클래스", "버그", "디버그",
        "분석", "비교", "요약해", "정리해", "계산",
        "작성해", "만들어", "구현", "설계",
        "code", "debug", "implement", "analyze", "refactor",
        "algorithm", "database", "sql", "api",
        "번역해", "translate",
    ]

    /// Keywords/patterns that suggest light (simple) tasks.
    private static let lightPatterns: [String] = [
        "안녕", "고마워", "감사", "ㅎㅎ", "ㅋㅋ", "네", "응",
        "오늘 날씨", "몇 시", "뭐 해",
        "hello", "hi", "thanks", "ok", "yes", "no",
        "좋아", "알겠어", "그래",
    ]

    /// Classify the complexity of a user message.
    static func classify(_ text: String) -> TaskComplexity {
        let lowered = text.lowercased()
        let length = text.count

        // Very short messages are likely casual
        if length < 10 {
            // But check for heavy keywords even in short messages
            if heavyPatterns.contains(where: { lowered.contains($0) }) {
                return .heavy
            }
            return .light
        }

        // Check for heavy patterns
        let heavyScore = heavyPatterns.reduce(0) { score, pattern in
            score + (lowered.contains(pattern) ? 1 : 0)
        }

        // Check for light patterns
        let lightScore = lightPatterns.reduce(0) { score, pattern in
            score + (lowered.contains(pattern) ? 1 : 0)
        }

        // Long messages (>200 chars) with tool-use indicators lean heavy
        let longBonus = length > 200 ? 1 : 0

        if heavyScore + longBonus >= 2 {
            return .heavy
        } else if heavyScore > lightScore {
            return .heavy
        } else if lightScore > 0 && heavyScore == 0 && length < 30 {
            return .light
        }

        return .standard
    }
}
