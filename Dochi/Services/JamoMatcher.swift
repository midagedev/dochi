import Foundation

/// 한글 자모 분해 기반 유사도 매칭 유틸리티
enum JamoMatcher {

    // MARK: - Jamo Decomposition

    /// 한글 음절을 초성/중성/종성 자모로 분해
    static func decompose(_ char: Character) -> [UInt32] {
        guard let scalar = char.unicodeScalars.first else { return [] }
        let code = scalar.value

        // 한글 음절 범위: 0xAC00...0xD7A3
        guard code >= 0xAC00, code <= 0xD7A3 else {
            return [code]
        }

        let base = code - 0xAC00
        let cho = base / (21 * 28)     // 초성
        let jung = (base % (21 * 28)) / 28  // 중성
        let jong = base % 28           // 종성 (0이면 없음)

        // 초성 기본 오프셋: 0x1100, 중성: 0x1161, 종성: 0x11A7
        var result: [UInt32] = [0x1100 + cho, 0x1161 + jung]
        if jong > 0 {
            result.append(0x11A7 + jong)
        }
        return result
    }

    /// 문자열 전체를 자모 시퀀스로 분해
    static func decompose(_ string: String) -> [UInt32] {
        string.flatMap { decompose($0) }
    }

    // MARK: - Levenshtein Distance

    /// 두 자모 시퀀스 간 편집 거리 계산
    static func levenshteinDistance(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        // 1차원 배열로 최적화
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = min(prev[j - 1], prev[j], curr[j - 1]) + 1
                }
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }

    // MARK: - Sliding Window Match

    /// transcript에서 웨이크워드와 가장 유사한 구간을 탐색
    /// - Returns: 최소 편집 거리와 매칭된 부분문자열, 없으면 nil
    static func findBestMatch(in transcript: String, for wakeWord: String) -> (distance: Int, match: String)? {
        let normalized = transcript.replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return nil }

        let chars = Array(normalized)
        let wakeWordJamo = decompose(wakeWord)
        let wakeWordLen = wakeWord.count

        guard wakeWordLen > 0 else { return nil }

        var bestDistance = Int.max
        var bestMatch = ""

        // 윈도우 크기: 웨이크워드 음절 수 ±1
        let minWindow = max(1, wakeWordLen - 1)
        let maxWindow = wakeWordLen + 1

        for windowSize in minWindow...maxWindow {
            guard windowSize <= chars.count else { continue }

            for start in 0...(chars.count - windowSize) {
                let substring = String(chars[start..<start + windowSize])
                let substringJamo = decompose(substring)
                let distance = levenshteinDistance(wakeWordJamo, substringJamo)

                if distance < bestDistance {
                    bestDistance = distance
                    bestMatch = substring
                }
            }
        }

        return bestDistance < Int.max ? (bestDistance, bestMatch) : nil
    }

    /// transcript에서 웨이크워드가 유사하게 포함되어 있는지 판정
    /// - Parameters:
    ///   - transcript: STT 인식 결과
    ///   - wakeWord: 원본 웨이크워드
    ///   - threshold: 허용 편집 거리 (nil이면 자동 계산: max(2, 자모수/4))
    static func isMatch(transcript: String, wakeWord: String, threshold: Int? = nil) -> Bool {
        let wakeWordJamo = decompose(wakeWord)
        let autoThreshold = threshold ?? max(2, wakeWordJamo.count / 4)

        guard let result = findBestMatch(in: transcript, for: wakeWord) else {
            return false
        }

        return result.distance <= autoThreshold
    }
}
