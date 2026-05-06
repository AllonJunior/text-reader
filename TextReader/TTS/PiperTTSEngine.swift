import Foundation
@preconcurrency import AVFoundation
#if canImport(AppKit)
import AppKit
#endif

private struct ScopedExportDirectoryAccess {
    let directoryURL: URL
    let stopAccess: () -> Void
}

/// Offline TTS backend for Piper (ONNX Runtime).
///
/// It synthesizes sentence-by-sentence and plays them sequentially.
@MainActor
final class PiperTTSEngine: TTSEngine {
    private static let preferredExportDirectoryURL = URL(
        fileURLWithPath: "/Users/RENREN/Desktop/materials/xcode-workspace/TextReader Exports",
        isDirectory: true
    ).standardizedFileURL
    private static let exportDirectoryBookmarkKey = "textreader.export.directory.bookmark"

    private enum PlaybackMode {
        case none
        case piperBuffer
        case fallbackSystem
    }

    private struct SynthesizedSentenceAudio {
        let samples: [Float]
        let sampleRate: Double
        let syllableCount: Int
    }

    private struct QueuedSentence {
        let text: String
        let explicitTokens: [String]?
        let externalOverrideSourceDescription: String?
    }

    private struct ExportDebugPayload: Codable {
        struct Sentence: Codable {
            let text: String
            let tokens: [String]
            let symbols: [String]
            let phonemeIDs: [Int]
            let usedExternalOverride: Bool
            let externalOverrideSourceDescription: String?
        }

        let text: String
        let lengthScale: Double
        let pinyinMode: PiperPinyinMode
        let sampleRate: Double
        let sentenceCount: Int
        let sentences: [Sentence]
    }

    var onDidStart: (() -> Void)?
    var onDidFinish: (() -> Void)?
    var onDidCancel: (() -> Void)?
    var onPlaybackSourceChanged: ((SpeechPlaybackSource?) -> Void)?

    private(set) var isSpeaking: Bool = false
    private(set) var isPaused: Bool = false

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchNode = AVAudioUnitTimePitch()
    private let fallbackEngine = SystemTTSEngine()
    private var modelSampleRate: Double = 16_000
    private let bypassTimePitchForPiperDiagnostics = false

    private var queue: [QueuedSentence] = []
    private var currentIndex: Int = 0

    private var cancelRequested = false
    private var configuration: SpeechConfiguration = .default
    private var playbackMode: PlaybackMode = .none

    // MARK: - ONNX Runtime

    private var ortSession: OpaquePointer?
    private var ortInputNames: [String] = []
    private var ortOutputNames: [String] = []
    private var voiceConfig: PiperVoiceConfig?

    /// XiaoYa medium (female, more natural)
    private let modelBasename = "zh_CN-xiao_ya-medium.onnx"

    init() {
        // Audio graph is always available (also for Preview / placeholder).
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitchNode)
        reconnectAudioGraph()
        apply(settings: configuration)
        try? audioEngine.start()

