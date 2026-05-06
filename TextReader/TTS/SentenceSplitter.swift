import Foundation

/// Very small sentence splitter for Chinese/English punctuation.
///
/// Design goals:
/// - Split long text into speakable chunks.
/// - Preserve punctuation at the end of each chunk.
/// - Treat newlines as hard boundaries.
///
/// This is intentionally simple. You can improve it later (e.g. quotes, abbreviations).
enum SentenceSplitter {
    static func split(_ text: String, maxChunkLength: Int = 200) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Treat *any* newline as a boundary: each non-empty line becomes its own splitLine input.
        let rawLines = trimmed.components(separatedBy: .newlines)

        var results: [String] = []
        results.reserveCapacity(rawLines.count)

        for raw in rawLines {
            let normalized = normalizeLinePrefix(raw)
            guard !normalized.isEmpty else {
                // Empty line acts as a boundary but doesn't produce output.
                continue
            }

            if isTitleLine(normalized) {
                results.append(normalized)
            } else {
                results.append(contentsOf: splitLine(normalized, maxChunkLength: maxChunkLength))
            }
        }

        return results
    }

    /// Removes leading indentation commonly seen in Chinese novels.
    /// - Trims ASCII whitespace.
    /// - Trims leading full-width spaces (U+3000) and common ideographic indent.
    private static func normalizeLinePrefix(_ line: String) -> String {
        var s = line

        // Trim ASCII whitespace first.
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return "" }

        // Remove leading full-width spaces and similar indents.
        while let first = s.first {
            if first == "\u{3000}" || first == "　" { // full-width space
                s.removeFirst()
                continue
            }
            // Some texts use tabs for indentation.
            if first == "\t" {
                s.removeFirst()
                continue
            }
            break
        }

        // Collapse multi spaces at start again.
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Heuristic: treat chapter/volume titles as standalone chunks.
    private static func isTitleLine(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }

        // Very long lines are probably not titles.
        if s.count > 30 { return false }

        // Common one-word titles.
        let simpleTitles: Set<String> = ["序", "序章", "楔子", "引子", "前言", "后记", "後記", "尾声", "尾聲"]
        if simpleTitles.contains(s) { return true }

        // Match patterns like:
        // - 第一章 离乡
        // - 第1章 离乡
        // - 第一卷 平庸少年
        // - 第十卷 ...
        // - 第三节 ...
        let pattern = "^第[0-9一二三四五六七八九十百千两〇零]+[章节卷部篇回集节]\\s*.+$"
        if s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        // Also allow "第X章" with no trailing text.
        let pattern2 = "^第[0-9一二三四五六七八九十百千两〇零]+[章节卷部篇回集节]$"
        if s.range(of: pattern2, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        return false
    }

    private static func splitLine(_ line: String, maxChunkLength: Int) -> [String] {
        // Work with an indexable view.
        let chars = Array(line)
        var out: [String] = []

        var buffer = ""
        var lastSoftBoundaryIndexInBuffer: Int? = nil

        func flushBuffer() {
            let t = buffer.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(t) }
            buffer = ""
            lastSoftBoundaryIndexInBuffer = nil
        }

        func flushAtLastSoftBoundary() {
            guard let cut = lastSoftBoundaryIndexInBuffer, cut > 0 else {
                flushBuffer()
                return
            }

            let idx = buffer.index(buffer.startIndex, offsetBy: cut)
            let head = String(buffer[..<idx]).trimmingCharacters(in: .whitespaces)
            let tail = String(buffer[idx...]).trimmingCharacters(in: .whitespaces)

            if !head.isEmpty { out.append(head) }
            buffer = tail
            lastSoftBoundaryIndexInBuffer = nil
        }

        func isAsciiLetterOrDigit(_ ch: Character) -> Bool {
            guard let v = ch.unicodeScalars.first?.value else { return false }
            return (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
        }

        func isLikelyAbbreviationDot(at index: Int) -> Bool {
            // Avoid splitting for things like: "U.S.", "e.g.", "i.e.", "Mr.", "3.14"
            guard index > 0, index + 1 < chars.count else { return false }
            let prev = chars[index - 1]
            let next = chars[index + 1]

            if isAsciiLetterOrDigit(prev) && isAsciiLetterOrDigit(next) {
                return true
            }

            // Also treat digit '.' digit as non-ender (decimal number)
            if prev.isNumber && next.isNumber {
                return true
            }

            return false
        }

        // Sentence-ending punctuation candidates.
        let hardEnders: Set<Character> = ["。", "！", "？", "!", "?", ".", "；", ";"]

        // Postfix punctuation that should belong to the same sentence if it appears right after a hard ender.
        let closers: Set<Character> = ["\"", "'", "”", "’", "」", "』", "】", "]", ")", "）", "】", "》", "〉", "】", "…"]

        // Soft boundaries: we *prefer* to cut here when chunk is too long.
        // (Comma and pause-like punctuation.)
        let softBoundaries: Set<Character> = ["，", ",", "、", "：", ":", "（", "(", "）", ")", "—", "-", " "]

        var i = 0
        while i < chars.count {
            let ch = chars[i]

            // Handle ellipsis: "……" (two U+2026) or "...".
            if ch == "…" {
                buffer.append(ch)
                if i + 1 < chars.count, chars[i + 1] == "…" {
                    buffer.append("…")
                    i += 1
                }
                // Treat ellipsis as ender.
                flushBuffer()
                i += 1
                continue
            }

            if ch == "." {
                buffer.append(ch)

                // If this dot is part of abbreviation/number, don't treat as ender.
                if isLikelyAbbreviationDot(at: i) {
                    if softBoundaries.contains(ch) {
                        lastSoftBoundaryIndexInBuffer = buffer.count
                    }
                    i += 1
                    continue
                }

                // If it's "..." treat as ellipsis ender.
                if i + 2 < chars.count, chars[i + 1] == ".", chars[i + 2] == "." {
                    buffer.append(".")
                    buffer.append(".")
                    i += 2
                    flushBuffer()
                    i += 1
                    continue
                }

                // Single dot: treat as hard ender.
                // Also swallow consecutive punctuation + closing quotes/brackets.
                i = swallowPostfix(chars: chars, startIndex: i + 1, buffer: &buffer, closers: closers)
                flushBuffer()
                i += 1
                continue
            }

            buffer.append(ch)

            if softBoundaries.contains(ch) {
                lastSoftBoundaryIndexInBuffer = buffer.count
            }

            // Hard ender handling (except '.' which we already treated specially).
            if hardEnders.contains(ch) {
                // Consume consecutive enders like "？！" "!!" and closing quotes/brackets like "。”"
                i = swallowPostfix(chars: chars, startIndex: i + 1, buffer: &buffer, closers: closers)
                flushBuffer()
                i += 1
                continue
            }

            // Length-based flush: prefer soft boundary.
            if buffer.count >= maxChunkLength {
                if lastSoftBoundaryIndexInBuffer != nil {
                    flushAtLastSoftBoundary()
                } else {
                    flushBuffer()
                }
            }

            i += 1
        }

        flushBuffer()
        return out
    }

    /// Swallow consecutive punctuations and closing quotes/brackets into the current buffer.
    /// Returns the last consumed index (relative to original string indices).
    private static func swallowPostfix(
        chars: [Character],
        startIndex: Int,
        buffer: inout String,
        closers: Set<Character>
    ) -> Int {
        var j = startIndex

        // Also swallow repeated hard enders like "!!" or "？！"
        let extraEnders: Set<Character> = ["。", "！", "？", "!", "?", "；", ";"]

        while j < chars.count {
            let c = chars[j]

            // Consume consecutive enders.
            if extraEnders.contains(c) {
                buffer.append(c)
                j += 1
                continue
            }

            // Consume closers right after the end.
            if closers.contains(c) {
                buffer.append(c)
                j += 1
                continue
            }

            // Consume trailing whitespace.
            if c == " " || c == "\t" {
                buffer.append(c)
                j += 1
                continue
            }

            break
        }

        return j - 1
    }
}
