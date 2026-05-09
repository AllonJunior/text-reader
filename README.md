# TextReader

A tiny SwiftUI text reader for macOS and iOS. Supports manual text input, importing mainstream document formats, pagination, and read-aloud playback.

一个面向 macOS 和 iOS 的轻量 SwiftUI 文本阅读器，支持手动输入、多格式文档导入、分页阅读和朗读播放。

## Features / 功能

- Manual text input and editing / 手动输入与编辑文本
- File import for multiple document formats / 支持多种文档格式导入
- Pagination for long-form reading / 长文本自动分页
- Previous / next page navigation, quick jump to first / last page, and direct page-number jump / 支持前后翻页、快速回到首尾页，以及按页码直接跳转
- Built-in read-aloud playback / 内置朗读播放
- Optional external pinyin override JSON for Chinese pronunciation tuning / 可选外部拼音覆盖 JSON，用于中文发音微调

## Supported import formats / 支持导入的格式

TextReader currently supports importing and extracting text from the following file types.

TextReader 当前支持从以下文件类型中导入并提取文本。

### Plain text-like formats / 纯文本类格式

- `.txt`
- `.text`
- `.md` / `.markdown`
- `.json`
- `.csv` / `.tsv`
- `.log`
- `.xml`
- `.yaml` / `.yml`
- `.ini` / `.conf`

### Rich text / document formats / 富文本与文档格式

- `.html` / `.htm`
- `.rtf`
- `.doc`
- `.docx`
- `.odt`
- `.pdf`
- `.epub`

## Import behavior / 导入行为

- Use **“从文件加载”** in the main interface to select a document.
- Imported content is normalized and then paginated automatically.
- Plain text files support common encodings such as UTF-8, UTF-16, GB18030, Big5, EUC-CN, ASCII, Latin-1, and Windows-1252.
- Rich text, Office documents, PDF, and EPUB are imported as extracted plain text for reading and TTS.

- 在主界面中使用 **“从文件加载”** 选择文档。
- 导入后的内容会先做规范化处理，再自动分页。
- 纯文本文件支持 UTF-8、UTF-16、GB18030、Big5、EUC-CN、ASCII、Latin-1、Windows-1252 等常见编码。
- 富文本、Office 文档、PDF 和 EPUB 会以“提取出的纯文本”形式导入，用于阅读与 TTS。

## Usage / 使用方式

- After text is entered or imported, use the on-screen controls to go to the first page, previous page, next page, or last page.
- You can also enter a page number and press **“跳转”** to jump directly.
- These controls are designed for long-form reading, so large documents can be navigated more efficiently.

- 输入或导入文本后，可以使用界面上的按钮快速切换到首页、上一页、下一页或末页。
- 也可以直接输入页码并点击 **“跳转”**，快速定位到目标页面。
- 这些分页控件主要面向长文本阅读，方便在较大的文档中高效导航。

## Keyboard shortcuts / 快捷键

Available on macOS and in keyboard-enabled usage scenarios:

适用于 macOS，以及连接外接键盘的使用场景：

- `⌘←` — Go to first page / 回到首页
- `⌥←` — Go to previous page / 上一页
- `⌥→` — Go to next page / 下一页
- `⌘→` — Go to last page / 跳到末页

## EPUB support notes / EPUB 支持说明

- EPUB import focuses on **text extraction for reading**, not visual layout reproduction.
- Chapter text is imported in reading order when available.
- Complex layouts, heavily styled books, image-based pages, DRM-protected EPUBs, or malformed EPUB packages may not extract perfectly.
- If an EPUB contains little or no extractable text, the app will report an import failure rather than silently loading an empty document.

- EPUB 导入以**提取可阅读文本**为主，不以还原原始排版为目标。
- 如果书籍结构可用，章节文本会按阅读顺序导入。
- 对于复杂排版、重样式图书、图片页、带 DRM 的 EPUB 或损坏的 EPUB 包，文本提取可能不完整。
- 如果 EPUB 中几乎没有可提取文本，应用会明确提示导入失败，而不是静默加载空内容。

## PDF / document extraction notes / PDF 与文档提取说明

