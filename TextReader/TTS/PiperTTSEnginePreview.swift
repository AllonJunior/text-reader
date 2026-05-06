#if PREVIEW
import Foundation

/// Preview-only stub to avoid linking onnxruntime while keeping APIs available.
@MainActor
final class PiperTTSEngine: TTSEngine {
    var isSpeaking: Bool = false
    var isPaused: Bool = false
    var onDidStart: (() -> Void)?
    var onDidFinish: (() -> Void)?
    var onDidCancel: (() -> Void)?
    var onPlaybackSourceChanged: ((SpeechPlaybackSource?) -> Void)?

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSpeaking = true
        isPaused = false
        onPlaybackSourceChanged?(.piper)
        onDidStart?()
        isSpeaking = false
        onPlaybackSourceChanged?(nil)
        onDidFinish?()
    }

    func stop() {
        guard isSpeaking || isPaused else { return }
        isSpeaking = false
        isPaused = false
        onPlaybackSourceChanged?(nil)
        onDidCancel?()
    }

    @discardableResult
    func pause() -> Bool {
        guard isSpeaking, !isPaused else { return false }
        isPaused = true
        return true
    }

    @discardableResult
    func resume() -> Bool {
        guard isPaused else { return false }
        isPaused = false
        return true
    }

    func apply(settings: SpeechConfiguration) {
        // Preview stub intentionally ignores settings.
    }
}
#endif
