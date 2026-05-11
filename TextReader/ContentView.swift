//
//  ContentView.swift
//  TextReader
//
//  Created by Ren, Ren (133) on 2026/4/21.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var textToRead = ""
    @State private var pagedDocument: PagedDocument = .empty
    @State private var currentPageIndex = 0
    @State private var textViewResetToken = 0
    @State private var pageJumpText = "1"
    @State private var isShowingFilePicker = false
    @State private var isShowingPinyinOverridePicker = false
    @State private var isShowingSettings = false
    @StateObject private var readerSettings: ReaderSettings
    @StateObject private var speechManager: SpeechManager
    @StateObject private var pinyinOverrideStore: ExternalPinyinOverrideStore
    @State private var isExportingAudio = false
    @State private var exportResultTitle = ""
    @State private var exportResultMessage = ""
    @State private var isShowingExportResult = false
    @State private var overrideResultTitle = ""
    @State private var overrideResultMessage = ""
    @State private var isShowingOverrideResult = false
    @State private var fileLoadResultTitle = ""
    @State private var fileLoadResultMessage = ""
    @State private var isShowingFileLoadResult = false
    @State private var jumpTopageIndexText = "跳转"

    @State private var isEditorFocused = false

    private var trimmedText: String {
        textToRead.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentPage: ReaderPage? {
        pagedDocument.page(at: currentPageIndex)
    }

    private var currentPageText: String {
        currentPage?.text ?? ""
    }

    private var trimmedCurrentPageText: String {
        currentPageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentPageTextBinding: Binding<String> {
        Binding(
            get: { currentPageText },
            set: { updateCurrentPageText($0) }
        )
    }

    private var primaryButtonTitle: String {
        switch speechManager.speechState {
        case .idle:
            return "朗读"
        case .reading:
            return "暂停"
        case .paused:
            return "继续"
        }
    }

    private var engineDescription: String {
        readerSettings.backend.displayName
    }

    private var playbackSourceDescription: String? {
        speechManager.playbackSource?.displayName
    }

    private var pinyinOverrideStatusText: String? {
        guard let loaded = pinyinOverrideStore.loadedOverride else { return nil }
        let suffix = loaded.matches(text: trimmedText)
            ? "当前文本已匹配，将优先使用外部拼音。"
            : "仅在文本与覆盖文件里的 text 完全一致时生效。"
        return "拼音覆盖：\(loaded.fileURL.lastPathComponent) · \(suffix)"
    }

    private var pinyinOverrideMismatchDiagnostic: TextMismatchDiagnostic? {
        pinyinOverrideStore.mismatchDiagnostic(for: textToRead)
    }

    private var editorHighlightedRanges: [NSRange] {
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

    private var canGoToPreviousPage: Bool {
        currentPageIndex > 0
    }

    private var canGoToNextPage: Bool {
        currentPageIndex + 1 < pagedDocument.pageCount
    }

    private var pageIndicatorText: String {
        let current = pagedDocument.pageCount == 0 ? 0 : currentPageIndex + 1
        return "第 \(current) / \(pagedDocument.pageCount) 页"
    }

    private var compactPageCounterText: String {
        let current = pagedDocument.pageCount == 0 ? 0 : currentPageIndex + 1
        return "\(current)/\(pagedDocument.pageCount)"
    }

    private var enteredPageIndex: Int? {
        guard pagedDocument.pageCount > 0 else { return nil }
        let trimmed = pageJumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmed), pageNumber >= 1 else { return nil }
        return min(max(pageNumber - 1, 0), pagedDocument.pageCount - 1)
    }

    private var canJumpToEnteredPage: Bool {
        guard let enteredPageIndex else { return false }
        return enteredPageIndex != currentPageIndex
    }

    private let placeholderText = "在这里输入文本或从文件中加载。"
    private let importableTextTypes = DocumentTextExtractor.supportedContentTypes

    private let editorFont: Font = .system(.body, design: .default)
    private let editorLineSpacing: CGFloat = 6
    private let compactSectionSpacing: CGFloat = 14
    private let compactCardCornerRadius: CGFloat = 16
    private let compactButtonHeight: CGFloat = 36
    private let compactShortButtonWidth: CGFloat = 64
    private let compactLongButtonWidth: CGFloat = 70
    private let compactJumpControlHeight: CGFloat = 30
    private let compactPageFieldWidth: CGFloat = 48
    private let regularPageFieldWidth: CGFloat = 40
    private let regularPageJumpControlsWidth: CGFloat = 190
    private let compactJumpRowLeadingInset: CGFloat = 6
    private let compactBottomActionButtonHeight: CGFloat = 30
    private let compactBottomActionRowLeadingInset: CGFloat = 10

    private var usesCompactLayout: Bool {
#if canImport(UIKit)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    init(speechManager: SpeechManager? = nil, readerSettings: ReaderSettings? = nil) {
        let resolvedSettings = readerSettings ?? ReaderSettings()
        _readerSettings = StateObject(wrappedValue: resolvedSettings)
        _pinyinOverrideStore = StateObject(wrappedValue: ExternalPinyinOverrideStore.shared)

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            let manager = speechManager ?? SpeechManager(engine: MockTTSEngine())
            _speechManager = StateObject(wrappedValue: manager)
        } else {
            let manager = speechManager ?? SpeechManager(settings: resolvedSettings)
            _speechManager = StateObject(wrappedValue: manager)
        }
    }

    var body: some View {
        VStack(spacing: usesCompactLayout ? compactSectionSpacing : 16) {
            if usesCompactLayout {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("文本阅读器")
                                .font(.title2.weight(.semibold))

                            Text(engineDescription)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        VStack(spacing: 6) {
                            Button {
                                isShowingSettings = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 48, height: 30)
                            }
#if canImport(UIKit)
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemFill))
                            )
#else
                            .buttonStyle(.plain)
#endif

                            Text(compactPageCounterText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }

                    if let playbackSourceDescription, speechManager.isPlaybackActive {
                        Text("当前句：\(playbackSourceDescription)")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
            } else {
                HStack(alignment: .top) {
                    Spacer()

                    VStack(spacing: 6) {
                        Text("文本阅读器")
                            .font(.largeTitle)
                        Text(engineDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let playbackSourceDescription, speechManager.isPlaybackActive {
                            Text("当前句：\(playbackSourceDescription)")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    VStack(spacing: 1) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

#if canImport(AppKit)
                        Text(compactPageCounterText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
#endif
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            ZStack(alignment: .topLeading) {
                if trimmedText.isEmpty && !isEditorFocused {
                    Text(placeholderText)
                        .font(editorFont)
                        .foregroundStyle(.secondary)
                        .lineSpacing(editorLineSpacing)
                        .padding(.top, 18)
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .allowsHitTesting(false)
                }

#if canImport(UIKit)
                ReadOnlyTextView(
                    text: currentPageTextBinding,
                    isEditable: !speechManager.isPlaybackActive,
                    font: UIFont.preferredFont(forTextStyle: .body),
                    textColor: UIColor.label,
                    backgroundColor: .clear,
                    lineSpacing: editorLineSpacing,
                    highlightedRanges: editorHighlightedRanges,
                    isFocused: $isEditorFocused,
                    scrollResetToken: textViewResetToken
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
#elseif canImport(AppKit)
                ReadOnlyTextView(
                    text: currentPageTextBinding,
                    isEditable: !speechManager.isPlaybackActive,
                    font: NSFont.preferredFont(forTextStyle: .body),
                    textColor: NSColor.labelColor,
                    backgroundColor: .clear,
                    lineSpacing: editorLineSpacing,
                    highlightedRanges: editorHighlightedRanges,
                    isFocused: $isEditorFocused,
                    scrollResetToken: textViewResetToken
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
#else
                TextEditor(text: currentPageTextBinding)
                    .font(editorFont)
                    .lineSpacing(editorLineSpacing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
#endif
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !speechManager.isPlaybackActive {
                    isEditorFocused = true
                }
            }
            .frame(minHeight: 220, maxHeight: 360)
#if canImport(UIKit)
            .background(Color(UIColor.secondarySystemBackground))
#elseif canImport(AppKit)
            .background(Color(NSColor.textBackgroundColor))
#endif
            .clipShape(RoundedRectangle(cornerRadius: usesCompactLayout ? compactCardCornerRadius : 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: usesCompactLayout ? compactCardCornerRadius : 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(usesCompactLayout ? 0.04 : 0.06), radius: usesCompactLayout ? 6 : 8, x: 0, y: 2)
            .padding(.top, usesCompactLayout ? 2 : 5)

            Group {
                if usesCompactLayout {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 2) {
                            HStack(spacing: 8) {
                                compactPaginationButton("首页", minWidth: compactShortButtonWidth) {
                                    goToFirstPage()
                                }
                                .disabled(!canGoToPreviousPage)
                                .keyboardShortcut(.leftArrow, modifiers: [.command])

                                compactPaginationButton("上一页", minWidth: compactLongButtonWidth) {
                                    goToPreviousPage()
                                }
                                .disabled(!canGoToPreviousPage)
                                .keyboardShortcut(.leftArrow, modifiers: [.option])
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            compactPaginationButton(primaryButtonTitle, isPrimary: true) {
                                switch speechManager.speechState {
                                case .idle:
                                    speechManager.startReading(text: currentPageText)
                                case .reading:
                                    speechManager.pauseReading()
                                case .paused:
                                    speechManager.resumeReading()
                                }
                            }
                            .disabled(speechManager.speechState == .idle && trimmedCurrentPageText.isEmpty)
                            .layoutPriority(1)

                            HStack(spacing: 8) {
                                compactPaginationButton("下一页", minWidth: compactLongButtonWidth) {
                                    goToNextPage()
                                }
                                .disabled(!canGoToNextPage)
                                .keyboardShortcut(.rightArrow, modifiers: [.option])

                                compactPaginationButton("末页") {
                                    goToLastPage()
                                }
                                .disabled(!canGoToNextPage)
                                .keyboardShortcut(.rightArrow, modifiers: [.command])
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 9) {
                                compactPageJumpField()

                                compactJumpButton()
                                    .disabled(!canJumpToEnteredPage)

                                Spacer(minLength: 8)

                                pageCharacterCountLabel()
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.leading, compactJumpRowLeadingInset)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Button("首页") {
                            goToFirstPage()
                        }
                        .disabled(!canGoToPreviousPage)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])

                        Button("上一页") {
                            goToPreviousPage()
                        }
                        .disabled(!canGoToPreviousPage)
                        .keyboardShortcut(.leftArrow, modifiers: [.option])

                        Button(primaryButtonTitle) {
                            switch speechManager.speechState {
                            case .idle:
                                speechManager.startReading(text: currentPageText)
                            case .reading:
                                speechManager.pauseReading()
                            case .paused:
                                speechManager.resumeReading()
                            }
                        }
                        .disabled(speechManager.speechState == .idle && trimmedCurrentPageText.isEmpty)

                        Button("下一页") {
                            goToNextPage()
                        }
                        .disabled(!canGoToNextPage)
                        .keyboardShortcut(.rightArrow, modifiers: [.option])

                        regularPageJumpControlsGroup()

                        Button("末页") {
                            goToLastPage()
                        }
                        .disabled(!canGoToNextPage)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, usesCompactLayout ? 16 : 4)

            Group {
                if usesCompactLayout {
                    VStack(spacing: 10) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                compactBottomActionButton("加载文件") {
                                    presentTextFilePicker()
                                }
                                .disabled(speechManager.isPlaybackActive)

                                compactBottomActionButton("加载拼音 JSON") {
                                    isShowingPinyinOverridePicker = true
                                }
                                .disabled(speechManager.isPlaybackActive)

                                if pinyinOverrideStore.loadedOverride != nil {
                                    compactBottomActionButton("清除拼音覆盖") {
                                        pinyinOverrideStore.clear()
                                    }
                                    .disabled(speechManager.isPlaybackActive)
                                }

                                compactBottomActionButton(isExportingAudio ? "导出中…" : "导出音频", prominent: true) {
                                    exportComparisonAudio()
                                }
                                .disabled(trimmedText.isEmpty || speechManager.isPlaybackActive || isExportingAudio)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, compactBottomActionRowLeadingInset)
                        }

                        HStack(spacing: 10) {
                            if speechManager.isPlaybackActive {
                                Button("停止") {
                                    speechManager.stopReading()
                                }
                                .frame(maxWidth: .infinity)
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack {
                        Button("加载文件") {
                            presentTextFilePicker()
                        }
                        .padding()
                        .disabled(speechManager.isPlaybackActive)

                        Button("加载拼音 JSON") {
                            isShowingPinyinOverridePicker = true
                        }
                        .padding()
                        .disabled(speechManager.isPlaybackActive)

                        if pinyinOverrideStore.loadedOverride != nil {
                            Button("清除拼音覆盖") {
                                pinyinOverrideStore.clear()
                            }
                            .padding()
                            .disabled(speechManager.isPlaybackActive)
                        }

                        Button(isExportingAudio ? "导出中…" : "导出音频") {
                            exportComparisonAudio()
                        }
                        .padding()
                        .disabled(trimmedText.isEmpty || speechManager.isPlaybackActive || isExportingAudio)

                        if speechManager.isPlaybackActive {
                            Button("停止") {
                                speechManager.stopReading()
                            }
                            .padding()
                        }
                    }
                }
            }

            if let pinyinOverrideStatusText {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pinyinOverrideStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let mismatch = pinyinOverrideMismatchDiagnostic {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("不匹配定位：\(mismatch.summary)")
                                .foregroundStyle(.red)
                            Text("当前文本：\(mismatch.currentTextExcerpt)")
                            Text("JSON text：\(mismatch.overrideTextExcerpt)")
                        }
                        .font(.caption.monospaced())
                        .padding(8)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .onChange(of: speechManager.isPlaybackActive) { _, isActive in
            if isActive {
                isEditorFocused = false
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            ReaderSettingsView(settings: readerSettings)
#if canImport(UIKit)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
#endif
        }
        .alert(exportResultTitle, isPresented: $isShowingExportResult) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(exportResultMessage)
        }
        .alert(overrideResultTitle, isPresented: $isShowingOverrideResult) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(overrideResultMessage)
        }
        .alert(fileLoadResultTitle, isPresented: $isShowingFileLoadResult) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(fileLoadResultMessage)
        }
        .fileImporter(isPresented: $isShowingFilePicker, allowedContentTypes: importableTextTypes) { result in
            switch result {
            case .success(let url):
                handleTextFileImport(url)
            case .failure(let error):
                fileLoadResultTitle = "加载失败"
                fileLoadResultMessage = "文件选择失败：\(error.localizedDescription)"
                isShowingFileLoadResult = true
            }
        }
        .fileImporter(isPresented: $isShowingPinyinOverridePicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let startedAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if startedAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let loaded = try pinyinOverrideStore.load(from: url)
                    overrideResultTitle = "拼音覆盖已加载"
                    if loaded.matches(text: trimmedText) {
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
            case .failure(let error):
                overrideResultTitle = "加载失败"
                overrideResultMessage = "拼音 JSON 选择失败：\(error.localizedDescription)"
                isShowingOverrideResult = true
            }
        }
    }

    private func exportComparisonAudio() {
        guard !isExportingAudio else { return }

        isExportingAudio = true
        Task {
            do {
                let exportedAudio = try await speechManager.exportCurrentTextAudio(text: currentPageText)
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

    private func presentTextFilePicker() {
#if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.title = "选择文档"
        panel.message = "请选择要加载到编辑器中的文档。支持 TXT、Markdown、JSON、CSV、XML、HTML、RTF、Word、ODT、PDF 等常见格式。"
        panel.prompt = "加载"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = importableTextTypes

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        handleTextFileImport(url)
#else
        isShowingFilePicker = true
#endif
    }

    private func handleTextFileImport(_ url: URL) {
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


    private func updateCurrentPageText(_ newPageText: String) {
        guard let currentPage else {
            applyDocumentText(newPageText, preferredPageIndex: 0)
            return
        }

        var updatedText = textToRead
        updatedText.replaceSubrange(currentPage.range, with: newPageText)
        applyDocumentText(updatedText, anchorUTF16Location: currentPage.utf16Range.location)
    }

    private func applyDocumentText(
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

    private func goToPreviousPage() {
        guard canGoToPreviousPage else { return }
        changePage(to: currentPageIndex - 1)
    }

    private func goToFirstPage() {
        guard canGoToPreviousPage else { return }
        changePage(to: 0)
    }

    private func goToNextPage() {
        guard canGoToNextPage else { return }
        changePage(to: currentPageIndex + 1)
    }

    private func goToLastPage() {
        guard canGoToNextPage else { return }
        changePage(to: pagedDocument.pageCount - 1)
    }

    private func changePage(to index: Int) {
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

    private func jumpToEnteredPage() {
        guard let enteredPageIndex else {
            syncPageJumpField()
            return
        }

        changePage(to: enteredPageIndex)
    }

    private func syncPageJumpField() {
        let displayPage = pagedDocument.pageCount == 0 ? 1 : currentPageIndex + 1
        pageJumpText = String(displayPage)
    }

    @ViewBuilder
    private func compactPageJumpField() -> some View {
        TextField("页码", text: $pageJumpText)
            .textFieldStyle(.plain)
            .frame(width: compactPageFieldWidth, height: compactJumpControlHeight)
            .font(.callout.monospacedDigit())
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
#if canImport(UIKit)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
#else
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
#endif
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.22), lineWidth: 1)
            )
            .onSubmit {
                jumpToEnteredPage()
            }
    }

    @ViewBuilder
    private func pageCharacterCountLabel() -> some View {
        if let currentPage {
            Text("本页 \(currentPage.text.count) 字")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func regularPageJumpControlsGroup() -> some View {
        HStack(spacing: 8) {
            TextField("页码", text: $pageJumpText)
#if canImport(AppKit)
                .textFieldStyle(.roundedBorder)
                .frame(width: regularPageFieldWidth)
#else
                .textFieldStyle(.roundedBorder)
                .frame(width: regularPageFieldWidth)
#endif
                .multilineTextAlignment(.trailing)
                .onSubmit {
                    jumpToEnteredPage()
                }

            Button(jumpTopageIndexText) {
                jumpToEnteredPage()
            }
            .disabled(!canJumpToEnteredPage)
            .frame(width: compactLongButtonWidth)

            pageCharacterCountLabel()
        }
        .frame(width: regularPageJumpControlsWidth, alignment: .trailing)
    }

    @ViewBuilder
    private func compactJumpButton() -> some View {
#if canImport(UIKit)
        Button(jumpTopageIndexText) {
            jumpToEnteredPage()
        }
        .font(.callout.weight(.medium))
        .frame(width: compactLongButtonWidth, height: compactJumpControlHeight)
        .buttonStyle(.bordered)
        .controlSize(.small)
#else
        Button(jumpTopageIndexText) {
            jumpToEnteredPage()
        }
        .font(.callout.weight(.medium))
        .frame(width: compactLongButtonWidth, height: compactJumpControlHeight)
#endif
    }

    @ViewBuilder
    private func compactBottomActionButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
#if canImport(UIKit)
        if prominent {
            Button(title, action: action)
                .font(.footnote.weight(.medium))
                .frame(minHeight: compactBottomActionButtonHeight)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else {
            Button(title, action: action)
                .font(.footnote.weight(.medium))
                .frame(minHeight: compactBottomActionButtonHeight)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
#else
        Button(title, action: action)
            .font(.footnote.weight(.medium))
            .frame(minHeight: compactBottomActionButtonHeight)
#endif
    }

    @ViewBuilder
    private func compactPaginationButton(_ title: String, isPrimary: Bool = false, minWidth: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        let resolvedMinWidth = minWidth ?? (isPrimary ? 72 : 64)
#if canImport(UIKit)
        if isPrimary {
            Button(title, action: action)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: resolvedMinWidth, minHeight: compactButtonHeight)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        } else {
            Button(title, action: action)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: resolvedMinWidth, minHeight: compactButtonHeight)
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
#else
        Button(title, action: action)
            .font(.callout.weight(isPrimary ? .semibold : .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: resolvedMinWidth, minHeight: compactButtonHeight)
#endif
    }
}


#Preview {
    ContentView(speechManager: SpeechManager(engine: MockTTSEngine()), readerSettings: ReaderSettings())
}
