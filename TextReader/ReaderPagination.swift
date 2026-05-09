import Foundation

struct ReaderPage: Identifiable, Equatable {
    let id: Int
    let range: Range<String.Index>
    let utf16Range: NSRange
    let text: String
}

struct PagedDocument: Equatable {
    let fullText: String
    let pages: [ReaderPage]

    static let empty = PagedDocument(fullText: "", pages: [
        ReaderPage(id: 0, range: "".startIndex..<("".startIndex), utf16Range: NSRange(location: 0, length: 0), text: "")
    ])

    var pageCount: Int { pages.count }

    func page(at index: Int) -> ReaderPage? {
        guard pages.indices.contains(index) else { return nil }
        return pages[index]
    }

    func clampedPageIndex(_ index: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        return min(max(index, 0), pages.count - 1)
    }

    func pageIndex(containingUTF16Location location: Int) -> Int {
        guard !pages.isEmpty else { return 0 }

        let clampedLocation = max(0, min(location, (fullText as NSString).length))
        for (index, page) in pages.enumerated() {
            let lowerBound = page.utf16Range.location
            let upperBound = page.utf16Range.location + page.utf16Range.length
            if clampedLocation >= lowerBound && clampedLocation < upperBound {
                return index
            }
        }

        if let lastIndex = pages.indices.last,
           clampedLocation >= pages[lastIndex].utf16Range.location {
            return lastIndex
        }

        return 0
    }
}

enum ReaderPaginator {
    private static let preferredPageLength = 900
    private static let maximumPageLength = 1200
    private static let minimumPageLength = 420
    private static let paragraphBreaks: Set<Character> = ["\n"]
    private static let sentenceBreaks: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", ":", "："]
    private static let clauseBreaks: Set<Character> = ["，", ",", "、"]

    static func paginate(_ text: String) -> PagedDocument {
        guard !text.isEmpty else {
            return .empty
        }

        let characters = Array(text)
        let indices = Array(text.indices)
        var pages: [ReaderPage] = []
        var startOffset = 0
        var pageID = 0

        while startOffset < characters.count {
            let endOffset = nextPageEndOffset(in: characters, startOffset: startOffset)
            let startIndex = indices[startOffset]
            let endIndex = endOffset < indices.count ? indices[endOffset] : text.endIndex
            let range = startIndex..<endIndex
            let pageText = String(text[range])
            let utf16Range = NSRange(range, in: text)

            pages.append(
                ReaderPage(
                    id: pageID,
                    range: range,
                    utf16Range: utf16Range,
                    text: pageText
                )
            )

            pageID += 1
            startOffset = max(endOffset, startOffset + 1)
        }

        return PagedDocument(fullText: text, pages: pages)
    }

    private static func nextPageEndOffset(in characters: [Character], startOffset: Int) -> Int {
        let remaining = characters.count - startOffset
        if remaining <= maximumPageLength {
            return characters.count
        }

        let preferredEnd = min(startOffset + preferredPageLength, characters.count)
        let minimumEnd = min(startOffset + minimumPageLength, characters.count)
        let maximumEnd = min(startOffset + maximumPageLength, characters.count)

        if let breakOffset = findBreakOffset(in: characters, from: preferredEnd, downTo: minimumEnd, breakSet: paragraphBreaks) {
            return breakOffset
        }
        if let breakOffset = findBreakOffset(in: characters, from: preferredEnd, through: maximumEnd, breakSet: paragraphBreaks) {
            return breakOffset
        }
        if let breakOffset = findBreakOffset(in: characters, from: preferredEnd, downTo: minimumEnd, breakSet: sentenceBreaks) {
            return breakOffset
        }
        if let breakOffset = findBreakOffset(in: characters, from: preferredEnd, through: maximumEnd, breakSet: sentenceBreaks) {
            return breakOffset
        }
        if let breakOffset = findBreakOffset(in: characters, from: preferredEnd, downTo: minimumEnd, breakSet: clauseBreaks) {
            return breakOffset
        }
        if let breakOffset = findBreakOffset(in: characters, from: preferredEnd, through: maximumEnd, breakSet: clauseBreaks) {
            return breakOffset
        }

        return maximumEnd
    }

    private static func findBreakOffset(
        in characters: [Character],
        from start: Int,
        downTo minimum: Int,
        breakSet: Set<Character>
    ) -> Int? {
        guard minimum < start else { return nil }

        for offset in stride(from: start - 1, through: minimum, by: -1) {
            if breakSet.contains(characters[offset]) {
                return offset + 1
            }
        }
        return nil
    }

    private static func findBreakOffset(
        in characters: [Character],
        from start: Int,
        through maximum: Int,
        breakSet: Set<Character>
    ) -> Int? {
        guard start < maximum else { return nil }

        for offset in start..<maximum {
            if breakSet.contains(characters[offset]) {
                return offset + 1
            }
        }
        return nil
    }
}
