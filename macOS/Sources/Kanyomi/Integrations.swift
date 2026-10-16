import Foundation
import AVFoundation

struct AnkiClient {
    let preferences: Preferences
    let session: URLSession
    init(_ preferences: Preferences, session: URLSession = .shared) { self.preferences = preferences; self.session = session }
    func request(_ action: String, _ params: [String: Any] = [:]) async throws -> Any {
        guard let url = URL(string: preferences.ankiEndpoint), ["http", "https"].contains(url.scheme ?? "") else { throw ReaderError.message("Invalid AnkiConnect endpoint") }
        var payload: [String: Any] = ["action": action, "version": 6, "params": params]
        if !preferences.ankiKey.isEmpty { payload["key"] = preferences.ankiKey }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReaderError.message("Invalid AnkiConnect response") }
        if let error = obj["error"] as? String { throw ReaderError.message(error) }
        return obj["result"] ?? NSNull()
    }
}
struct AudioData { var data: Data; var ext: String }
struct AudioSource {
    static func resolve(_ template: String, result: WordResult) throws -> URL {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        let term = result.expression.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let reading = result.reading.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let value = template.replacingOccurrences(of: "{term}", with: term).replacingOccurrences(of: "{expression}", with: term).replacingOccurrences(of: "{reading}", with: reading)
        guard let url = URL(string: value), ["http", "https", "file"].contains(url.scheme ?? "") else { throw ReaderError.message("Invalid audio source URL") }; return url
    }
    static func download(_ url: URL, type: String) async throws -> AudioData {
        if url.isFileURL { return AudioData(data: try Data(contentsOf: url), ext: url.pathExtension.isEmpty ? "mp3" : url.pathExtension) }
        var request = URLRequest(url: url); request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ReaderError.message("Audio source returned an error") }
        if type == "Yomitan JSON" {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let list = obj["audioSources"] as? [[String: Any]], let source = list.first, let path = source["url"] as? String, let next = URL(string: path, relativeTo: url)?.absoluteURL else { throw ReaderError.message("Audio source has no audioSources entries") }
            return try await download(next, type: "Direct audio")
        }
        let mime = http.mimeType ?? ""
        guard !mime.contains("text/") && !mime.contains("json"), !data.isEmpty else { throw ReaderError.message("Audio source did not return audio") }
        let ext = mime.contains("wav") ? "wav" : mime.contains("ogg") ? "ogg" : mime.contains("mp4") ? "m4a" : "mp3"
        return AudioData(data: data, ext: ext)
    }
}
struct CardTemplate {
    static let supported = ["expression", "reading", "furigana-plain", "audio", "glossary", "glossary-brief", "glossary-no-dictionary", "glossary-first", "glossary-first-brief", "glossary-first-no-dictionary", "monolingual-definition", "monolingual-definition-brief", "monolingual-definition-no-dictionary", "bilingual-definition", "bilingual-definition-brief", "bilingual-definition-no-dictionary", "monolingual-definition-fallback", "monolingual-definition-fallback-brief", "monolingual-definition-fallback-no-dictionary", "bilingual-definition-fallback", "bilingual-definition-fallback-brief", "bilingual-definition-fallback-no-dictionary", "selected-glossary", "selected-glossary-brief", "selected-glossary-no-dictionary", "popup-selection-text", "sentence", "cloze-prefix", "cloze-body", "cloze-suffix", "frequencies", "frequency-harmonic-rank", "pitch-accent-positions", "pitch-accent-categories", "pitch-accent-graphs", "pitch-accent-graphs-first", "document-title", "book-cover", "sasayaki-audio"]
    static func render(_ template: String, result r: WordResult, sentence: String, selection: String, title: String, dictionaries: [DictionaryRecord], media: [String: String] = [:], selectedGlossary: Glossary? = nil) throws -> String {
        let range = sentence.range(of: r.matched)
        let prefix = range.map { String(sentence[..<$0.lowerBound]) } ?? ""
        let suffix = range.map { String(sentence[$0.upperBound...]) } ?? ""
        func glossary(_ list: [Glossary], brief: Bool = false, noDictionary: Bool = false) -> String {
            list.map { (noDictionary ? "" : "<small>\(escapeHTML($0.dictionary))</small>") + (brief ? escapeHTML($0.plain) : $0.html) }.joined(separator: "<br>")
        }
        let groups = dictionaries.reduce(into: [String: String]()) { $0[$1.title] = $1.category }
        let mono = r.glossaries.filter { groups[$0.dictionary] == "monolingual" }
        let bi = r.glossaries.filter { groups[$0.dictionary] != "monolingual" && groups[$0.dictionary] != "exclude" }
        let visible = r.glossaries.filter { groups[$0.dictionary] != "exclude" }
        let frequencies = r.frequencyValues.filter { $0 > 0 }; let harmonic = frequencies.isEmpty ? "" : String(Int(Double(frequencies.count) / frequencies.reduce(0.0) { $0 + 1.0 / Double($1) }))
        let mora = morae(r.reading)
        let graphs = r.pitchPositions.map { graph(mora: mora, position: $0) }
        var values: [String: String] = ["expression": escapeHTML(r.expression), "reading": escapeHTML(r.reading), "furigana-plain": furigana(expression: r.expression, reading: r.reading), "sentence": escapeHTML(sentence), "popup-selection-text": escapeHTML(selection), "cloze-prefix": escapeHTML(prefix), "cloze-body": escapeHTML(range == nil ? r.matched : String(sentence[range!])), "cloze-suffix": escapeHTML(suffix), "frequencies": r.frequencies.map(escapeHTML).joined(separator: "<br>"), "frequency-harmonic-rank": harmonic, "pitch-accent-positions": r.pitchPositions.map(String.init).joined(separator: ", "), "pitch-accent-categories": r.pitchPositions.map { $0 == 0 ? "平板" : $0 == 1 ? "頭高" : $0 == mora.count ? "尾高" : "中高" }.joined(separator: ", "), "pitch-accent-graphs": graphs.joined(), "pitch-accent-graphs-first": graphs.first ?? "", "document-title": escapeHTML(title), "audio": media["audio"] ?? "", "book-cover": media["book-cover"] ?? "", "sasayaki-audio": media["sasayaki-audio"] ?? ""]
        let lists: [(String, [Glossary])] = [("glossary", visible), ("glossary-first", Array(visible.prefix(1))), ("selected-glossary", selectedGlossary.map { [$0] } ?? Array(visible.prefix(1))), ("monolingual-definition", mono), ("bilingual-definition", bi), ("monolingual-definition-fallback", mono.isEmpty ? bi : mono), ("bilingual-definition-fallback", bi.isEmpty ? mono : bi)]
        for (name, list) in lists { values[name] = glossary(list); values[name + "-brief"] = glossary(list, brief: true, noDictionary: true); values[name + "-no-dictionary"] = glossary(list, noDictionary: true) }
        let regex = try NSRegularExpression(pattern: "\\{([a-z][a-z-]*)\\}")
        var text = template
        for m in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
            guard let tokenRange = Range(m.range(at: 1), in: template), let range = Range(m.range, in: text) else { continue }
            let name = String(template[tokenRange]); guard let value = values[name] else { throw ReaderError.message("Unknown Anki marker: {\(name)}") }; text.replaceSubrange(range, with: value)
        }
        return text
    }
    static func furigana(expression: String, reading: String) -> String {
        guard !reading.isEmpty, expression != reading else { return escapeHTML(expression) }
        func kanji(_ char: Character) -> Bool { char.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x2FFFF).contains($0.value) || $0.value == 0x3005 } }
        func hiragana(_ s: String) -> String { String(String.UnicodeScalarView(s.unicodeScalars.map { scalar in (0x30A1...0x30F6).contains(scalar.value) ? UnicodeScalar(scalar.value - 0x60)! : scalar })) }
        var runs: [(String, Bool)] = []
        for char in expression { let kind = kanji(char); if runs.last?.1 == kind { runs[runs.count - 1].0.append(char) } else { runs.append((String(char), kind)) } }
        let kana = hiragana(reading); var cursor = kana.startIndex; var output = ""
        for (i, run) in runs.enumerated() {
            if !run.1 {
                let literal = hiragana(run.0)
                guard kana[cursor...].hasPrefix(literal) else { return "\(escapeHTML(expression))[\(escapeHTML(reading))]" }
                cursor = kana.index(cursor, offsetBy: literal.count); output += escapeHTML(run.0)
            } else {
                let next = i + 1 < runs.count ? hiragana(runs[i + 1].0) : ""
                let end: String.Index
                if next.isEmpty { end = kana.endIndex }
                else if let range = kana.range(of: next, range: cursor..<kana.endIndex) { end = range.lowerBound }
                else { return "\(escapeHTML(expression))[\(escapeHTML(reading))]" }
                guard end > cursor else { return "\(escapeHTML(expression))[\(escapeHTML(reading))]" }
                output += "\(escapeHTML(run.0))[\(escapeHTML(String(kana[cursor..<end])))]"; cursor = end
            }
        }
        return cursor == kana.endIndex ? output : "\(escapeHTML(expression))[\(escapeHTML(reading))]"
    }
    static func morae(_ reading: String) -> [String] { var result: [String] = []; for char in reading { if "ゃゅょぁぃぅぇぉャュョァィゥェォ".contains(char), !result.isEmpty { result[result.count - 1].append(char) } else { result.append(String(char)) } }; return result }
    static func graph(mora: [String], position: Int) -> String {
        guard !mora.isEmpty else { return "" }
        let high: (Int) -> Bool = { i in position == 1 ? i == 0 : i > 0 && (position == 0 || i < position) }
        let points = (0...mora.count).map { "\(16 + $0 * 24),\(high($0) ? 12 : 32)" }.joined(separator: " ")
        let labels = mora.enumerated().map { "<text x=\"\(16 + $0.offset * 24)\" y=\"53\" text-anchor=\"middle\" font-size=\"14\">\(escapeHTML($0.element))</text>" }.joined()
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(48 + mora.count * 24)\" height=\"60\"><polyline points=\"\(points)\" stroke=\"#b3654b\" stroke-width=\"2\" fill=\"none\"/>\(labels)</svg>"
    }
}
struct Audiobook {
    static func parseSRT(_ source: String) -> [Cue] {
        let text = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = text.components(separatedBy: "\n\n")
        func seconds(_ s: String) -> Double? { let values = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").components(separatedBy: ":").compactMap(Double.init); guard values.count == 3 else { return nil }; return values[0] * 3600 + values[1] * 60 + values[2] }
        return blocks.enumerated().compactMap { index, block in
            let lines = block.components(separatedBy: "\n"); guard let i = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }; let range = lines[i].components(separatedBy: "-->")
            guard range.count == 2, let start = seconds(range[0]), let end = seconds(range[1].components(separatedBy: " ").first(where: { !$0.isEmpty }) ?? range[1]), end > start else { return nil }
            let text = lines.dropFirst(i + 1).joined(separator: " ").replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            return Cue(id: index, start: start, end: end, text: text)
        }
    }
    static func match(_ cues: [Cue], chapters: [Chapter]) -> [Cue] {
        func normalize(_ text: String) -> String { text.folding(options: [.widthInsensitive], locale: Locale(identifier: "ja")).replacingOccurrences(of: "[\\s\\p{P}]", with: "", options: .regularExpression) }
        let clean = chapters.map { normalize($0.text) }; var lastChapter = 0; var lastIndex = 0
        return cues.map { input in
            var cue = input; let needle = normalize(cue.text); guard !needle.isEmpty else { return cue }
            for ch in lastChapter..<chapters.count {
                let text = clean[ch] as NSString; let start = ch == lastChapter ? min(lastIndex, text.length) : 0
                let found = text.range(of: needle, range: NSRange(location: start, length: text.length - start))
                if found.location != NSNotFound {
                    // Map the normalized match back into original UTF-16 offsets.
                    let original = chapters[ch].text; var cleaned = 0; var offset = 0
                    for char in original { if cleaned >= found.location { break }; cleaned += normalize(String(char)).utf16.count; offset += String(char).utf16.count }
                    cue.chapter = ch; cue.offset = offset; lastChapter = ch; lastIndex = found.location + found.length; break
                }
            }; return cue
        }
    }
    static func clip(_ file: URL, start: Double, end: Double) async throws -> Data {
        let asset = AVURLAsset(url: file)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw ReaderError.message("This audiobook cannot be clipped") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a"); defer { try? FileManager.default.removeItem(at: output) }
        export.outputURL = output; export.outputFileType = .m4a; export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        await export.export(); guard export.status == .completed else { throw export.error ?? ReaderError.message("Audio export failed") }; return try Data(contentsOf: output)
    }
}
