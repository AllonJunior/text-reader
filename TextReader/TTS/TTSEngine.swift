import Foundation

enum PiperPinyinMode: String, CaseIterable, Identifiable, Codable {
    case orthographic
    case zeroInitialNormalized

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orthographic:
            return "拼写拆分"
        case .zeroInitialNormalized:
            return "零声母归一（实验）"
        }
    }

    var detailText: String {
        switch self {
        case .orthographic:
            return "按常见拼音写法拆分，例如 you -> y + ou，wang -> w + ang。"
        case .zeroInitialNormalized:
            return "把 y/w 开头的零声母拼音归一为更底层的韵母形式，例如 you -> iu，wang -> uang。适合排查中文模型是否按这种规则训练。"
        }
    }

    var shortTag: String {
        switch self {
        case .orthographic:
            return "py-ortho"
        case .zeroInitialNormalized:
            return "py-zero"
        }
    }
}

struct SpeechConfiguration: Equatable, Codable {
    var rate: Double
    var pitch: Double
    var volume: Double
    var piperLengthScale: Double
    var piperPinyinMode: PiperPinyinMode

    static let `default` = SpeechConfiguration(
        rate: 1.0,
        pitch: 1.0,
        volume: 1.0,
        piperLengthScale: 1.0,
        piperPinyinMode: .orthographic
    )
}

struct ExportedSpeechAudio: Equatable {
    let fileURL: URL
    let formatDescription: String
}

enum SpeechExportError: LocalizedError {
    case emptyText
    case unsupportedEngine(String)
    case synthesisFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "没有可导出的文本。"
        case .unsupportedEngine(let detail):
            return detail
        case .synthesisFailed(let detail):
            return detail
        case .saveFailed(let detail):
            return detail
        }
    }
}

enum SpeechPlaybackSource: Equatable {
    case system
    case piper
    case systemFallback

    var displayName: String {
        switch self {
        case .system:
            return "系统语音"
        case .piper:
            return "Piper"
        case .systemFallback:
            return "系统兜底"
        }
    }
}

/// A minimal abstraction so the UI can switch between different TTS backends
/// (e.g. system AVSpeechSynthesizer now, Piper later) without changing view code.
@MainActor
protocol TTSEngine {
    /// Whether the engine is currently speaking/playing audio.
    var isSpeaking: Bool { get }

    /// Whether the engine is paused and can resume from its current position.
    var isPaused: Bool { get }

    /// Start speaking `text`. Implementations should handle trimming/empty text.
    func speak(_ text: String)

    /// Stop speaking immediately.
    func stop()

    /// Pause speaking/playing, keeping the current position when possible.
    @discardableResult
    func pause() -> Bool

    /// Resume speaking/playing after a pause.
    @discardableResult
    func resume() -> Bool

    /// Apply runtime speech settings.
    func apply(settings: SpeechConfiguration)

    /// Export synthesized audio for offline comparison when supported by the backend.
    func exportAudio(for text: String) async throws -> ExportedSpeechAudio

    /// Optional callbacks for state changes.
    var onDidStart: (() -> Void)? { get set }
    var onDidFinish: (() -> Void)? { get set }
    var onDidCancel: (() -> Void)? { get set }
    var onPlaybackSourceChanged: ((SpeechPlaybackSource?) -> Void)? { get set }
}

extension TTSEngine {
    func exportAudio(for text: String) async throws -> ExportedSpeechAudio {
        throw SpeechExportError.unsupportedEngine("当前语音引擎不支持导出对比音频，请切换到 Piper 后再试。")
    }
}
