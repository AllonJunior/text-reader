//
//  ContentViewScreenState.swift
//  TextReader
//
//  Summary: Encapsulates derived UI state for ContentView rendering and interaction.
//  Author: Ren, Ren
//  Modified: 2026/5/18
//

import Foundation

struct ContentViewScreenState {
    let textToRead: String
    let pagedDocument: PagedDocument
    let currentPageIndex: Int
    let pageJumpText: String
    let speechState: SpeechManager.SpeechState
    let playbackSourceDescription: String?
    let isPlaybackActive: Bool
    let backendDisplayName: String
    let loadedOverride: LoadedPinyinOverride?
    let pinyinOverrideMismatchDiagnostic: TextMismatchDiagnostic?

    var trimmedText: String {
        textToRead.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentPage: ReaderPage? {
        pagedDocument.page(at: currentPageIndex)
    }

    var currentPageText: String {
        currentPage?.text ?? ""
    }

    var trimmedCurrentPageText: String {
        currentPageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var primaryButtonTitle: String {
        switch speechState {
        case .idle:
            return "朗读"
        case .reading:
            return "暂停"
        case .paused:
            return "继续"
        }
    }

    var pinyinOverrideStatusText: String? {
        guard let loadedOverride else { return nil }
        let suffix = loadedOverride.matches(text: trimmedText)
            ? "当前文本已匹配，将优先使用外部拼音。"
            : "仅在文本与覆盖文件里的 text 完全一致时生效。"
        return "拼音覆盖：\(loadedOverride.fileURL.lastPathComponent) · \(suffix)"
    }

    var editorHighlightedRanges: [NSRange] {
        guard let mismatchRange = pinyinOverrideMismatchDiagnostic?.currentTextHighlightRange,
              let currentPage else {
            return []
        }

        let intersection = NSIntersectionRange(mismatchRange, currentPage.utf16Range)
        guard intersection.length > 0 else { return [] }

        return [
            NSRange(
                location: intersection.location - currentPage.utf16Range.location,
                length: intersection.length
            )
        ]
    }

    var canGoToPreviousPage: Bool {
        currentPageIndex > 0
    }

    var canGoToNextPage: Bool {
        currentPageIndex + 1 < pagedDocument.pageCount
    }

    var compactPageCounterText: String {
        let current = pagedDocument.pageCount == 0 ? 0 : currentPageIndex + 1
        return "\(current)/\(pagedDocument.pageCount)"
    }

    var enteredPageIndex: Int? {
        guard pagedDocument.pageCount > 0 else { return nil }
        let trimmed = pageJumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmed), pageNumber >= 1 else { return nil }
        return min(max(pageNumber - 1, 0), pagedDocument.pageCount - 1)
    }

    var canJumpToEnteredPage: Bool {
        guard let enteredPageIndex else { return false }
        return enteredPageIndex != currentPageIndex
    }

    var currentPageCharacterCountText: String? {
        currentPage.map { "本页 \($0.text.count) 字" }
    }
}
