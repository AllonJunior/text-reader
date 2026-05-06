import Foundation

/// Minimal voice config parsed from `*.onnx.json` shipped with Piper voices.
struct PiperVoiceConfig: Decodable {
    struct Audio: Decodable {
        let sample_rate: Double
        let quality: String?
    }

    // Not strictly required, but useful for debugging/validation.
    struct Espeak: Decodable {
        let voice: String?
    }

    struct Inference: Decodable {
        let noise_scale: Double?
        let length_scale: Double?
        let noise_w: Double?
    }

    let audio: Audio
    let espeak: Espeak?
    let phoneme_type: String?
    let num_symbols: Int?
    let num_speakers: Int?
    let inference: Inference?

    /// Maps symbol -> [id]. (Piper stores arrays but in practice it’s a single id.)
    let phoneme_id_map: [String: [Int]]

    let speaker_id_map: [String: Int]?

    static func load(from url: URL) throws -> PiperVoiceConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PiperVoiceConfig.self, from: data)
    }

    func id(for symbol: String) -> Int? {
        phoneme_id_map[symbol]?.first
    }

    func ids(for symbol: String) -> [Int]? {
        phoneme_id_map[symbol]
    }
}
