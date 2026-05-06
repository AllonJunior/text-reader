import Foundation

struct PinyinPhonemizationDebugInfo: Codable, Equatable {
    let normalizedText: String
    let tokens: [String]
    let symbols: [String]
    let usedExternalOverride: Bool
    let externalOverrideSourceDescription: String?
}

/// Offline phonemizer for the bundled `zh_CN-xiao_ya-medium` voice.
///
/// Uses the system Mandarin Latin transform to convert most Hanzi into numbered pinyin,
/// then decomposes each syllable into Piper-compatible initial/final/tone symbols.
enum SimpleZhPinyinPhonemizer {
    private static let initials = [
        "zh", "ch", "sh",
        "b", "p", "m", "f",
        "d", "t", "n", "l",
        "g", "k", "h",
        "j", "q", "x",
        "r", "z", "c", "s",
        "y", "w"
    ]

    /// Pragmatic overrides for common Mandarin polyphonic words.
    ///
    /// The bundled `xiao_ya` voice was trained with a stronger Chinese G2P frontend
    /// (see model card mention of g2pW). Without a full offline lexicon here, the
    /// system Mandarin transform still misreads many high-frequency words like
    /// “银行 / 音乐 / 长大 / 地上”. These overrides fix the most obvious cases first.
    private static let phrasePinyinOverrides: [String: [String]] = [
        // Official XiaoYa sample text clauses/phrases. The model card explicitly notes
        // a dependency on g2pW, so we give the bundled comparison sample a stronger
        // fallback path here to reduce context-sensitive G2P errors in the demo text.
        "又稱": ["you4", "cheng1"],
        "天弓": ["tian1", "gong1"],
        "天虹": ["tian1", "hong2"],
        "簡稱": ["jian3", "cheng1"],
        "氣象": ["qi4", "xiang4"],
        "一種": ["yi4", "zhong3"],
        "光學": ["guang1", "xue2"],
        "現象": ["xian4", "xiang4"],
        "太陽光": ["tai4", "yang2", "guang1"],
        "照射": ["zhao4", "she4"],
        "半空中": ["ban4", "kong1", "zhong1"],
        "水滴": ["shui3", "di1"],
        "光線": ["guang1", "xian4"],
        "折射": ["zhe2", "she4"],
        "反射": ["fan3", "she4"],
        "天空上": ["tian1", "kong1", "shang4"],
        "形成": ["xing2", "cheng2"],
        "拱形": ["gong3", "xing2"],
        "七彩": ["qi1", "cai3"],
        "光譜": ["guang1", "pu3"],
        "外圈": ["wai4", "quan1"],
        "內圈": ["nei4", "quan1"],
        "顏色": ["yan2", "se4"],
        "霓虹": ["ni2", "hong2"],
        "相反": ["xiang1", "fan3"],
        "是氣象中的一種光學現象": ["shi4", "qi4", "xiang4", "zhong1", "de5", "yi4", "zhong3", "guang1", "xue2", "xian4", "xiang4"],
        "當太陽光照射到半空中的水滴時": ["dang1", "tai4", "yang2", "guang1", "zhao4", "she4", "dao4", "ban4", "kong1", "zhong1", "de5", "shui3", "di1", "shi2"],
        "光線被折射及反射": ["guang1", "xian4", "bei4", "zhe2", "she4", "ji2", "fan3", "she4"],
        "在天空上形成拱形的七彩光譜": ["zai4", "tian1", "kong1", "shang4", "xing2", "cheng2", "gong3", "xing2", "de5", "qi1", "cai3", "guang1", "pu3"],
        "由外圈至內圈呈紅": ["you2", "wai4", "quan1", "zhi4", "nei4", "quan1", "cheng2", "hong2"],
        "紫七種顏色": ["zi3", "qi1", "zhong3", "yan2", "se4"],
        "霓虹則相反": ["ni2", "hong2", "ze2", "xiang1", "fan3"],

        "银行行长": ["yin2", "hang2", "hang2", "zhang3"],
        "银行": ["yin2", "hang2"],
        "行长": ["hang2", "zhang3"],
        "行业": ["hang2", "ye4"],
        "外行": ["wai4", "hang2"],
        "内行": ["nei4", "hang2"],
        "同行": ["tong2", "hang2"],
        "一行": ["yi1", "hang2"],
        "行列": ["hang2", "lie4"],
        "字行": ["zi4", "hang2"],
        "排行": ["pai2", "hang2"],
        "行走": ["xing2", "zou3"],
        "行人": ["xing2", "ren2"],
        "行为": ["xing2", "wei2"],
        "不行": ["bu4", "xing2"],
        "可以": ["ke3", "yi3"],

        "重庆": ["chong2", "qing4"],
        "重新": ["chong2", "xin1"],
        "重复": ["chong2", "fu4"],
        "重阳": ["chong2", "yang2"],
        "重来": ["chong2", "lai2"],
        "重要": ["zhong4", "yao4"],
        "重量": ["zhong4", "liang4"],
        "重大": ["zhong4", "da4"],
        "重视": ["zhong4", "shi4"],

        "长大": ["zhang3", "da4"],
        "长高": ["zhang3", "gao1"],
        "成长": ["cheng2", "zhang3"],
        "生长": ["sheng1", "zhang3"],
        "长成": ["zhang3", "cheng2"],
        "校长": ["xiao4", "zhang3"],
        "院长": ["yuan4", "zhang3"],
        "班长": ["ban1", "zhang3"],
        "市长": ["shi4", "zhang3"],
        "船长": ["chuan2", "zhang3"],
        "厂长": ["chang3", "zhang3"],
        "部长": ["bu4", "zhang3"],
        "长江": ["chang2", "jiang1"],
        "长城": ["chang2", "cheng2"],
        "长久": ["chang2", "jiu3"],
        "长短": ["chang2", "duan3"],
        "长远": ["chang2", "yuan3"],

        "音乐": ["yin1", "yue4"],
        "乐器": ["yue4", "qi4"],
        "乐队": ["yue4", "dui4"],
        "乐谱": ["yue4", "pu3"],
        "奏乐": ["zou4", "yue4"],
        "快乐": ["kuai4", "le4"],
        "欢乐": ["huan1", "le4"],
        "可乐": ["ke3", "le4"],
        "娱乐": ["yu2", "le4"],
        "安乐": ["an1", "le4"],

        "朝阳": ["chao2", "yang2"],
        "朝着": ["chao2", "zhe5"],
        "朝向": ["chao2", "xiang4"],
        "朝前": ["chao2", "qian2"],
        "朝后": ["chao2", "hou4"],
        "王朝": ["wang2", "chao2"],
        "朝代": ["chao2", "dai4"],
        "朝廷": ["chao2", "ting2"],
        "今朝": ["jin1", "zhao1"],
        "明朝": ["ming2", "zhao1"],
        "朝霞": ["zhao1", "xia2"],

        "地方": ["di4", "fang1"],
        "地方上": ["di4", "fang1", "shang4"],
        "地上": ["di4", "shang4"],
        "地下": ["di4", "xia4"],
        "地面": ["di4", "mian4"],
        "地图": ["di4", "tu2"],
        "地址": ["di4", "zhi3"],
        "地球": ["di4", "qiu2"],
        "地板": ["di4", "ban3"],
        "地铁": ["di4", "tie3"],
        "地震": ["di4", "zhen4"],
        "大地": ["da4", "di4"],
        "土地": ["tu3", "di4"],
        "天地": ["tian1", "di4"],
        "目的": ["mu4", "di4"],

        "觉得": ["jue2", "de5"],
        "得了": ["de2", "le5"],
        "得很": ["de5", "hen3"],
        "得到": ["de2", "dao4"],
        "得出": ["de2", "chu1"],
        "舍得": ["she3", "de2"],

        "还有": ["hai2", "you3"],
        "什么": ["shen2", "me5"],
        "怎么": ["zen3", "me5"],
        "这么": ["zhe4", "me5"],
        "那么": ["na4", "me5"],
        "他们": ["ta1", "men5"],
        "我们": ["wo3", "men5"],
        "你们": ["ni3", "men5"],
        "她们": ["ta1", "men5"],
    ]

