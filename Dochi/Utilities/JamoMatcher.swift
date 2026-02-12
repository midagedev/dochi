import Foundation

/// Korean Hangul wake word matcher using Jamo decomposition and Levenshtein distance.
///
/// Decomposes Hangul syllables (U+AC00–U+D7A3) into constituent Jamo (초성/중성/종성),
/// then applies a sliding-window Levenshtein comparison to detect fuzzy matches
/// in a transcript string.
struct JamoMatcher {

    // MARK: - Jamo Tables

    /// 초성 (leading consonants), 19 entries
    private static let leadConsonants: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ",
        "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// 중성 (vowels), 21 entries
    private static let vowels: [Character] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ",
        "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ",
    ]

    /// 종성 (trailing consonants), 28 entries (index 0 = no trailing consonant)
    private static let tailConsonants: [Character?] = [
        nil, "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ",
        "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ",
        "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    private static let hangulBase: UInt32 = 0xAC00
    private static let hangulEnd: UInt32 = 0xD7A3
    private static let vowelCount: UInt32 = 21
    private static let tailCount: UInt32 = 28

    // MARK: - Public API

    /// Determines whether `transcript` contains a fuzzy match for `wakeWord`.
    ///
    /// - Parameters:
    ///   - transcript: The full recognized text (e.g. from STT).
    ///   - wakeWord: The target wake word to detect.
    ///   - threshold: Maximum allowed Levenshtein distance. When `nil`,
    ///     auto-calculated as `max(2, jamoCount / 4)`.
    /// - Returns: `true` if any sliding window over the transcript's Jamo
    ///   representation is within the threshold distance of the wake word's Jamo.
    static func isMatch(transcript: String, wakeWord: String, threshold: Int? = nil) -> Bool {
        let transcriptJamo = decompose(transcript.replacingOccurrences(of: " ", with: ""))
        let wakeWordJamo = decompose(wakeWord.replacingOccurrences(of: " ", with: ""))

        guard !wakeWordJamo.isEmpty else { return false }
        guard !transcriptJamo.isEmpty else { return false }

        let effectiveThreshold = threshold ?? autoThreshold(jamoCount: wakeWordJamo.count)

        // Window sizes in Jamo units: center on the wake word's actual Jamo count
        // with a margin to account for fuzzy matching.
        let jamoMargin = max(1, wakeWordJamo.count / 3)
        let minWindow = max(1, wakeWordJamo.count - jamoMargin)
        let maxWindow = wakeWordJamo.count + jamoMargin

        for windowSize in minWindow...maxWindow {
            if windowSize > transcriptJamo.count {
                continue
            }
            for start in 0...(transcriptJamo.count - windowSize) {
                let window = Array(transcriptJamo[start..<(start + windowSize)])
                let distance = levenshteinDistance(window, wakeWordJamo)
                if distance <= effectiveThreshold {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Jamo Decomposition

    /// Decomposes a string into its Jamo representation.
    /// Hangul syllables are split into 초성 + 중성 + (optional 종성).
    /// Non-Hangul characters are kept as-is.
    static func decompose(_ text: String) -> [Character] {
        var result: [Character] = []
        result.reserveCapacity(text.count * 3)

        for char in text {
            guard let scalar = char.unicodeScalars.first,
                  char.unicodeScalars.count == 1,
                  scalar.value >= hangulBase,
                  scalar.value <= hangulEnd else {
                // Non-Hangul character — keep as-is
                result.append(char)
                continue
            }

            let code = scalar.value - hangulBase
            let leadIndex = Int(code / (vowelCount * tailCount))
            let vowelIndex = Int((code % (vowelCount * tailCount)) / tailCount)
            let tailIndex = Int(code % tailCount)

            result.append(leadConsonants[leadIndex])
            result.append(vowels[vowelIndex])
            if let tail = tailConsonants[tailIndex] {
                result.append(tail)
            }
        }

        return result
    }

    // MARK: - Threshold

    /// Auto-calculate threshold: `max(2, jamoCount / 4)`.
    static func autoThreshold(jamoCount: Int) -> Int {
        max(2, jamoCount / 4)
    }

    // MARK: - Levenshtein Distance

    /// Computes Levenshtein (edit) distance between two character arrays.
    static func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Use two-row optimization to reduce memory from O(m*n) to O(n).
        var previousRow = Array(0...n)
        var currentRow = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            currentRow[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1,      // deletion
                    currentRow[j - 1] + 1,    // insertion
                    previousRow[j - 1] + cost  // substitution
                )
            }
            swap(&previousRow, &currentRow)
        }

        return previousRow[n]
    }
}
