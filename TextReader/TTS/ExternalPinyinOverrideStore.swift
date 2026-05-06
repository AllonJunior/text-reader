import Foundation
import Combine

enum ReaderTextCanonicalizer {
    static func normalizeLineEndingsAndBOM(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if normalized.unicodeScalars.first == "\u{FEFF}" {
            normalized.removeFirst()
        }

        return normalized
    }

    static func normalizeForMatching(_ text: String) -> String {
        normalizeLineEndingsAndBOM(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimmedRange(in text: String) -> Range<String.Index>? {
        guard let start = text.firstIndex(where: { !isWhitespaceOrNewline($0) }),
              let end = text.lastIndex(where: { !isWhitespaceOrNewline($0) })
        else {
            return nil
        }

        return start..<text.index(after: end)
    }

    static func isWhitespaceOrNewline(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

struct TextMismatchDiagnostic: Equatable {
    let position: Int
    let currentTextExcerpt: String
    let overrideTextExcerpt: String
    let summary: String
    let currentTextHighlightRange: NSRange?
}

struct LoadedPinyinOverride: Equatable {
    let text: String
    let normalizedText: String
    let tokens: [String]
    let sourceDescription: String
    let fileURL: URL

    func matches(text candidate: String) -> Bool {
        normalizedText == ReaderTextCanonicalizer.normalizeForMatching(candidate)
    }
}

struct ResolvedSentencePinyinOverride: Equatable {
    let tokens: [String]
    let sourceDescription: String
}

enum ExternalPinyinOverrideError: LocalizedError {
    case invalidFormat(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let detail), .loadFailed(let detail):
            return detail
        }
    }
}

private struct ExternalPinyinOverrideFile: Decodable {
    let text: String
    let tokens: [String]
    let source: String?
    let notes: String?
}

final class ExternalPinyinOverrideStore: ObservableObject {
    static let shared = ExternalPinyinOverrideStore()

    @Published private(set) var loadedOverride: LoadedPinyinOverride?

    private init() {}

    func load(from url: URL) throws -> LoadedPinyinOverride {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ExternalPinyinOverrideError.loadFailed("无法读取拼音覆盖文件：\(error.localizedDescription)")
        }

        let decoded: ExternalPinyinOverrideFile
        do {
            decoded = try JSONDecoder().decode(ExternalPinyinOverrideFile.self, from: data)
        } catch {
            throw ExternalPinyinOverrideError.invalidFormat(
                "拼音覆盖 JSON 格式不正确。需要包含 text 和 tokens 字段。\n\n系统错误：\(error.localizedDescription)"
            )
        }

        let normalizedText = ReaderTextCanonicalizer.normalizeForMatching(decoded.text)
        guard !normalizedText.isEmpty else {
            throw ExternalPinyinOverrideError.invalidFormat("拼音覆盖文件中的 text 不能为空。")
        }

        let tokens = decoded.tokens
        guard tokens.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ExternalPinyinOverrideError.invalidFormat("拼音覆盖文件中的 tokens 不能为空。")
        }

        let sourceParts = [decoded.source, decoded.notes]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        let sourceDescription = sourceParts.isEmpty
            ? url.lastPathComponent
            : sourceParts.joined(separator: " · ")

        let loaded = LoadedPinyinOverride(
            text: decoded.text,
            normalizedText: normalizedText,
            tokens: tokens,
            sourceDescription: sourceDescription,
            fileURL: url
        )
        loadedOverride = loaded
        return loaded
    }

    func clear() {
        loadedOverride = nil
    }

    func tokens(for text: String) -> [String]? {
        guard let loadedOverride, loadedOverride.matches(text: text) else {
            return nil
        }
        return loadedOverride.tokens
    }

    func matchedOverride(for text: String) -> LoadedPinyinOverride? {
        guard let loadedOverride, loadedOverride.matches(text: text) else {
            return nil
        }
        return loadedOverride
    }

