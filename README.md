# TextReader

A tiny SwiftUI text reader. Supports manual text input, importing `.txt` files, and reading aloud.

## Documentation

- [中文发音排障经验](docs/chinese-pronunciation-troubleshooting.md)

## Current TTS

The app currently uses Apple’s built-in `AVSpeechSynthesizer` (no extra dependencies).

## (Planned) Offline open-source TTS on iOS (Chinese)

If you want **more human-like Chinese voices** and you can accept a much larger app size (you said up to ~500MB), the most practical open-source option for iOS is typically **Piper TTS** (ONNX-based) with a Chinese voice model.

### Why Piper

- Open-source
- Fully offline
- Has community Chinese voices
- Quality is generally more natural than classic formant engines (eSpeak)

### What you’ll add to the Xcode project

1. **ONNX Runtime for iOS** as a prebuilt `.xcframework` (or build from source).
2. **Piper iOS wrapper** (C/C++ library + Swift bridging layer).
3. One **Chinese voice model** (often tens to hundreds of MB) copied into the app bundle.

### High-level integration steps

1. Create `TextReader/TTS/` folder for wrapper code.
2. Add `onnxruntime.xcframework` to the project (Frameworks, Libraries, and Embedded Content).
3. Add Piper wrapper sources (C/C++), expose a C API for:
   - load model
   - synthesize(text) -> PCM
   - cancel
4. In Swift, create an engine class (e.g. `PiperTTSEngine`) that:
   - loads model from `Bundle.main.url(forResource:...)`
   - synthesizes into PCM buffers
   - plays via `AVAudioEngine` + `AVAudioPlayerNode`
5. Keep the current UI unchanged by keeping the `SpeechManager` API the same.

### Notes / risks

- **App size**: most of the size comes from the Chinese model(s).
- **Performance**: first-sentence latency depends on device + model; consider caching / model warm-up.
- **Licenses**: you must track the license for Piper, ONNX Runtime, and the selected voice model.

If you want, tell me your target iOS version and whether you prefer “best quality” vs “smaller model”, and I’ll pin down a concrete model choice and a step-by-step file-level integration guide.
