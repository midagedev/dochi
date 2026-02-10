import Foundation

/// Incrementally splits streamed text into sentence-like chunks.
/// - Terminates on newline immediately or on punctuation followed by whitespace.
final class SentenceChunker {
    private var buffer: String = ""
    private static let terminators: Set<Character> = [".", "?", "!", "。"]

    func reset() { buffer = "" }

    /// Feed new text and return any completed sentences.
    func process(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        while let idx = findBoundary() {
            let sentence = String(buffer[buffer.startIndex...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[buffer.index(after: idx)...])
            if !sentence.isEmpty { sentences.append(sentence) }
        }
        return sentences
    }

    /// Flush any remaining non-empty text as one final sentence.
    func flush() -> String? {
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return remaining.isEmpty ? nil : remaining
    }

    private func findBoundary() -> String.Index? {
        var i = buffer.startIndex
        while i < buffer.endIndex {
            let ch = buffer[i]
            if ch == "\n" { return i }
            if Self.terminators.contains(ch) {
                let next = buffer.index(after: i)
                if next < buffer.endIndex && buffer[next].isWhitespace { return i }
                if next == buffer.endIndex { return nil }
            }
            i = buffer.index(after: i)
        }
        return nil
    }
}