        // Never try to load ORT/model in SwiftUI Preview.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        setupOrtIfPossible()
    }

    deinit {
        MainActor.assumeIsolated {
            releaseOrtResources()
        }
    }

    @MainActor
    private func releaseOrtResources() {
        if let ortSession {
            TROrtPiperSessionDestroy(ortSession)
            self.ortSession = nil
        }
        ortInputNames.removeAll()
        ortOutputNames.removeAll()
    }

    private func reconnectAudioGraph() {
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.disconnectNodeOutput(timePitchNode)
        if bypassTimePitchForPiperDiagnostics {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
            logPiper(
                "诊断模式：已旁路 TimePitch。player=\(describeAudioFormat(playerNode.outputFormat(forBus: 0))) " +
                "mixerOut=\(describeAudioFormat(audioEngine.mainMixerNode.outputFormat(forBus: 0)))"
            )
        } else {
            audioEngine.connect(playerNode, to: timePitchNode, format: nil)
            audioEngine.connect(timePitchNode, to: audioEngine.mainMixerNode, format: nil)
            logPiper(
                "音频图已重连。player=\(describeAudioFormat(playerNode.outputFormat(forBus: 0))) " +
                "timePitchIn=\(describeAudioFormat(timePitchNode.inputFormat(forBus: 0))) " +
                "mixerOut=\(describeAudioFormat(audioEngine.mainMixerNode.outputFormat(forBus: 0)))"
            )
        }
    }

    func speak(_ text: String) {
        stop() // cancel any current playback

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let queuedSentences = makeQueuedSentences(for: trimmed)
        guard !queuedSentences.isEmpty else { return }

        queue = queuedSentences
        currentIndex = 0
        cancelRequested = false
        isPaused = false
        playbackMode = .none

        isSpeaking = true
        onDidStart?()

        Task {
            await playQueue()
        }
    }

    func stop() {
        cancelRequested = true
        queue.removeAll()
        currentIndex = 0
        isPaused = false
        playbackMode = .none

        playerNode.stop()
        fallbackEngine.stop()
        onPlaybackSourceChanged?(nil)

        if isSpeaking {
            isSpeaking = false
            onDidCancel?()
        }
    }

    @discardableResult
    func pause() -> Bool {
        guard isSpeaking, !isPaused else { return false }

        let paused: Bool
        switch playbackMode {
        case .piperBuffer:
            playerNode.pause()
            paused = true
        case .fallbackSystem:
            paused = fallbackEngine.pause()
        case .none:
            paused = false
        }

        if paused {
            isPaused = true
        }
        return paused
    }

    @discardableResult
    func resume() -> Bool {
        guard isSpeaking, isPaused else { return false }

        let resumed: Bool
        switch playbackMode {
        case .piperBuffer:
            playerNode.play()
            resumed = true
        case .fallbackSystem:
            resumed = fallbackEngine.resume()
        case .none:
            resumed = false
        }

        if resumed {
            isPaused = false
        }
        return resumed
    }

    func apply(settings: SpeechConfiguration) {
        configuration = settings
        playerNode.volume = Float(settings.volume)
        if bypassTimePitchForPiperDiagnostics {
            timePitchNode.rate = 1.0
            timePitchNode.pitch = 0.0
        } else {
            timePitchNode.rate = Float(settings.rate)
            timePitchNode.pitch = Float((settings.pitch - 1.0) * 1200.0)
        }
        fallbackEngine.apply(settings: settings)
    }

    // MARK: - Playback

    private func playQueue() async {
        guard audioEngine.isRunning else {
            isSpeaking = false
            onDidCancel?()
            return
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        while currentIndex < queue.count {
            if cancelRequested {
                isSpeaking = false
                isPaused = false
                playbackMode = .none
                onPlaybackSourceChanged?(nil)
                onDidCancel?()
                return
            }

            let sentence = queue[currentIndex]
            currentIndex += 1

            // Prefer real Piper synthesis. If it fails, fall back to the system TTS engine
            // instead of collapsing into a near-instant silent placeholder.
            if let buffer = synthesizePCM(for: sentence) {
                playbackMode = .piperBuffer
                onPlaybackSourceChanged?(.piper)
                await withCheckedContinuation { cont in
                    playerNode.scheduleBuffer(buffer, at: nil, options: []) {
                        cont.resume()
                    }
                }
                playbackMode = .none
            } else {
                playbackMode = .fallbackSystem
                onPlaybackSourceChanged?(.systemFallback)
                await speakWithFallback(sentence.text)
                playbackMode = .none
            }
        }

        isSpeaking = false
        isPaused = false
        playbackMode = .none
        onPlaybackSourceChanged?(nil)
        onDidFinish?()
    }

    private func speakWithFallback(_ sentence: String) async {
        await withCheckedContinuation { cont in
            fallbackEngine.onDidStart = nil
            fallbackEngine.onDidFinish = {
                self.fallbackEngine.onDidFinish = nil
                self.fallbackEngine.onDidCancel = nil
                cont.resume()
            }
            fallbackEngine.onDidCancel = {
                self.fallbackEngine.onDidFinish = nil
                self.fallbackEngine.onDidCancel = nil
                cont.resume()
            }
            fallbackEngine.speak(sentence)
        }
    }

    // MARK: - Piper synthesis

    private func logPiper(_ message: String) {
        print("[PiperTTSEngine] \(message)")
    }

    private func consumeErrorMessage(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { TROrtFreeCString(pointer) }
        return String(cString: pointer)
    }

    private func consumeCStringArray(_ array: inout TROrtCStringArray) -> [String] {
        defer { TROrtCStringArrayFree(array) }
        guard let items = array.items, array.count > 0 else { return [] }

        var values: [String] = []
        values.reserveCapacity(Int(array.count))
        for index in 0..<Int(array.count) {
            if let item = items[index] {
                values.append(String(cString: item))
            }
        }
        return values
    }

    private func syllableCount(in symbols: [String]) -> Int {
        symbols.reduce(into: 0) { count, symbol in
            if symbol.count == 1,
               let scalar = symbol.unicodeScalars.first,
               CharacterSet.decimalDigits.contains(scalar) {
                count += 1
            }
        }
    }

    private var chinesePinyinGroupEndSymbols: Set<String> {
        [
            "1", "2", "3", "4", "5",
            "。", ".", "？", "?", "！", "!",
            "—", "…", "、", "，", ",", "：", ":", "；", ";",
            " "
        ]
    }

    private func phonemeIDs(for symbols: [String], config: PiperVoiceConfig, originalText: String) -> [Int64]? {
        guard let bosIDs = config.ids(for: "^"), !bosIDs.isEmpty,
              let eosIDs = config.ids(for: "$"), !eosIDs.isEmpty,
              let padIDs = config.ids(for: "_"), !padIDs.isEmpty
        else {
            logPiper("模型缺少 ^ / _ / $ 的 phoneme_id_map，无法按官方 Piper 规则组装输入：\(originalText)")
            return nil
        }

        let contentSymbols = symbols.filter { $0 != "^" && $0 != "$" }
        guard !contentSymbols.isEmpty else {
            logPiper("去除边界符后音素序列为空，无法合成：\(originalText)")
            return nil
        }

        var ids: [Int64] = []
        ids.reserveCapacity(bosIDs.count + eosIDs.count + contentSymbols.count * 2)
        ids.append(contentsOf: bosIDs.map(Int64.init))

        let usesChinesePinyinGrouping = config.phoneme_type == "pinyin"

        for symbol in contentSymbols {
            guard let phonemeIDs = config.ids(for: symbol), !phonemeIDs.isEmpty else {
                logPiper("模型不认识的音素：\(symbol)，原句：\(originalText)")
                return nil
            }

            ids.append(contentsOf: phonemeIDs.map(Int64.init))

            if usesChinesePinyinGrouping {
                if chinesePinyinGroupEndSymbols.contains(symbol) {
                    ids.append(contentsOf: padIDs.map(Int64.init))
                }
            } else {
                ids.append(contentsOf: padIDs.map(Int64.init))
            }
        }

        ids.append(contentsOf: eosIDs.map(Int64.init))
        return ids
    }

    private func stabilizedSymbolsForShortUtterance(_ symbols: [String], originalText: String) -> [String] {
        guard symbols.count >= 3,
              let eosIndex = symbols.lastIndex(of: "$"),
              eosIndex > 0
        else {
            return symbols
        }

        let terminalBoundarySymbols: Set<String> = ["。", ".", "？", "?", "！", "!", "—", "…", "、", "，", ",", "：", ":", "；", ";", " "]
        let lastContentIndex = symbols.index(before: eosIndex)
        if terminalBoundarySymbols.contains(symbols[lastContentIndex]) {
            return symbols
        }

        let syllableCount = syllableCount(in: symbols)

        guard syllableCount <= 1 else {
            return symbols
        }

        var stabilized = symbols
        stabilized.insert(" ", at: eosIndex)
        logPiper("为极短输入补充句末停顿边界以稳定发声：\(originalText) -> \(stabilized)")
        return stabilized
    }

    private func describeAudioFormat(_ format: AVAudioFormat) -> String {
        let sampleRate = format.sampleRate > 0 ? String(format: "%.0f", format.sampleRate) : "unknown"
        return "\(sampleRate)Hz/\(format.channelCount)ch"
    }

    private func currentPlaybackFormat() -> AVAudioFormat {
        let playerFormat = playerNode.outputFormat(forBus: 0)
        if playerFormat.sampleRate > 0, playerFormat.channelCount > 0 {
            return playerFormat
        }

        let mixerFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        if mixerFormat.sampleRate > 0, mixerFormat.channelCount > 0 {
            return mixerFormat
        }

        return AVAudioFormat(standardFormatWithSampleRate: modelSampleRate, channels: 1)!
    }

    private func trimNearSilenceForVeryShortUtterance(_ samples: [Float], originalText: String) -> [Float] {
        guard samples.count > 512 else { return samples }

        let peak = samples.reduce(0.0 as Float) { partial, sample in
            max(partial, abs(sample))
        }
        guard peak > 0 else { return samples }

        let threshold = max(peak * 0.015, 0.0005)
        guard let firstAudibleIndex = samples.firstIndex(where: { abs($0) >= threshold }),
              let lastAudibleIndex = samples.lastIndex(where: { abs($0) >= threshold })
        else {
            return samples
        }

        let padding = min(256, max(64, samples.count / 80))
        let start = max(0, firstAudibleIndex - padding)
        let end = min(samples.count - 1, lastAudibleIndex + padding)

        guard start > 0 || end < samples.count - 1 else {
            return samples
        }

        let trimmed = Array(samples[start...end])
        logPiper(
            "为极短输入裁剪弱静音：\(originalText) frames \(samples.count) -> \(trimmed.count), " +
            "threshold=\(String(format: "%.5f", threshold))"
        )
        return trimmed
    }

    private func normalizeVeryShortUtterance(_ samples: [Float], originalText: String) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let peak = samples.reduce(0.0 as Float) { partial, sample in
            max(partial, abs(sample))
        }
        guard peak > 0 else { return samples }

        let targetPeak: Float = 0.32
        let maxGain: Float = 2.5
        let gain = min(maxGain, targetPeak / peak)

        guard gain > 1.05 else {
            return samples
        }

        let normalized = samples.map { sample in
            max(-1.0, min(1.0, sample * gain))
        }
        logPiper(
            "为极短输入做轻度归一化：\(originalText) peak \(String(format: "%.4f", peak)) -> " +
            "\(String(format: "%.4f", min(1.0, peak * gain))) gain=\(String(format: "%.2f", gain))"
        )
        return normalized
    }

    private func convertForPlaybackIfNeeded(_ sourceBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let targetFormat = currentPlaybackFormat()
        let sourceFormat = sourceBuffer.format

        if sourceFormat.sampleRate == targetFormat.sampleRate,
           sourceFormat.channelCount == targetFormat.channelCount,
           sourceFormat.commonFormat == targetFormat.commonFormat,
           sourceFormat.isInterleaved == targetFormat.isInterleaved {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            logPiper("无法创建重采样转换器：source=\(describeAudioFormat(sourceFormat)) target=\(describeAudioFormat(targetFormat))")
            return nil
        }

        let estimatedFrameCount = max(
            1,
            Int(ceil(Double(sourceBuffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate)) + 1024
        )
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(estimatedFrameCount)
        ) else {
            logPiper("无法为重采样后的音频分配缓冲区。target=\(describeAudioFormat(targetFormat))")
            return nil
        }

        var didSupplySource = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didSupplySource {
                outStatus.pointee = .endOfStream
                return nil
            }

            didSupplySource = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            guard convertedBuffer.frameLength > 0 else {
                logPiper("重采样后没有得到任何音频帧。source=\(describeAudioFormat(sourceFormat)) target=\(describeAudioFormat(targetFormat))")
                return nil
            }
            logPiper("已将模型音频从 \(describeAudioFormat(sourceFormat)) 转换到播放格式 \(describeAudioFormat(targetFormat))")
            return convertedBuffer
        case .error:
            logPiper("重采样失败：\(conversionError?.localizedDescription ?? "unknown error")")
            return nil
        @unknown default:
            logPiper("遇到未知的 AVAudioConverter 状态。")
            return nil
        }
    }

    private func setupOrtIfPossible() {
        guard let modelURL = resolveModelURL() else {
            logPiper("未找到模型文件 \(modelBasename)，将回退到系统语音。")
            return
        }

        releaseOrtResources()

        // Load voice json next to the model
        let jsonURL = modelURL.deletingPathExtension().appendingPathExtension("onnx.json")
        if let cfg = try? PiperVoiceConfig.load(from: jsonURL) {
            self.voiceConfig = cfg
            self.modelSampleRate = cfg.audio.sample_rate
            reconnectAudioGraph()
            if audioEngine.isRunning {
                playerNode.stop()
                audioEngine.stop()
                try? audioEngine.start()
            }
            logPiper("模型采样率：\(Int(cfg.audio.sample_rate)) Hz；当前播放图：\(describeAudioFormat(currentPlaybackFormat()))")
            if bypassTimePitchForPiperDiagnostics {
                logPiper("诊断模式已启用：Piper 已旁路 TimePitch，当前语速/音调滑块不会影响 Piper 播放。")
            }
        } else {
            logPiper("未能读取模型配置：\(jsonURL.lastPathComponent)")
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let session = modelURL.path.withCString { path in
            TROrtPiperSessionCreate(path, &errorMessage)
        }

        guard let session else {
            logPiper(consumeErrorMessage(errorMessage) ?? "ONNX session 创建失败。")
            return
        }

        self.ortSession = session

        var inputNames = TROrtCStringArray(items: nil, count: 0)
        var outputNames = TROrtCStringArray(items: nil, count: 0)
        errorMessage = nil

        if TROrtPiperSessionCopyIO(session, &inputNames, &outputNames, &errorMessage) {
            ortInputNames = consumeCStringArray(&inputNames)
            ortOutputNames = consumeCStringArray(&outputNames)
            logPiper("ONNX session 已加载。inputs=\(ortInputNames), outputs=\(ortOutputNames)")
        } else {
            logPiper(consumeErrorMessage(errorMessage) ?? "无法读取 ONNX 模型输入输出签名。")
        }
    }

    private func resolveModelURL() -> URL? {
        if let url = Bundle.main.url(forResource: modelBasename, withExtension: nil) {
            return url
        }

        if let url = Bundle.main.url(forResource: modelBasename, withExtension: nil, subdirectory: "modules/zh-cn/xiao_ya") {
            return url
        }

        let devPath = "/Users/RENREN/Desktop/materials/xcode-workspace/TextReader/TextReader/modules/zh-cn/xiao_ya/\(modelBasename)"
        let devURL = URL(fileURLWithPath: devPath)
        if FileManager.default.fileExists(atPath: devURL.path) {
            return devURL
        }

        return nil
    }

    func exportAudio(for text: String) async throws -> ExportedSpeechAudio {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeechExportError.emptyText
        }
        guard ortSession != nil, voiceConfig != nil else {
            throw SpeechExportError.synthesisFailed("Piper 模型尚未就绪，暂时无法导出对比音频。")
        }

        let queuedSentences = makeQueuedSentences(for: trimmed)
        guard !queuedSentences.isEmpty else {
            throw SpeechExportError.emptyText
        }

        var combinedSamples: [Float] = []
        var exportSampleRate: Double?
        var sentenceDebugPayloads: [ExportDebugPayload.Sentence] = []

        for (index, sentence) in queuedSentences.enumerated() {
            guard let sentenceAudio = synthesizeSentenceAudio(for: sentence) else {
                throw SpeechExportError.synthesisFailed("导出失败：句子“\(sentence.text)”未能完成 Piper 合成。")
            }

            if let debugInfo = SimpleZhPinyinPhonemizer.debugInfo(
                for: sentence.text,
                explicitTokens: sentence.explicitTokens,
                externalOverrideSourceDescription: sentence.externalOverrideSourceDescription,
                pinyinMode: configuration.piperPinyinMode
            ) {
                let phonemeIDs = phonemeIDs(for: debugInfo.symbols, config: voiceConfig!, originalText: sentence.text)?.compactMap {
                    Int(exactly: $0)
                } ?? []
                sentenceDebugPayloads.append(
                    ExportDebugPayload.Sentence(
                        text: sentence.text,
                        tokens: debugInfo.tokens,
                        symbols: debugInfo.symbols,
                        phonemeIDs: phonemeIDs,
                        usedExternalOverride: debugInfo.usedExternalOverride,
                        externalOverrideSourceDescription: debugInfo.externalOverrideSourceDescription
                    )
                )
            }

            if let exportSampleRate {
                guard abs(exportSampleRate - sentenceAudio.sampleRate) < 0.5 else {
                    throw SpeechExportError.saveFailed("导出失败：不同句子的采样率不一致。")
                }
            } else {
                exportSampleRate = sentenceAudio.sampleRate
            }

            if index > 0 {
                let gapFrames = Int(sentenceAudio.sampleRate * 0.06)
                combinedSamples.append(contentsOf: repeatElement(0, count: gapFrames))
            }
            combinedSamples.append(contentsOf: sentenceAudio.samples)
        }

        guard let exportSampleRate, !combinedSamples.isEmpty else {
            throw SpeechExportError.synthesisFailed("导出失败：没有得到可写入的音频数据。")
        }

        let exportDirectoryAccess = try beginExportDirectoryAccess()
        defer { exportDirectoryAccess.stopAccess() }

        let baseURL = try makeExportBaseURL(for: trimmed, exportRoot: exportDirectoryAccess.directoryURL)
        let wavURL = baseURL.appendingPathExtension("wav")
        try writeWaveFile(samples: combinedSamples, sampleRate: exportSampleRate, to: wavURL)

        try? writeExportDebugPayload(
            ExportDebugPayload(
                text: trimmed,
                lengthScale: configuration.piperLengthScale,
                pinyinMode: configuration.piperPinyinMode,
                sampleRate: exportSampleRate,
                sentenceCount: sentenceDebugPayloads.count,
                sentences: sentenceDebugPayloads
            ),
            to: baseURL.appendingPathExtension("json")
        )

        logPiper("已导出对比音频：\(wavURL.path)")
        return ExportedSpeechAudio(fileURL: wavURL, formatDescription: "WAV")
    }

    private func beginExportDirectoryAccess() throws -> ScopedExportDirectoryAccess {
        let exportRoot = Self.preferredExportDirectoryURL

        do {
            try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

#if canImport(AppKit)
            if let restored = try restoreBookmarkedExportDirectoryAccess(for: exportRoot) {
                return restored
            }

            if canWriteToExportDirectory(exportRoot) {
                return ScopedExportDirectoryAccess(directoryURL: exportRoot, stopAccess: {})
            }

            return try beginSecurityScopedExportDirectoryAccess(exportRoot: exportRoot)
#else
            if canWriteToExportDirectory(exportRoot) {
                return ScopedExportDirectoryAccess(directoryURL: exportRoot, stopAccess: {})
            }

            throw SpeechExportError.saveFailed(
                "程序没有权限写入导出目录：\(exportRoot.path)"
            )
#endif
        } catch {
#if canImport(AppKit)
            return try beginSecurityScopedExportDirectoryAccess(exportRoot: exportRoot)
#else
            throw SpeechExportError.saveFailed(
                "程序没有权限写入导出目录：\(exportRoot.path)\n\n系统错误：\(error.localizedDescription)"
            )
#endif
        }
    }