    private static let sortedOverrideKeys = phrasePinyinOverrides.keys.sorted { lhs, rhs in
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs > rhs
    }

    /// Returns Piper symbols like: ["^", "n", "i", "3", "h", "ao", "3", "$"].
    static func phonemizeToPiperSymbols(
        _ text: String,
        explicitTokens: [String]? = nil,
        externalOverrideSourceDescription: String? = nil,
        pinyinMode: PiperPinyinMode = .orthographic
    ) -> [String] {
        debugInfo(
            for: text,
            explicitTokens: explicitTokens,
            externalOverrideSourceDescription: externalOverrideSourceDescription,
            pinyinMode: pinyinMode
        )?.symbols ?? []
    }

    static func debugInfo(
        for text: String,
        explicitTokens: [String]? = nil,
        externalOverrideSourceDescription: String? = nil,
        pinyinMode: PiperPinyinMode = .orthographic
    ) -> PinyinPhonemizationDebugInfo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicitTokens, !explicitTokens.isEmpty {
            return PinyinPhonemizationDebugInfo(
                normalizedText: trimmed,
                tokens: explicitTokens,
                symbols: phonemizeExplicitTokensToPiperSymbols(explicitTokens, pinyinMode: pinyinMode),
                usedExternalOverride: true,
                externalOverrideSourceDescription: externalOverrideSourceDescription
            )
        }

