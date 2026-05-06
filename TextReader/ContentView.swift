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
    @State private var textToRead = ""
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

    @State private var isEditorFocused = false

    private var trimmedText: String {
        textToRead.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var primaryButtonTitle: String {
        switch speechManager.speechState {
        case .idle:
            return "开始阅读"
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
        guard let range = pinyinOverrideMismatchDiagnostic?.currentTextHighlightRange else {
            return []
        }
        return [range]
    }

    private let placeholderText = "在这里输入文本或从文件中加载。"
    private let importableTextTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let utf8PlainText = UTType(filenameExtension: "txt") {
            types.append(utf8PlainText)
        }
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return Array(Set(types))
    }()

    private let editorFont: Font = .system(.body, design: .default)
    private let editorLineSpacing: CGFloat = 6

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
        VStack(spacing: 16) {
            HStack {
                Spacer()

                VStack(spacing: 4) {
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

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 8)

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
                    text: $textToRead,
                    isEditable: !speechManager.isPlaybackActive,
                    font: UIFont.preferredFont(forTextStyle: .body),
                    textColor: UIColor.label,
                    backgroundColor: .clear,
                    lineSpacing: editorLineSpacing,
                    highlightedRanges: editorHighlightedRanges,
                    isFocused: $isEditorFocused
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
#elseif canImport(AppKit)
                ReadOnlyTextView(
                    text: $textToRead,
                    isEditable: !speechManager.isPlaybackActive,
                    font: NSFont.preferredFont(forTextStyle: .body),
                    textColor: NSColor.labelColor,
                    backgroundColor: .clear,
                    lineSpacing: editorLineSpacing,
                    highlightedRanges: editorHighlightedRanges,
                    isFocused: $isEditorFocused
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
#else
                TextEditor(text: $textToRead)
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.top, 5)

            HStack {
                Button("从文件加载") {
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

                Button(isExportingAudio ? "导出中…" : "导出对比音频") {
                    exportComparisonAudio()
                }
                .padding()
                .disabled(trimmedText.isEmpty || speechManager.isPlaybackActive || isExportingAudio)

                Button(primaryButtonTitle) {
                    switch speechManager.speechState {
                    case .idle:
                        speechManager.startReading(text: textToRead)
                    case .reading:
                        speechManager.pauseReading()
                    case .paused:
                        speechManager.resumeReading()
                    }
                }
                .padding()
                .disabled(speechManager.speechState == .idle && trimmedText.isEmpty)

                if speechManager.isPlaybackActive {
                    Button("停止") {
                        speechManager.stopReading()
                    }
                    .padding()
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
                let exportedAudio = try await speechManager.exportCurrentTextAudio(text: textToRead)
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
        panel.title = "选择文本文件"
        panel.message = "请选择要加载到编辑器中的文本文件。"
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
            textToRead = try loadTextFileContents(from: url)
        } catch {
            fileLoadResultTitle = "加载失败"
            fileLoadResultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isShowingFileLoadResult = true
        }
    }

    private func loadTextFileContents(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .unicode,
            .init(cfEncoding: .GB_18030_2000),
            .init(cfEncoding: .big5),
            .init(cfEncoding: .EUC_CN),
        ]

        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return ReaderTextCanonicalizer.normalizeLineEndingsAndBOM(string)
            }
        }

        throw TextFileLoadError.unsupportedEncoding(url.lastPathComponent)
    }
}

private enum TextFileLoadError: LocalizedError {
    case unsupportedEncoding(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding(let filename):
            return "无法读取文件“\(filename)”。目前支持 UTF-8 / UTF-16 / GB18030 / Big5 / EUC-CN 等常见文本编码。"
        }
    }
}

private extension String.Encoding {
    init(cfEncoding: CFStringEncodings) {
        self = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue)))
    }
}

#Preview {
    ContentView(speechManager: SpeechManager(engine: MockTTSEngine()), readerSettings: ReaderSettings())
}
