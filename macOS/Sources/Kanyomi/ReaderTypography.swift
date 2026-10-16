import Foundation
import CoreText

enum ReaderTypography {
    // Resolve missing Han glyphs once per chapter/font, rather than allowing the
    // browser to mix fonts with incompatible character metrics within a line.
    static func fallbacks(font name: String, text: String) -> [[String: String]] {
        let font = CTFontCreateWithName(name as CFString, 24, nil)
        let coverage = CTFontCopyCharacterSet(font)
        let han = Set(text.unicodeScalars.filter(isHan)).sorted { $0.value < $1.value }
        let missing = han.filter { !CFCharacterSetIsLongCharacterMember(coverage, $0.value) }
        var families: [String: String] = [:]
        for scalar in missing {
            let character = String(scalar)
            let fallback = CTFontCreateForString(font, character as CFString, CFRange(location: 0, length: character.utf16.count))
            let family = CTFontCopyFamilyName(fallback) as String
            families[family, default: ""] += character
        }
        return families.keys.sorted().map { family in
            let fallback = CTFontCreateWithName(family as CFString, 24, nil)
            let coverage = CTFontCopyCharacterSet(fallback)
            let supported = han.filter { CFCharacterSetIsLongCharacterMember(coverage, $0.value) }
            return ["font": family, "missing": families[family]!, "supported": supported.map { String($0) }.joined()]
        }
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9fff).contains(scalar.value)
            || (0xf900...0xfaff).contains(scalar.value)
            || (0x20000...0x323af).contains(scalar.value)
    }
}