        if let override = ExternalPinyinOverrideStore.shared.matchedOverride(for: trimmed) {
            return PinyinPhonemizationDebugInfo(
                normalizedText: trimmed,
                tokens: override.tokens,
                symbols: phonemizeExplicitTokensToPiperSymbols(override.tokens, pinyinMode: pinyinMode),
                usedExternalOverride: true,
                externalOverrideSourceDescription: override.sourceDescription
            )
        }

        let normalizedTokens = tokenize(trimmed).map { token -> String in
            switch token {
            case .syllable(let syllable):
                return syllable
            case .punctuation(let punctuation):
                return punctuation
            case .pause:
                return " "
            }
        }

        var out: [String] = ["^"]

        func appendPauseIfNeeded() {
            guard let last = out.last, last != "^", last != " " else { return }
            out.append(" ")
        }

        for token in tokenize(trimmed) {
            switch token {
            case .syllable(let syllable):
                guard let symbols = decomposeNumberedPinyin(syllable, pinyinMode: pinyinMode) else {
                    appendPauseIfNeeded()
                    continue
                }
                out.append(contentsOf: symbols)
            case .punctuation(let punctuation):
                while out.last == " " { out.removeLast() }
                out.append(punctuation)
            case .pause:
                appendPauseIfNeeded()
            }
        }

        while out.last == " " { out.removeLast() }
        out.append("$")

