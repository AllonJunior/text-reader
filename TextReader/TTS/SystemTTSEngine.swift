import Foundation
import AVFoundation

/// System TTS backend powered by AVSpeechSynthesizer.
@MainActor
final class SystemTTSEngine: NSObject, TTSEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private var configuration: SpeechConfiguration = .default

    var onDidStart: (() -> Void)?
    var onDidFinish: (() -> Void)?
    var onDidCancel: (() -> Void)?
    var onPlaybackSourceChanged: ((SpeechPlaybackSource?) -> Void)?

    var isSpeaking: Bool { synthesizer.isSpeaking }
    var isPaused: Bool { synthesizer.isPaused }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(configuration.rate)
        utterance.pitchMultiplier = Float(configuration.pitch)
        utterance.volume = Float(configuration.volume)

        onPlaybackSourceChanged?(.system)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        onPlaybackSourceChanged?(nil)
    }

    @discardableResult
    func pause() -> Bool {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return false }
        return synthesizer.pauseSpeaking(at: .word)
    }

    @discardableResult
    func resume() -> Bool {
        guard synthesizer.isPaused else { return false }
        return synthesizer.continueSpeaking()
    }

    func apply(settings: SpeechConfiguration) {
        configuration = settings
    }
}

extension SystemTTSEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onDidStart?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onPlaybackSourceChanged?(nil)
            self.onDidFinish?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onPlaybackSourceChanged?(nil)
            self.onDidCancel?()
        }
    }
}
