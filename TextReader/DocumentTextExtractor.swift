import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(PDFKit)
import PDFKit
#endif

enum DocumentTextExtractor {
    static let supportedContentTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]

        for fileExtension in [
            "txt", "text", "md", "markdown", "json", "csv", "tsv", "log",
            "xml", "yaml", "yml", "ini", "conf",
            "html", "htm", "rtf", "pdf", "doc", "docx", "odt",
        ] {
            if let type = UTType(filenameExtension: fileExtension) {
                types.append(type)
            }
        }

        return Array(Set(types))
    }()

    static func extractText(from url: URL) throws -> String {
        guard let kind = supportedKind(for: url) else {
            throw DocumentTextExtractorError.unsupportedFileType(url.lastPathComponent)
        }

        let extractedText: String
        switch kind {
        case .plainText:
            extractedText = try extractPlainText(from: url)
        case .attributed(let documentType):
            extractedText = try extractAttributedText(from: url, documentType: documentType)
        case .pdf:
            extractedText = try extractPDFText(from: url)
        }

        let normalizedText = ReaderTextCanonicalizer.normalizeLineEndingsAndBOM(extractedText)
        guard normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw DocumentTextExtractorError.noExtractableText(
                url.lastPathComponent,
                hint: "文档内容为空，或当前格式里没有可提取的正文文本。"
            )
        }

        return normalizedText
    }

    private static func extractPlainText(from url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DocumentTextExtractorError.extractionFailed(url.lastPathComponent, reason: error.localizedDescription)
        }

        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .unicode,
            .ascii,
            .isoLatin1,
            .windowsCP1252,
            .init(cfEncoding: .GB_18030_2000),
            .init(cfEncoding: .big5),
            .init(cfEncoding: .EUC_CN),
        ]

        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        throw DocumentTextExtractorError.unsupportedEncoding(url.lastPathComponent)
    }

    private static func extractAttributedText(from url: URL, documentType: String) throws -> String {
        do {
            let attributedText = try NSAttributedString(
                url: url,
                options: [.documentType: documentType],
                documentAttributes: nil
            )
            return attributedText.string
        } catch {
            throw DocumentTextExtractorError.extractionFailed(url.lastPathComponent, reason: error.localizedDescription)
        }
    }

    private static func extractPDFText(from url: URL) throws -> String {
#if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            throw DocumentTextExtractorError.extractionFailed(url.lastPathComponent, reason: "无法打开 PDF 文档。")
        }

        var pageTexts: [String] = []
        pageTexts.reserveCapacity(document.pageCount)

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), pageText.isEmpty == false else {
                continue
            }
            pageTexts.append(pageText)
        }

        let joinedText = pageTexts.joined(separator: "\n\n")
        guard joinedText.isEmpty == false else {
            throw DocumentTextExtractorError.noExtractableText(
                url.lastPathComponent,
                hint: "该 PDF 可能是扫描件、受保护文档，或本身不包含可复制的文字层。"
            )
        }

        return joinedText
#else
        throw DocumentTextExtractorError.extractionFailed(url.lastPathComponent, reason: "当前平台不支持 PDF 文本提取。")
#endif
    }

    private static func supportedKind(for url: URL) -> SupportedDocumentKind? {
        if let kind = kind(forPathExtension: url.pathExtension) {
            return kind
        }

        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return nil
        }

        if contentType.conforms(to: .pdf) {
            return .pdf
        }

        if contentType.conforms(to: .text) || contentType.conforms(to: .plainText) {
            return .plainText
        }

        for fileExtension in ["html", "rtf", "doc", "docx", "odt"] {
            if let type = UTType(filenameExtension: fileExtension), contentType.conforms(to: type) {
                return kind(forPathExtension: fileExtension)
            }
        }

        return nil
    }

    private static func kind(forPathExtension pathExtension: String) -> SupportedDocumentKind? {
        switch pathExtension.lowercased() {
        case "txt", "text", "md", "markdown", "json", "csv", "tsv", "log", "xml", "yaml", "yml", "ini", "conf":
            return .plainText
        case "html", "htm":
            return .attributed("NSHTML")
        case "rtf":
            return .attributed("NSRTF")
        case "doc":
            return .attributed("NSDocFormat")
        case "docx":
            return .attributed("NSOfficeOpenXML")
        case "odt":
            return .attributed("NSOpenDocument")
        case "pdf":
            return .pdf
        default:
            return nil
        }
    }
}

private enum SupportedDocumentKind {
    case plainText
    case attributed(String)
    case pdf
}

private enum DocumentTextExtractorError: LocalizedError {
    case unsupportedFileType(String)
    case unsupportedEncoding(String)
    case extractionFailed(String, reason: String)
    case noExtractableText(String, hint: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let filename):
            return "暂不支持文件“\(filename)”的格式。当前可导入 TXT / Markdown / JSON / CSV / XML / HTML / RTF / Word / ODT / PDF 等常见文档。"
        case .unsupportedEncoding(let filename):
            return "无法读取文件“\(filename)”。纯文本目前支持 UTF-8 / UTF-16 / GB18030 / Big5 / EUC-CN / ASCII / Latin-1 / Windows-1252 等常见编码。"
        case .extractionFailed(let filename, let reason):
            return "无法读取文件“\(filename)”：\(reason)"
        case .noExtractableText(let filename, let hint):
            return "文件“\(filename)”里没有可提取的文本。\(hint)"
        }
    }
}

private extension String.Encoding {
    init(cfEncoding: CFStringEncodings) {
        self = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue)))
    }
}