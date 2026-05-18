//
//  ContentView+Support.swift
//  TextReader
//
//  Summary: Provides ContentView helper state accessors and actions for import, export, and pagination.
//  Author: Ren, Ren
//  Modified: 2026/5/18
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

extension ContentView {
    var placeholderText: String {
        "在这里输入文本或从文件中加载。"
    }

    var importableTextTypes: [UTType] {
        DocumentTextExtractor.supportedContentTypes
    }

    var usesCompactLayout: Bool {
#if canImport(UIKit)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    var screenState: ContentViewScreenState {
        ContentViewScreenState(
            textToRead: textToRead,
            pagedDocument: pagedDocument,
            currentPageIndex: currentPageIndex,
            pageJumpText: pageJumpText,
            speechState: speechManager.speechState,
            playbackSourceDescription: speechManager.playbackSource?.displayName,
            isPlaybackActive: speechManager.isPlaybackActive,
            backendDisplayName: readerSettings.backend.displayName,
            loadedOverride: pinyinOverrideStore.loadedOverride,
            pinyinOverrideMismatchDiagnostic: pinyinOverrideStore.mismatchDiagnostic(for: textToRead)
        )
    }

    var currentPageTextBinding: Binding<String> {
        Binding(
            get: { pagedDocument.page(at: currentPageIndex)?.text ?? "" },
            set: { updateCurrentPageText($0) }
        )
    }

    func handlePrimaryAction() {
        switch speechManager.speechState {
        case .idle:
            speechManager.startReading(text: screenState.currentPageText)
        case .reading:
            speechManager.pauseReading()
        case .paused:
            speechManager.resumeReading()
        }
    }

    func handleTextFileImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            handleTextFileImport(url)
        case .failure(let error):
            fileLoadResultTitle = "加载失败"
            fileLoadResultMessage = "文件选择失败：\(error.localizedDescription)"
            isShowingFileLoadResult = true
        }
    }

    func handlePinyinOverrideImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            handlePinyinOverrideImport(url)
        case .failure(let error):
            overrideResultTitle = "加载失败"
            overrideResultMessage = "拼音 JSON 选择失败：\(error.localizedDescription)"
            isShowingOverrideResult = true
        }
    }

    func exportComparisonAudio() {
        guard !isExportingAudio else { return }

        isExportingAudio = true
        Task {
            do {
                let exportedAudio = try await speechManager.exportCurrentTextAudio(text: screenState.currentPageText)
                exportResultTitle = "导出成功"
                exportResultMessage = "已保存为\(exportedAudio.formatDescription)：\n\(exportedAudio.fileURL.path)"
#if canImport(AppKit)
                NSWorkspace.shared.activateFileViewerSelecting([exportedAudio.fileURL])
#endif
            } catch {
                exportResultTitle = "导出失败"
                exportResultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }

            isExportingAudio = false
            isShowingExportResult = true
        }
    }

    func presentTextFilePicker() {
#if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.title = "选择文档"
        panel.message = "请选择要加载到编辑器中的文档。支持 TXT、Markdown、JSON、CSV、XML、HTML、RTF、Word、ODT、PDF 等常见格式。"
        panel.prompt = "加载"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = importableTextTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleTextFileImport(url)
#else
        isShowingFilePicker = true
#endif
    }

    func handleTextFileImport(_ url: URL) {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let importedText = try DocumentTextExtractor.extractText(from: url)
            applyDocumentText(importedText, preferredPageIndex: 0, resetScrollPosition: true)
        } catch {
            fileLoadResultTitle = "加载失败"
            fileLoadResultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isShowingFileLoadResult = true
        }
    }

    func handlePinyinOverrideImport(_ url: URL) {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let loaded = try pinyinOverrideStore.load(from: url)
            overrideResultTitle = "拼音覆盖已加载"
            if loaded.matches(text: screenState.trimmedText) {
                overrideResultMessage = "已加载：\(loaded.fileURL.lastPathComponent)\n\n当前文本已匹配，接下来导出或朗读会优先使用外部拼音。"
            } else if let mismatch = pinyinOverrideStore.mismatchDiagnostic(for: textToRead) {
                overrideResultMessage = "已加载：\(loaded.fileURL.lastPathComponent)\n\n但当前文本与 JSON 中的 text 不完全一致，只有文本完全匹配时才会生效。\n\n\(mismatch.summary)\n当前文本：\(mismatch.currentTextExcerpt)\nJSON text：\(mismatch.overrideTextExcerpt)"
            } else {
                overrideResultMessage = "已加载：\(loaded.fileURL.lastPathComponent)\n\n但当前文本与 JSON 中的 text 不完全一致，只有文本完全匹配时才会生效。"
            }
        } catch {
            overrideResultTitle = "加载失败"
            overrideResultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isShowingOverrideResult = true
    }

    func updateCurrentPageText(_ newPageText: String) {
        guard let currentPage = pagedDocument.page(at: currentPageIndex) else {
            applyDocumentText(newPageText, preferredPageIndex: 0)
            return
        }

        var updatedText = textToRead
        updatedText.replaceSubrange(currentPage.range, with: newPageText)
        applyDocumentText(updatedText, anchorUTF16Location: currentPage.utf16Range.location)
    }

    func applyDocumentText(
        _ newText: String,
        anchorUTF16Location: Int? = nil,
        preferredPageIndex: Int? = nil,
        resetScrollPosition: Bool = false
    ) {
        textToRead = newText
        pagedDocument = ReaderPaginator.paginate(newText)

        if let preferredPageIndex {
            currentPageIndex = pagedDocument.clampedPageIndex(preferredPageIndex)
        } else if let anchorUTF16Location {
            currentPageIndex = pagedDocument.pageIndex(containingUTF16Location: anchorUTF16Location)
        } else {
            currentPageIndex = 0
        }

        syncPageJumpField()
        if resetScrollPosition {
            textViewResetToken &+= 1
        }
    }

    func goToPreviousPage() {
        guard screenState.canGoToPreviousPage else { return }
        changePage(to: currentPageIndex - 1)
    }

    func goToFirstPage() {
        guard screenState.canGoToPreviousPage else { return }
        changePage(to: 0)
    }

    func goToNextPage() {
        guard screenState.canGoToNextPage else { return }
        changePage(to: currentPageIndex + 1)
    }

    func goToLastPage() {
        guard screenState.canGoToNextPage else { return }
        changePage(to: pagedDocument.pageCount - 1)
    }

    func changePage(to index: Int) {
        let clampedIndex = pagedDocument.clampedPageIndex(index)
        guard clampedIndex != currentPageIndex else { return }

        if speechManager.isPlaybackActive {
            speechManager.stopReading()
        }

        currentPageIndex = clampedIndex
        syncPageJumpField()
        isEditorFocused = false
        textViewResetToken &+= 1
    }

    func jumpToEnteredPage() {
        guard let enteredPageIndex = screenState.enteredPageIndex else {
            syncPageJumpField()
            return
        }

        changePage(to: enteredPageIndex)
    }

    func syncPageJumpField() {
        let displayPage = pagedDocument.pageCount == 0 ? 1 : currentPageIndex + 1
        pageJumpText = String(displayPage)
    }
}
