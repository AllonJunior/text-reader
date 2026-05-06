import Foundation

#if DEBUG
/// Lightweight self-test / demo cases for the sentence splitter.
///
/// Call `SentenceSplitterSelfTest.run()` from anywhere in DEBUG to print results.
enum SentenceSplitterSelfTest {
    static func run() {
        let cases: [String] = [
            "你好！我叫小雅。很高兴认识你！",
            "他说：\"今天下雨了……我们改天再去吧。\"我点点头。",
            "价格是3.14元，不是3.1。OK?",
            "Abbrev: e.g. i.e. U.S.A. should not split by dots.",
            "连续标点？！真的可以！！当然。",
            "很长很长很长很长很长很长很长很长很长很长很长很长，后面继续。",
            // Multi-line / paragraphs / titles
            "第一卷 平庸少年\n\n第一章 离乡\n　　铁柱坐在村内的小路边，望着蔚蓝的天空，神情发呆。\n\n　　第二段开头有缩进。它应该作为新段落。",
        ]

        for (idx, text) in cases.enumerated() {
            let parts = SentenceSplitter.split(text, maxChunkLength: 20)
            print("[SentenceSplitterSelfTest] Case \(idx + 1): \(text)")
            for (i, p) in parts.enumerated() {
                print("  \(i + 1). \(p)")
            }
        }
    }
}
#endif
