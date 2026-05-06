import Foundation
import Combine

/// Coordinates reading state for the UI, independent of the underlying TTS backend.
@MainActor
final class SpeechManager: ObservableObject {
    enum Backend {
        case system
        case piper
    }

    enum SpeechState {
        case idle
        case reading
        case paused
    }

    @Published private(set) var speechState: SpeechState = .idle
    @Published private(set) var playbackSource: SpeechPlaybackSource?

    var isReading: Bool { speechState != .idle }
    var isPlaybackActive: Bool { speechState == .reading || speechState == .paused }

    private var engine: TTSEngine
    private var settings: ReaderSettings?
    private var cancellables = Set<AnyCancellable>()
    private var lastText: String = ""
    private var engineCallbackToken = UUID()

    init(settings: ReaderSettings) {
        self.settings = settings
        self.engine = SpeechManager.makeEngine(for: settings.backend)
        bindEngineCallbacks()
        bindSettings(settings)
        engine.apply(settings: settings.speechConfiguration)
    }

    /// Dependency-injection initializer (useful for SwiftUI Previews/tests).
    init(engine: TTSEngine) {
        self.engine = engine
        bindEngineCallbacks()
        engine.apply(settings: .default)
    }

    private static func makeEngine(for backend: ReaderSettings.BackendOption) -> TTSEngine {
        switch backend {
        case .system:
            return SystemTTSEngine()
        case .piper:
            return PiperTTSEngine()
        }
    }

    private func bindEngineCallbacks() {
        let token = UUID()
        engineCallbackToken = token

        engine.onDidStart = { [weak self] in
            guard let self, self.engineCallbackToken == token else { return }
            self.speechState = .reading
        }
        engine.onDidFinish = { [weak self] in
            guard let self, self.engineCallbackToken == token else { return }
            self.speechState = .idle
            self.playbackSource = nil
        }
        engine.onDidCancel = { [weak self] in
            guard let self, self.engineCallbackToken == token else { return }
            self.speechState = .idle
            self.playbackSource = nil
        }
        engine.onPlaybackSourceChanged = { [weak self] source in
            guard let self, self.engineCallbackToken == token else { return }
            self.playbackSource = source
        }
    }

    private func bindSettings(_ settings: ReaderSettings) {
        settings.$backend
            .dropFirst()
            .sink { [weak self] backend in
                self?.switchBackend(to: backend)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            Publishers.CombineLatest4(settings.$rate, settings.$pitch, settings.$volume, settings.$piperLengthScale),
            settings.$piperPinyinMode
        )
            .dropFirst()
            .sink { [weak self] combined, piperPinyinMode in
                let (rate, pitch, volume, piperLengthScale) = combined
                self?.engine.apply(
                    settings: SpeechConfiguration(
                        rate: rate,
                        pitch: pitch,
                        volume: volume,
                        piperLengthScale: piperLengthScale,
                        piperPinyinMode: piperPinyinMode
                    )
                )
            }
            .store(in: &cancellables)
    }

    private func switchBackend(to backend: ReaderSettings.BackendOption) {
        engine.onDidStart = nil
        engine.onDidFinish = nil
        engine.onDidCancel = nil
        engine.onPlaybackSourceChanged = nil
        engineCallbackToken = UUID()

        engine.stop()
        speechState = .idle
        playbackSource = nil

        engine = SpeechManager.makeEngine(for: backend)
        bindEngineCallbacks()
        if let settings {
            engine.apply(settings: settings.speechConfiguration)
        }
        playbackSource = nil
    }

    func startReading(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lastText = trimmed
        if let settings {
            engine.apply(settings: settings.speechConfiguration)
        }
        engine.speak(trimmed)
    }

    func exportCurrentTextAudio(text: String) async throws -> ExportedSpeechAudio {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeechExportError.emptyText
        }

        lastText = trimmed
        if let settings {
            engine.apply(settings: settings.speechConfiguration)
        }
        return try await engine.exportAudio(for: trimmed)
    }

    func pauseReading() {
        if engine.pause() {
            speechState = .paused
        }
    }

    func resumeReading() {
        if engine.resume() {
            speechState = .reading
        } else if !lastText.isEmpty {
            startReading(text: lastText)
        }
    }

    func stopReading() {
        engine.stop()
        playbackSource = nil
    }
}