#if canImport(AppKit)
    private func beginSecurityScopedExportDirectoryAccess(exportRoot: URL) throws -> ScopedExportDirectoryAccess {
        let normalizedExportRoot = exportRoot.standardizedFileURL

        let panel = NSOpenPanel()
        panel.title = "授权导出目录"
        panel.message = "请允许 TextReader 将导出音频保存到以下目录：\n\n\(normalizedExportRoot.path)\n\n在弹窗中选择“TextReader Exports”文件夹，然后点“授权”。"
        panel.prompt = "授权"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = normalizedExportRoot.deletingLastPathComponent()

        guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
            throw SpeechExportError.saveFailed(
                "程序没有访问导出目录的权限。请授权以下目录后重试：\n\n\(normalizedExportRoot.path)"
            )
        }

        guard selectedURL.path == normalizedExportRoot.path else {
            throw SpeechExportError.saveFailed(
                "请选择指定的导出目录：\n\n\(normalizedExportRoot.path)"
            )
        }

        guard selectedURL.startAccessingSecurityScopedResource() else {
            throw SpeechExportError.saveFailed(
                "已选择导出目录，但系统没有授予写入权限：\n\n\(normalizedExportRoot.path)"
            )
        }

        do {
            try FileManager.default.createDirectory(at: normalizedExportRoot, withIntermediateDirectories: true)
            try storeExportDirectoryBookmark(for: selectedURL)
            return ScopedExportDirectoryAccess(directoryURL: normalizedExportRoot) {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        } catch {
            selectedURL.stopAccessingSecurityScopedResource()
            throw SpeechExportError.saveFailed(
                "已获得目录授权，但仍无法写入：\n\n\(normalizedExportRoot.path)\n\n系统错误：\(error.localizedDescription)"
            )
        }
    }

    private func restoreBookmarkedExportDirectoryAccess(for exportRoot: URL) throws -> ScopedExportDirectoryAccess? {
        let defaults = UserDefaults.standard
        guard let bookmarkData = defaults.data(forKey: Self.exportDirectoryBookmarkKey) else {
            return nil
        }

        var isStale = false
        let bookmarkedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL

        guard bookmarkedURL.path == exportRoot.path else {
            defaults.removeObject(forKey: Self.exportDirectoryBookmarkKey)
            return nil
        }

        guard bookmarkedURL.startAccessingSecurityScopedResource() else {
            defaults.removeObject(forKey: Self.exportDirectoryBookmarkKey)
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
            if isStale {
                try storeExportDirectoryBookmark(for: bookmarkedURL)
            }
            return ScopedExportDirectoryAccess(directoryURL: exportRoot) {
                bookmarkedURL.stopAccessingSecurityScopedResource()
            }
        } catch {
            bookmarkedURL.stopAccessingSecurityScopedResource()
            defaults.removeObject(forKey: Self.exportDirectoryBookmarkKey)
            throw SpeechExportError.saveFailed(
                "已恢复导出目录授权，但无法写入：\n\n\(exportRoot.path)\n\n系统错误：\(error.localizedDescription)"
            )
        }
    }

    private func storeExportDirectoryBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: Self.exportDirectoryBookmarkKey)
    }
