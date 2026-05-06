import Foundation

#if DEBUG
/// Lightweight self-test / demo cases for the bundled Chinese phonemizer.
///
/// Call `SimpleZhPinyinPhonemizerSelfTest.run()` from anywhere in DEBUG to inspect
/// whether generated Piper symbols still contain accidental per-syllable pause tokens.
enum SimpleZhPinyinPhonemizerSelfTest {
    static func run() {
        let cases: [String] = [
            "你好",
            "你好！我叫小雅。",
            "去学习普通话",
            "月亮出来了",
            "“你好！”她笑着说。",
            "银行行长喜欢音乐。",
            "重庆的校长长大后去了银行。",
            "地上有一张地图，大家觉得很重要。",
        ]

        for text in cases {
            let orthographicSymbols = SimpleZhPinyinPhonemizer.phonemizeToPiperSymbols(text)
            let zeroInitialSymbols = SimpleZhPinyinPhonemizer.phonemizeToPiperSymbols(
                text,
                pinyinMode: .zeroInitialNormalized
            )
            print("[SimpleZhPinyinPhonemizerSelfTest] \(text)")
            print("  orthographic: \(orthographicSymbols)")
            print("  zero-initial: \(zeroInitialSymbols)")
        }
    }
}
#endif