        return PinyinPhonemizationDebugInfo(
            normalizedText: trimmed,
            tokens: normalizedTokens,
            symbols: out,
            usedExternalOverride: false,
            externalOverrideSourceDescription: nil
        )
    }

    // MARK: - Tokenization

    private enum Token {
        case syllable(String)
        case punctuation(String)
        case pause
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        tokens.reserveCapacity(text.count)
        let characters = Array(text)

        var currentChunk = ""

        func appendPauseTokenIfNeeded() {
            if case .pause? = tokens.last {
                return
            }
            tokens.append(.pause)
        }

        func flushCurrentChunk() {
            let chunk = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            currentChunk = ""
            guard !chunk.isEmpty else { return }

            let mutable = NSMutableString(string: chunk) as CFMutableString
            CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
            let latin = (mutable as String).lowercased()

            var syllables: [String] = []
            syllables.reserveCapacity(latin.count / 2)
            for rawToken in latin.split(whereSeparator: { $0.isWhitespace }) {
                let token = String(rawToken).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { continue }
                syllables.append(numberedPinyin(from: token))
            }

            for syllable in applyContextToneAdjustments(to: syllables) {
                tokens.append(.syllable(syllable))
            }
        }

        var index = 0
        while index < characters.count {
            let ch = characters[index]

            if ch.isWhitespace {
                flushCurrentChunk()
                appendPauseTokenIfNeeded()
                index += 1
                continue
            }

            if isPunctuation(ch) {
                flushCurrentChunk()
                tokens.append(.punctuation(String(ch)))
                index += 1
                continue
            }

            if isIgnorableDelimiter(ch) {
                flushCurrentChunk()
                index += 1
                continue
            }

            if let override = bestPhraseOverride(in: characters, from: index) {
                flushCurrentChunk()
                tokens.append(contentsOf: override.syllables.map(Token.syllable))
                index += override.length
                continue
            }

            currentChunk.append(ch)
            index += 1
        }

        flushCurrentChunk()
        return tokens
    }

    private static func bestPhraseOverride(in characters: [Character], from start: Int) -> (length: Int, syllables: [String])? {
        guard start < characters.count else { return nil }

        for key in sortedOverrideKeys {
            let length = key.count
            guard start + length <= characters.count else { continue }

            let candidate = String(characters[start..<(start + length)])
            if candidate == key, let syllables = phrasePinyinOverrides[key] {
                return (length, syllables)
            }
        }

        return nil
    }

    // MARK: - Pinyin normalization

    private static func numberedPinyin(from syllable: String) -> String {
        var tone = 5
        var body = ""
        body.reserveCapacity(syllable.count)

        for ch in syllable {
            switch ch {
            case "ā": body.append("a"); tone = 1
            case "á": body.append("a"); tone = 2
            case "ǎ": body.append("a"); tone = 3
            case "à": body.append("a"); tone = 4
            case "ē": body.append("e"); tone = 1
            case "é": body.append("e"); tone = 2
            case "ě": body.append("e"); tone = 3
            case "è": body.append("e"); tone = 4
            case "ī": body.append("i"); tone = 1
            case "í": body.append("i"); tone = 2
            case "ǐ": body.append("i"); tone = 3
            case "ì": body.append("i"); tone = 4
            case "ō": body.append("o"); tone = 1
            case "ó": body.append("o"); tone = 2
            case "ǒ": body.append("o"); tone = 3
            case "ò": body.append("o"); tone = 4
            case "ū": body.append("u"); tone = 1
            case "ú": body.append("u"); tone = 2
            case "ǔ": body.append("u"); tone = 3
            case "ù": body.append("u"); tone = 4
            case "ǖ": body.append("v"); tone = 1
            case "ǘ": body.append("v"); tone = 2
            case "ǚ": body.append("v"); tone = 3
            case "ǜ": body.append("v"); tone = 4
            case "ü": body.append("v")
            default:
                if ch.isASCII {
                    body.append(ch)
                }
            }
        }

        if let last = body.last, last.isNumber {
            return body
        }

        return body + String(tone)
    }

    private static func phonemizeExplicitTokensToPiperSymbols(
        _ tokens: [String],
        pinyinMode: PiperPinyinMode
    ) -> [String] {
        var out: [String] = ["^"]

        func appendPauseIfNeeded() {
            guard let last = out.last, last != "^", last != " " else { return }
            out.append(" ")
        }

        for token in tokens {
            if token.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                appendPauseIfNeeded()
                continue
            }

            if let symbols = decomposeNumberedPinyin(token, pinyinMode: pinyinMode) {
                out.append(contentsOf: symbols)
                continue
            }

            for character in token {
                if character.isWhitespace {
                    appendPauseIfNeeded()
                    continue
                }
                if isIgnorableDelimiter(character) {
                    continue
                }
                if isPunctuation(character) {
                    while out.last == " " { out.removeLast() }
                    out.append(String(character))
                    continue
                }
                appendPauseIfNeeded()
            }
        }

        while out.last == " " { out.removeLast() }
        out.append("$")
        return out
    }

    private static func applyContextToneAdjustments(to syllables: [String]) -> [String] {
        guard syllables.count > 1 else { return syllables }

        var adjusted = syllables
        for index in adjusted.indices {
            let current = adjusted[index]
            guard let currentTone = toneNumber(in: current) else { continue }
            let body = String(current.dropLast())

            if body == "bu", index + 1 < adjusted.count,
               let nextTone = toneNumber(in: adjusted[index + 1]), nextTone == 4 {
                adjusted[index] = "bu2"
                continue
            }

            if body == "yi", index + 1 < adjusted.count,
               let nextTone = toneNumber(in: adjusted[index + 1]) {
                switch nextTone {
                case 4:
                    adjusted[index] = "yi2"
                case 1, 2, 3:
                    adjusted[index] = "yi4"
                default:
                    adjusted[index] = currentTone == 5 ? "yi1" : current
                }
            }
        }

        return adjusted
    }

    private static func toneNumber(in syllable: String) -> Int? {
        guard let last = syllable.last, let value = last.wholeNumberValue else {
            return nil
        }
        return value
    }

    private static func decomposeNumberedPinyin(
        _ syllable: String,
        pinyinMode: PiperPinyinMode
    ) -> [String]? {
        guard let toneChar = syllable.last, toneChar.isNumber else { return nil }

        let tone = String(toneChar)
        var body = String(syllable.dropLast())
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        // Normalize uncommon forms from Latin transform.
        body = body
            .replacingOccurrences(of: "u:", with: "v")
            .replacingOccurrences(of: "ü", with: "v")

        // "ng" can appear standalone as an interjection; map to the dedicated silent initial.
        if body == "ng" {
            return ["Ø", "eng", tone]
        }

        var initial = initials.first(where: { body.hasPrefix($0) }) ?? ""
        var final = initial.isEmpty ? body : String(body.dropFirst(initial.count))

        if pinyinMode == .zeroInitialNormalized {
            if let normalized = normalizeZeroInitialSyllable(initial: initial, final: final) {
                initial = normalized.initial
                final = normalized.final
            }
        }

        if ["j", "q", "x"].contains(initial), final.hasPrefix("u") {
            final = "v" + final.dropFirst()
        }

        guard !final.isEmpty else { return nil }
        return initial.isEmpty ? ["Ø", final, tone] : [initial, final, tone]
    }

    private static func normalizeZeroInitialSyllable(initial: String, final: String) -> (initial: String, final: String)? {
        switch initial {
        case "y":
            switch final {
            case "i": return ("", "i")
            case "in": return ("", "in")
            case "ing": return ("", "ing")
            case "a": return ("", "ia")
            case "an": return ("", "ian")
            case "ang": return ("", "iang")
            case "ao": return ("", "iao")
            case "e": return ("", "ie")
            case "ou": return ("", "iu")
            case "ong": return ("", "iong")
            case "u": return ("", "v")
            case "ue": return ("", "ve")
            case "uan": return ("", "van")
            case "un": return ("", "vn")
            default: return nil
            }
        case "w":
            switch final {
            case "u": return ("", "u")
            case "a": return ("", "ua")
            case "ai": return ("", "uai")
            case "an": return ("", "uan")
            case "ang": return ("", "uang")
            case "ei": return ("", "ui")
            case "en": return ("", "un")
            case "eng": return ("", "ueng")
            case "o": return ("", "uo")
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func isIgnorableDelimiter(_ ch: Character) -> Bool {
        switch ch {
        case "\"", "'", "“", "”", "‘", "’", "「", "」", "『", "』", "《", "》", "〈", "〉", "【", "】", "[", "]", "(", ")", "（", "）":
            return true
        default:
            return false
        }
    }

    private static func isPunctuation(_ ch: Character) -> Bool {
        switch ch {
        case "。", "，", "、", "！", "？", ".", ",", "!", "?", "：", ":", "；", ";", "…", "—":
            return true
        default:
            return false
        }
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
