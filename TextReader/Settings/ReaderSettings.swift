import Foundation
import Combine

@MainActor
final class ReaderSettings: ObservableObject {
    enum BackendOption: String, CaseIterable, Identifiable {
        case system
        case piper

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system:
                return "系统语音"
            case .piper:
                return "Piper 本地语音"
            }
        }
    }

    private enum Keys {
        static let backend = "reader.settings.backend"
        static let rate = "reader.settings.rate"
        static let pitch = "reader.settings.pitch"
        static let volume = "reader.settings.volume"
        static let piperLengthScale = "reader.settings.piperLengthScale"
        static let piperPinyinMode = "reader.settings.piperPinyinMode"
    }

    @Published var backend: BackendOption {
        didSet { defaults.set(backend.rawValue, forKey: Keys.backend) }
    }

    @Published var rate: Double {
        didSet { defaults.set(rate, forKey: Keys.rate) }
    }

    @Published var pitch: Double {
        didSet { defaults.set(pitch, forKey: Keys.pitch) }
    }

    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: Keys.volume) }
    }

    @Published var piperLengthScale: Double {
        didSet { defaults.set(piperLengthScale, forKey: Keys.piperLengthScale) }
    }

    @Published var piperPinyinMode: PiperPinyinMode {
        didSet { defaults.set(piperPinyinMode.rawValue, forKey: Keys.piperPinyinMode) }
    }

    var speechConfiguration: SpeechConfiguration {
        SpeechConfiguration(
            rate: rate,
            pitch: pitch,
            volume: volume,
            piperLengthScale: piperLengthScale,
            piperPinyinMode: piperPinyinMode
        )
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let rawBackend = defaults.string(forKey: Keys.backend)
        self.backend = BackendOption(rawValue: rawBackend ?? "") ?? .piper

        let storedRate = defaults.object(forKey: Keys.rate) as? Double
        let storedPitch = defaults.object(forKey: Keys.pitch) as? Double
        let storedVolume = defaults.object(forKey: Keys.volume) as? Double
        let storedPiperLengthScale = defaults.object(forKey: Keys.piperLengthScale) as? Double
        let storedPiperPinyinMode = defaults.string(forKey: Keys.piperPinyinMode)

        self.rate = storedRate ?? SpeechConfiguration.default.rate
        self.pitch = storedPitch ?? SpeechConfiguration.default.pitch
        self.volume = storedVolume ?? SpeechConfiguration.default.volume
        self.piperLengthScale = storedPiperLengthScale ?? SpeechConfiguration.default.piperLengthScale
        self.piperPinyinMode = PiperPinyinMode(rawValue: storedPiperPinyinMode ?? "") ?? SpeechConfiguration.default.piperPinyinMode
    }

    func reset() {
        backend = .piper
        rate = SpeechConfiguration.default.rate
        pitch = SpeechConfiguration.default.pitch
        volume = SpeechConfiguration.default.volume
        piperLengthScale = SpeechConfiguration.default.piperLengthScale
        piperPinyinMode = SpeechConfiguration.default.piperPinyinMode
    }
}
