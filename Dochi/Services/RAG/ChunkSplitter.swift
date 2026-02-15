import Foundation

/// 텍스트를 RAG 인덱싱용 청크로 분할하는 유틸리티.
/// 마크다운은 섹션(# 헤더) 기준으로 먼저 분할한 후, 각 섹션을 maxChunkSize 이하 청크로 나눈다.
/// 일반 텍스트는 문단(빈 줄) 기준으로 분할 후 청크를 생성한다.
struct ChunkSplitter: Sendable {

    struct Chunk: Sendable, Equatable {
        let content: String
        let sectionTitle: String?
        let position: Int
    }

    let maxChunkSize: Int
    let overlapSize: Int

    init(maxChunkSize: Int = 500, overlapSize: Int = 100) {
        self.maxChunkSize = max(100, maxChunkSize)
        self.overlapSize = max(0, min(overlapSize, maxChunkSize / 2))
    }

    // MARK: - Public

    /// 마크다운 텍스트를 섹션 → 청크로 분할
    func splitMarkdown(_ text: String) -> [Chunk] {
        let sections = splitIntoSections(text)
        var chunks: [Chunk] = []
        var position = 0

        for section in sections {
            let sectionChunks = splitTextIntoChunks(section.content, sectionTitle: section.title, startPosition: position)
            chunks.append(contentsOf: sectionChunks)
            position += sectionChunks.count
        }

        return chunks
    }

    /// 일반 텍스트를 문단 → 청크로 분할
    func splitPlainText(_ text: String) -> [Chunk] {
        return splitTextIntoChunks(text, sectionTitle: nil, startPosition: 0)
    }

    // MARK: - Internal

    struct Section {
        let title: String?
        let content: String
    }

    /// 마크다운 헤더(# ~ ###)를 기준으로 섹션 분할
    func splitIntoSections(_ text: String) -> [Section] {
        let lines = text.components(separatedBy: "\n")
        var sections: [Section] = []
        var currentTitle: String? = nil
        var currentLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                // Flush current section
                if !currentLines.isEmpty {
                    let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        sections.append(Section(title: currentTitle, content: content))
                    }
                }
                // Extract title (remove # prefix)
                currentTitle = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                currentLines = [line]
            } else {
                currentLines.append(line)
            }
        }

        // Flush last section
        if !currentLines.isEmpty {
            let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                sections.append(Section(title: currentTitle, content: content))
            }
        }

        // If no sections found (no headers), treat entire text as one section
        if sections.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(Section(title: nil, content: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return sections
    }

    /// 텍스트를 문단 단위로 나눈 뒤 maxChunkSize에 맞게 청크 생성 (오버랩 포함)
    func splitTextIntoChunks(_ text: String, sectionTitle: String?, startPosition: Int) -> [Chunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // If text fits in one chunk
        if trimmed.count <= maxChunkSize {
            return [Chunk(content: trimmed, sectionTitle: sectionTitle, position: startPosition)]
        }

        // Split by paragraphs (double newline)
        let paragraphs = trimmed.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [Chunk] = []
        var currentChunk = ""
        var position = startPosition

        for paragraph in paragraphs {
            if currentChunk.isEmpty {
                currentChunk = paragraph
            } else if currentChunk.count + paragraph.count + 2 <= maxChunkSize {
                currentChunk += "\n\n" + paragraph
            } else {
                // Emit current chunk
                chunks.append(Chunk(content: currentChunk, sectionTitle: sectionTitle, position: position))
                position += 1

                // Start new chunk with overlap
                if overlapSize > 0 && currentChunk.count > overlapSize {
                    let overlapText = String(currentChunk.suffix(overlapSize))
                    currentChunk = overlapText + "\n\n" + paragraph
                } else {
                    currentChunk = paragraph
                }
            }
        }

        // Flush remaining
        if !currentChunk.isEmpty {
            chunks.append(Chunk(content: currentChunk, sectionTitle: sectionTitle, position: position))
        }

        // Handle case where a single paragraph exceeds maxChunkSize
        var finalChunks: [Chunk] = []
        var pos = startPosition
        for chunk in chunks {
            if chunk.content.count <= maxChunkSize {
                finalChunks.append(Chunk(content: chunk.content, sectionTitle: chunk.sectionTitle, position: pos))
                pos += 1
            } else {
                // Force split long chunk by character boundary
                let subChunks = forceSplit(chunk.content, sectionTitle: chunk.sectionTitle, startPosition: pos)
                finalChunks.append(contentsOf: subChunks)
                pos += subChunks.count
            }
        }

        return finalChunks
    }

    /// maxChunkSize를 초과하는 텍스트를 강제 분할
    private func forceSplit(_ text: String, sectionTitle: String?, startPosition: Int) -> [Chunk] {
        var chunks: [Chunk] = []
        var position = startPosition
        var remaining = text

        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(maxChunkSize, remaining.count))
            let chunkText = String(remaining[remaining.startIndex..<end])
            chunks.append(Chunk(content: chunkText, sectionTitle: sectionTitle, position: position))
            position += 1

            if end < remaining.endIndex {
                let overlapStart = remaining.index(end, offsetBy: -min(overlapSize, remaining.distance(from: remaining.startIndex, to: end)))
                remaining = String(remaining[overlapStart...])
                // Avoid infinite loop if overlap equals chunk
                if remaining.count >= text.count {
                    break
                }
            } else {
                remaining = ""
            }
        }

        return chunks
    }
}
