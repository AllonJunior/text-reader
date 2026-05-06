import Foundation

/// Mock engine for SwiftUI previews/tests.
/// It never touches audio, models, or any heavy dependencies.
@MainActor
final class MockTTSEngine: TTSEngine {
    var isSpeaking: Bool = false
    var isPaused: Bool = false

    var onDidStart: (() -> Void)?
    var onDidFinish: (() -> Void)?
    var onDidCancel: (() -> Void)?
    var onPlaybackSourceChanged: ((SpeechPlaybackSource?) -> Void)?

    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        isSpeaking = true
        isPaused = false
        onPlaybackSourceChanged?(.system)
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
        // Mock ignores runtime settings.
    }
}
