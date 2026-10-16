import Foundation
import CoreFoundation
import NaturalLanguage

struct FuriganaBlock: Sendable {
    let id: Int
    let text: String
    var language: String? = nil
}

struct FuriganaReading: Sendable {
    let offset: Int
    let length: Int
    let text: String
    let reading: String
    var json: [String: Any] { ["offset": offset, "length": length, "text": text, "reading": reading] }
}

struct FuriganaAnnotations: Sendable {
    let id: Int
    let readings: [FuriganaReading]
    var json: [String: Any] { ["id": id, "readings": readings.map(\.json)] }
}

enum FuriganaGenerator {
    static func annotate(_ blocks: [FuriganaBlock]) -> [FuriganaAnnotations] {
        var result: [FuriganaAnnotations] = []
        for block in blocks {
            if Task.isCancelled { break }
            result.append(FuriganaAnnotations(id: block.id, readings: readings(in: block)))
        }
        return result
    }

    static func readings(in block: FuriganaBlock) -> [FuriganaReading] {
        // Bilingual books sometimes label the entire document Japanese. Detect
        // each paragraph too, so Chinese translations do not acquire Japanese ruby.
        if let language = block.language, !language.isEmpty,
           language != "und", !language.lowercased().hasPrefix("ja") { return [] }
        guard block.text.range(of: "\\p{Han}", options: .regularExpression) != nil,
              NLLanguageRecognizer.dominantLanguage(for: block.text) == .japanese else { return [] }
        let source = block.text as NSString
        guard let tokenizer = CFStringTokenizerCreate(nil, block.text as CFString,
            CFRange(location: 0, length: source.length), kCFStringTokenizerUnitWord,
            Locale(identifier: "ja") as CFLocale) else { return [] }
        var result: [FuriganaReading] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            if Task.isCancelled { return [] }
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let word = source.substring(with: NSRange(location: range.location, length: range.length))
            guard word.range(of: "\\p{Han}", options: .regularExpression) != nil,
                  let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
                  let kana = latin.applyingTransform(.latinToHiragana, reverse: false)?.precomposedStringWithCanonicalMapping,
                  kana.range(of: "^[ぁ-ゖゝゞー]+$", options: .regularExpression) != nil else { continue }
            result += align(word: word, reading: kana, offset: range.location)
        }
        return result
    }

    // Align kana anchors before emitting anything. If a transcription cannot be
    // aligned, leave the token alone instead of guessing a reading for each kanji.
    static func align(word: String, reading: String, offset: Int = 0) -> [FuriganaReading] {
        var runs: [(text: String, kanji: Bool, offset: Int)] = []
        var position = offset
        for character in word {
            let text = String(character)
            let kanji = text.range(of: "[\\p{Han}々]", options: .regularExpression) != nil
            if runs.last?.kanji == kanji { runs[runs.count - 1].text += text }
            else { runs.append((text, kanji, position)) }
            position += text.utf16.count
        }
        func hiragana(_ text: String) -> String { text.applyingTransform(.hiraganaToKatakana, reverse: true) ?? text }
        var cursor = reading.startIndex
        var result: [FuriganaReading] = []
        for (index, run) in runs.enumerated() {
            if !run.kanji {
                let literal = hiragana(run.text)
                guard reading[cursor...].hasPrefix(literal) else { return [] }
                cursor = reading.index(cursor, offsetBy: literal.count)
            } else {
                guard cursor < reading.endIndex else { return [] }
                let next = index + 1 < runs.count ? hiragana(runs[index + 1].text) : ""
                let end: String.Index
                if next.isEmpty { end = reading.endIndex }
                else if let anchor = reading.range(of: next, range: reading.index(after: cursor)..<reading.endIndex) { end = anchor.lowerBound }
                else { return [] }
                guard end > cursor else { return [] }
                result.append(FuriganaReading(offset: run.offset, length: run.text.utf16.count,
                    text: run.text, reading: String(reading[cursor..<end])))
                cursor = end
            }
        }
        return cursor == reading.endIndex ? result : []
    }
}