    func mismatchDiagnostic(for candidate: String) -> TextMismatchDiagnostic? {
        guard let loadedOverride, !loadedOverride.matches(text: candidate) else {
            return nil
        }

        let canonicalCandidate = ReaderTextCanonicalizer.normalizeLineEndingsAndBOM(candidate)
        let candidateTrimmedRange = ReaderTextCanonicalizer.trimmedRange(in: canonicalCandidate) ?? canonicalCandidate.startIndex..<canonicalCandidate.startIndex
        let trimmedCandidate = String(canonicalCandidate[candidateTrimmedRange])
        let overrideText = loadedOverride.normalizedText

        let candidateChars = Array(trimmedCandidate)
        let overrideChars = Array(overrideText)

        var prefixCount = 0
        while prefixCount < candidateChars.count,
              prefixCount < overrideChars.count,
              candidateChars[prefixCount] == overrideChars[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < candidateChars.count - prefixCount,
              suffixCount < overrideChars.count - prefixCount,
              candidateChars[candidateChars.count - 1 - suffixCount] == overrideChars[overrideChars.count - 1 - suffixCount] {
            suffixCount += 1
        }

        let candidateDiffRange = prefixCount..<(candidateChars.count - suffixCount)
        let overrideDiffRange = prefixCount..<(overrideChars.count - suffixCount)
        let currentTextHighlightRange = highlightRange(
            in: canonicalCandidate,
            trimmedRange: candidateTrimmedRange,
            diffRange: candidateDiffRange
        )

        let candidateDiffCount = max(candidateDiffRange.count, 1)
        let overrideDiffCount = max(overrideDiffRange.count, 1)
        let summary: String
        if candidateDiffRange.isEmpty {
            summary = "从第 \(prefixCount + 1) 个字符开始，当前文本缺少 JSON 中的一段内容。"
        } else if overrideDiffRange.isEmpty {
            summary = "从第 \(prefixCount + 1) 个字符开始，当前文本比 JSON 多出一段内容。"
        } else if candidateDiffCount == overrideDiffCount {
            summary = "第 \(prefixCount + 1)–\(prefixCount + candidateDiffCount) 个字符与 JSON 不一致。"
        } else {
            summary = "从第 \(prefixCount + 1) 个字符开始，两边有长度不同的区段。"
        }

        return TextMismatchDiagnostic(
            position: prefixCount + 1,
            currentTextExcerpt: excerpt(from: candidateChars, diffRange: candidateDiffRange),
            overrideTextExcerpt: excerpt(from: overrideChars, diffRange: overrideDiffRange),
            summary: summary,
            currentTextHighlightRange: currentTextHighlightRange
        )
    }

    func sentenceOverrides(for fullText: String, sentences: [String]) -> [ResolvedSentencePinyinOverride]? {
        guard let loadedOverride else {
            return nil
        }

        let normalizedFullText = ReaderTextCanonicalizer.normalizeForMatching(fullText)
        guard loadedOverride.normalizedText == normalizedFullText else {
            return nil
        }

        let alignedText = Array(loadedOverride.normalizedText)
        guard alignedText.count == loadedOverride.tokens.count else {
            return nil
        }

        var cursor = 0
        var resolved: [ResolvedSentencePinyinOverride] = []
        resolved.reserveCapacity(sentences.count)

        func skipLeadingWhitespace() {
            while cursor < alignedText.count,
                  alignedText[cursor].unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                cursor += 1
            }
        }

        for sentence in sentences {
            let trimmedSentence = ReaderTextCanonicalizer.normalizeForMatching(sentence)
            guard !trimmedSentence.isEmpty else { continue }

            skipLeadingWhitespace()

            let start = cursor
            for character in trimmedSentence {
                guard cursor < alignedText.count, alignedText[cursor] == character else {
                    return nil
                }
                cursor += 1
            }

            resolved.append(
                ResolvedSentencePinyinOverride(
                    tokens: Array(loadedOverride.tokens[start..<cursor]),
                    sourceDescription: loadedOverride.sourceDescription
                )
            )
        }

        skipLeadingWhitespace()
        guard cursor == alignedText.count else {
            return nil
        }

        return resolved.count == sentences.count ? resolved : nil
    }

    private func highlightRange(
        in fullText: String,
        trimmedRange: Range<String.Index>,
        diffRange: Range<Int>
    ) -> NSRange? {
        let visibleRange: Range<String.Index>
        if !diffRange.isEmpty {
            let lowerBound = fullText.index(trimmedRange.lowerBound, offsetBy: diffRange.lowerBound)
            let upperBound = fullText.index(trimmedRange.lowerBound, offsetBy: diffRange.upperBound)
            visibleRange = lowerBound..<upperBound
        } else if trimmedRange.lowerBound < trimmedRange.upperBound {
            let anchor = fullText.index(trimmedRange.lowerBound, offsetBy: diffRange.lowerBound)
            if anchor < trimmedRange.upperBound {
                visibleRange = anchor..<fullText.index(after: anchor)
            } else {
                let previous = fullText.index(before: anchor)
                visibleRange = previous..<anchor
            }
        } else {
            return nil
        }

        return NSRange(visibleRange, in: fullText)
    }

    private func excerpt(from characters: [Character], diffRange: Range<Int>, contextRadius: Int = 8) -> String {
        let start = max(0, diffRange.lowerBound - contextRadius)
        let end = min(characters.count, diffRange.upperBound + contextRadius)

        let prefix = start > 0 ? "…" : ""
        let suffix = end < characters.count ? "…" : ""
        let leading = String(characters[start..<diffRange.lowerBound])
        let differing = diffRange.isEmpty ? "∅" : String(characters[diffRange])
        let trailing = String(characters[diffRange.upperBound..<end])
        return prefix + leading + "【" + differing + "】" + trailing + suffix
    }
}