- PDF import works best for PDFs with a selectable text layer.
- Scanned PDFs or image-only pages may not produce usable text.
- Word / ODT / HTML / RTF imports aim to preserve readable body text, but complex formatting, tables, headers/footers, annotations, and some embedded content may be simplified or omitted.

- PDF 导入最适合带有可选中文本层的 PDF。
- 扫描版 PDF 或纯图片页面可能无法提取出可用文本。
- Word / ODT / HTML / RTF 导入会尽量保留可阅读正文，但复杂排版、表格、页眉页脚、批注以及部分嵌入内容可能会被简化或省略。

## Documentation / 文档

- [中文发音排障经验](docs/chinese-pronunciation-troubleshooting.md)

## Current TTS / 当前 TTS

The app currently uses Apple’s built-in `AVSpeechSynthesizer` (no extra dependencies).

当前应用使用 Apple 内置的 `AVSpeechSynthesizer`，不需要额外依赖。

## (Planned) Offline open-source TTS on iOS (Chinese) / （规划中）iOS 中文离线开源 TTS

If you want **more human-like Chinese voices** and you can accept a much larger app size (you said up to ~500MB), the most practical open-source option for iOS is typically **Piper TTS** (ONNX-based) with a Chinese voice model.

如果你希望获得**更接近真人的中文声音**，并且可以接受明显更大的 App 体积（你之前提到可接受到约 500MB），那么在 iOS 上比较实际的开源方案通常是基于 ONNX 的 **Piper TTS** 搭配中文语音模型。

### Why Piper / 为什么选择 Piper

- Open-source / 开源
- Fully offline / 完全离线
- Has community Chinese voices / 有社区维护的中文音色
- Quality is generally more natural than classic formant engines (eSpeak) / 相比经典共振峰引擎（如 eSpeak），自然度通常更好

### What you’ll add to the Xcode project / 需要向 Xcode 工程中加入的内容

1. **ONNX Runtime for iOS** as a prebuilt `.xcframework` (or build from source). / 以预编译 `.xcframework` 形式引入 **ONNX Runtime for iOS**（或自行源码编译）。
2. **Piper iOS wrapper** (C/C++ library + Swift bridging layer). / 引入 **Piper iOS 封装层**（C/C++ 库 + Swift 桥接层）。
3. One **Chinese voice model** (often tens to hundreds of MB) copied into the app bundle. / 将一个**中文语音模型**拷贝到 App Bundle 中（通常几十到几百 MB）。

### High-level integration steps / 高层集成步骤

1. Create `TextReader/TTS/` folder for wrapper code. / 为封装代码创建 `TextReader/TTS/` 目录。
2. Add `onnxruntime.xcframework` to the project (Frameworks, Libraries, and Embedded Content). / 将 `onnxruntime.xcframework` 加入工程（Frameworks, Libraries, and Embedded Content）。
3. Add Piper wrapper sources (C/C++), expose a C API for: / 添加 Piper 封装源文件（C/C++），并暴露一个 C API，用于：
   - load model / 加载模型
   - synthesize(text) -> PCM / 合成文本到 PCM
   - cancel / 取消合成
4. In Swift, create an engine class (e.g. `PiperTTSEngine`) that: / 在 Swift 中创建一个引擎类（例如 `PiperTTSEngine`），负责：
   - loads model from `Bundle.main.url(forResource:...)` / 从 `Bundle.main.url(forResource:...)` 加载模型
   - synthesizes into PCM buffers / 合成为 PCM 缓冲
   - plays via `AVAudioEngine` + `AVAudioPlayerNode` / 通过 `AVAudioEngine` + `AVAudioPlayerNode` 播放
5. Keep the current UI unchanged by keeping the `SpeechManager` API the same. / 保持 `SpeechManager` API 不变，从而尽量不改现有 UI。

### Notes / risks / 注意事项与风险

- **App size**: most of the size comes from the Chinese model(s). / **App 体积**：大部分体积都会来自中文模型本身。
- **Performance**: first-sentence latency depends on device + model; consider caching / model warm-up. / **性能**：首句延迟取决于设备和模型，可考虑缓存或预热模型。
- **Licenses**: you must track the license for Piper, ONNX Runtime, and the selected voice model. / **许可证**：需要分别确认 Piper、ONNX Runtime 和所选语音模型的许可证要求。
