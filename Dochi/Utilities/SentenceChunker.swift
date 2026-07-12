import Foundation

/// Buffers streaming text and emits complete sentences.
/// Used to feed TTS from LLM SSE streaming output.
struct SentenceChunker {
    private var buffer: String = ""

    /// Sentence boundary characters
    private static let boundaries: Set<Character> = [".", "!", "?", "\n", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
    /// Korean sentence-ending particles that indicate sentence boundary
    private static let koreanEndings = ["다.", "요.", "죠.", "까?", "요?", "죠?", "다!", "요!", "죠!"]

    /// Append new text delta from LLM streaming.
    /// Returns any complete sentences found.
    mutating func append(_ delta: String) -> [String] {
        buffer += delta
        return extractSentences()
    }

    /// Flush remaining buffer as a final sentence.
    mutating func flush() -> String? {
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return remaining.isEmpty ? nil : remaining
    }

    private mutating func extractSentences() -> [String] {
        var sentences: [String] = []

        while let range = findSentenceBoundary() {
            let sentence = String(buffer[buffer.startIndex...range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            buffer = String(buffer[buffer.index(after: range)...])
        }

        return sentences
    }

    private func findSentenceBoundary() -> String.Index? {
        for (index, char) in buffer.enumerated() {
            let stringIndex = buffer.index(buffer.startIndex, offsetBy: index)
            if Self.boundaries.contains(char) {
                if isInsideURL(at: stringIndex) { continue }
                // Don't split on decimal points (e.g., "3.14")
                if char == "." && index > 0 {
                    let prevIndex = buffer.index(before: stringIndex)
                    if buffer[prevIndex].isNumber { continue }
                }
                return stringIndex
            }
        }
        return nil
    }

    private func isInsideURL(at index: String.Index) -> Bool {
        let prefix = buffer[..<index]
        guard let tokenStart = prefix.lastIndex(where: { $0.isWhitespace || $0 == "(" || $0 == "[" || $0 == "\"" || $0 == "'" }) else {
            let token = buffer[buffer.startIndex...index]
            return token.hasPrefix("http://") || token.hasPrefix("https://") || token.hasPrefix("file://")
        }

        let start = buffer.index(after: tokenStart)
        let token = buffer[start...index]
        return token.hasPrefix("http://") || token.hasPrefix("https://") || token.hasPrefix("file://")
    }
}