#endif

    private func canWriteToExportDirectory(_ directoryURL: URL) -> Bool {
        let probeURL = directoryURL.appendingPathComponent(".textreader-write-probe-\(UUID().uuidString)")
        let probeData = Data("probe".utf8)

        do {
            try probeData.write(to: probeURL, options: .atomic)
            try? FileManager.default.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }

    private func makeExportBaseURL(for text: String, exportRoot: URL) throws -> URL {
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let preview = String(text.prefix(12)).lowercased().map { character -> Character in
            let scalar = String(character).unicodeScalars.first
            if let scalar, allowed.contains(scalar) {
                return character
            }
            if character.isWhitespace {
                return "_"
            }
            return "_"
        }
        let stemPreview = String(preview).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let lengthScaleTag = String(format: "ls%.2f", configuration.piperLengthScale)
        let pinyinTag = configuration.piperPinyinMode.shortTag
        let filenameStem = stemPreview.isEmpty
            ? "textreader-\(timestamp)-\(lengthScaleTag)-\(pinyinTag)"
            : "\(timestamp)-\(stemPreview)-\(lengthScaleTag)-\(pinyinTag)"
        return exportRoot.appendingPathComponent(filenameStem)
    }

    private func writeWaveFile(samples: [Float], sampleRate: Double, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = makePCMBuffer(samples: samples, sampleRate: sampleRate, syllableCount: 2)
        else {
            throw SpeechExportError.saveFailed("无法为导出音频构建 WAV 缓冲区。")
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
    }

    private func writeExportDebugPayload(_ payload: ExportDebugPayload, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    private func makeQueuedSentences(for text: String) -> [QueuedSentence] {
        let sentences = SentenceSplitter.split(text, maxChunkLength: 200)
        guard !sentences.isEmpty else { return [] }

        let resolvedOverrides = ExternalPinyinOverrideStore.shared.sentenceOverrides(for: text, sentences: sentences)
        if ExternalPinyinOverrideStore.shared.matchedOverride(for: text) != nil, resolvedOverrides == nil {
            logPiper("已加载外部拼音覆盖，但无法按句对齐；本次将回退到内置前端。")
        }

        return sentences.enumerated().map { index, sentence in
            let override = resolvedOverrides?[index]
            return QueuedSentence(
                text: sentence,
                explicitTokens: override?.tokens,
                externalOverrideSourceDescription: override?.sourceDescription
            )
        }
    }

    private func synthesizeSentenceAudio(for sentence: QueuedSentence) -> SynthesizedSentenceAudio? {
        guard let ortSession, let cfg = voiceConfig else {
            logPiper("ONNX session 或 voice config 未就绪，句子将回退到系统语音。")
            return nil
        }

        let rawSymbols = SimpleZhPinyinPhonemizer.phonemizeToPiperSymbols(
            sentence.text,
            explicitTokens: sentence.explicitTokens,
            externalOverrideSourceDescription: sentence.externalOverrideSourceDescription,
            pinyinMode: configuration.piperPinyinMode
        )
        let symbols = stabilizedSymbolsForShortUtterance(rawSymbols, originalText: sentence.text)
        let syllableCount = syllableCount(in: symbols)
        guard symbols.count >= 3 else {
            logPiper("音素序列过短，无法合成：\(sentence.text)")
            return nil
        }

        guard let ids = phonemeIDs(for: symbols, config: cfg, originalText: sentence.text) else {
            return nil
        }

        let inf = cfg.inference
        let noiseScale = Float(inf?.noise_scale ?? 0.667)
        let configuredLengthScale = configuration.piperLengthScale
        let lengthScale = Float(max(0.5, min(2.0, configuredLengthScale)))
        let noiseW = Float(inf?.noise_w ?? 0.8)
        var waveform = TROrtFloatArray(data: nil, count: 0)
        var errorMessage: UnsafeMutablePointer<CChar>?

        let didSucceed = ids.withUnsafeBufferPointer { inputBuffer in
            guard let baseAddress = inputBuffer.baseAddress else { return false }
            return TROrtPiperSessionSynthesize(
                ortSession,
                baseAddress,
                inputBuffer.count,
                noiseScale,
                lengthScale,
                noiseW,
                true,
                0,
                &waveform,
                &errorMessage
            )
        }

        guard didSucceed, let samplePointer = waveform.data, waveform.count > 0 else {
            logPiper(consumeErrorMessage(errorMessage) ?? "ONNX 推理失败。输入=\(ortInputNames) 输出=\(ortOutputNames)")
            return nil
        }
        defer { TROrtFloatArrayFree(waveform) }

        let rawSamples = Array(UnsafeBufferPointer(start: samplePointer, count: Int(waveform.count)))
        let samples: [Float]
        if syllableCount <= 1 {
            let trimmedSamples = trimNearSilenceForVeryShortUtterance(rawSamples, originalText: sentence.text)
            samples = normalizeVeryShortUtterance(trimmedSamples, originalText: sentence.text)
        } else {
            samples = rawSamples
        }

        return SynthesizedSentenceAudio(samples: samples, sampleRate: cfg.audio.sample_rate, syllableCount: syllableCount)
    }

    private func synthesizePCM(for sentence: QueuedSentence) -> AVAudioPCMBuffer? {
        guard let sentenceAudio = synthesizeSentenceAudio(for: sentence) else {
            return nil
        }

        guard let sourceBuffer = makePCMBuffer(
            samples: sentenceAudio.samples,
            sampleRate: sentenceAudio.sampleRate,
            syllableCount: sentenceAudio.syllableCount
        ) else {
            return nil
        }

        return convertForPlaybackIfNeeded(sourceBuffer)
    }

    private func makePCMBuffer(samples: [Float], sampleRate: Double, syllableCount: Int) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let out = buffer.floatChannelData?[0] else { return nil }

        // Copy + clamp
        for i in 0..<samples.count {
            let v = max(-1.0, min(1.0, Double(samples[i])))
            out[i] = Float(v)
        }

        // Tiny fade-in/out to reduce clicks
        let fade: Int
        if syllableCount <= 1 {
            fade = min(64, samples.count / 40)
        } else {
            fade = min(256, samples.count / 10)
        }
        if fade > 0 {
            for i in 0..<fade {
                let g = Float(i + 1) / Float(fade + 1)
                out[i] *= g
                out[samples.count - 1 - i] *= g
            }
        }

        return buffer
    }

    /// Placeholder synthesized audio: short silence.
    private func synthesizePlaceholderPCM(for sentence: String) -> AVAudioPCMBuffer? {
        let format = currentPlaybackFormat()
        let frameCount = AVAudioFrameCount(format.sampleRate * 0.12)
        guard frameCount > 0 else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let channelsPtr = buffer.floatChannelData!
        memset(channelsPtr[0], 0, Int(frameCount) * MemoryLayout<Float>.size)
        return buffer
    }
}
