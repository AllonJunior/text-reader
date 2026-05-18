//
//  ContentView.swift
//  TextReader
//
//  Created by Ren, Ren (133) on 2026/4/21.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State var textToRead = ""
    @State var pagedDocument: PagedDocument = .empty
    @State var currentPageIndex = 0
    @State var textViewResetToken = 0
    @State var pageJumpText = "1"
    @State var isShowingFilePicker = false
    @State var isShowingPinyinOverridePicker = false
    @State var isShowingSettings = false
    @StateObject var readerSettings: ReaderSettings
    @StateObject var speechManager: SpeechManager
    @StateObject var pinyinOverrideStore: ExternalPinyinOverrideStore
    @State var isExportingAudio = false
    @State var exportResultTitle = ""
    @State var exportResultMessage = ""
    @State var isShowingExportResult = false
    @State var overrideResultTitle = ""
    @State var overrideResultMessage = ""
    @State var isShowingOverrideResult = false
    @State var fileLoadResultTitle = ""
    @State var fileLoadResultMessage = ""
    @State var isShowingFileLoadResult = false
    @State var isEditorFocused = false

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
        let state = screenState

        return VStack(spacing: usesCompactLayout ? ContentViewMetrics.compactSectionSpacing : 16) {
            ContentViewHeader(state: state, usesCompactLayout: usesCompactLayout) {
                isShowingSettings = true
            }

            ContentViewEditorCard(
                state: state,
                text: currentPageTextBinding,
                isEditorFocused: $isEditorFocused,
                usesCompactLayout: usesCompactLayout,
                placeholderText: placeholderText,
                scrollResetToken: textViewResetToken
            )

            ContentViewPaginationSection(state: state, usesCompactLayout: usesCompactLayout, pageJumpText: $pageJumpText) {
                goToFirstPage()
            } onPrevious: {
                goToPreviousPage()
            } onPrimary: {
                handlePrimaryAction()
            } onNext: {
                goToNextPage()
            } onLast: {
                goToLastPage()
            } onJump: {
                jumpToEnteredPage()
            }
            .padding(.horizontal, usesCompactLayout ? 16 : 4)

            ContentViewBottomActionsSection(
                state: state,
                usesCompactLayout: usesCompactLayout,
                isExportingAudio: isExportingAudio,
                canClearOverride: pinyinOverrideStore.loadedOverride != nil,
                onLoadFile: presentTextFilePicker,
                onLoadOverride: { isShowingPinyinOverridePicker = true },
                onClearOverride: { pinyinOverrideStore.clear() },
                onExport: exportComparisonAudio,
                onStop: { speechManager.stopReading() }
            )

            if let statusText = state.pinyinOverrideStatusText {
                ContentViewOverrideStatusSection(
                    statusText: statusText,
                    mismatch: state.pinyinOverrideMismatchDiagnostic
                )
            }
        }
        .padding()
        .onChange(of: speechManager.isPlaybackActive) { _, isActive in
            if isActive { isEditorFocused = false }
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
        .fileImporter(isPresented: $isShowingFilePicker, allowedContentTypes: importableTextTypes) {
            handleTextFileImportResult($0)
        }
        .fileImporter(isPresented: $isShowingPinyinOverridePicker, allowedContentTypes: [.json]) {
            handlePinyinOverrideImportResult($0)
        }
    }
}


#Preview {
    ContentView(speechManager: SpeechManager(engine: MockTTSEngine()), readerSettings: ReaderSettings())
}
