import Foundation
import CHoshiDicts

actor DictionaryEngine {
    private var query: OpaquePointer?
    private var deinflector: OpaquePointer?
    private var lookup: OpaquePointer?
    private var styles = ""
    init() { query = hd_query_new(); deinflector = hd_deinflector_new(); lookup = hd_lookup_new(query, deinflector) }
    deinit { hd_lookup_free(lookup); hd_deinflector_free(deinflector); hd_query_free(query) }
    func rebuild(_ dictionaries: [DictionaryRecord], root: URL) {
        hd_lookup_free(lookup); hd_query_free(query); query = hd_query_new()
        for d in dictionaries where d.enabled {
            let path = root.appendingPathComponent("Dictionaries/\(d.id)/\(d.title)").path
            if d.terms > 0 { _ = hd_query_add_term_dict(query, path) }
            if d.frequencies > 0 { _ = hd_query_add_freq_dict(query, path) }
            if d.pitches > 0 { _ = hd_query_add_pitch_dict(query, path) }
            if d.kanji > 0 { _ = hd_query_add_kanji_dict(query, path) }
        }
        lookup = hd_lookup_new(query, deinflector)
        var ptr: UnsafePointer<hd_dictionary_style>?; var count = 0
        let result = hd_query_get_styles(query, &ptr, &count); defer { hd_styles_free(result) }
        styles = buffer(ptr, count).map { string($0.styles) }.joined(separator: "\n")
    }
    func importZip(_ url: URL, root: URL) throws -> DictionaryRecord {
        let id = UUID().uuidString
        let destination = root.appendingPathComponent("Dictionaries/\(id)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            // Validate every archive entry before the upstream importer sees it.
            let staging = root.appendingPathComponent("Staging/\(id)")
            defer { try? FileManager.default.removeItem(at: staging) }
            try EPUBImporter.extract(url, to: staging)
            guard let index = try JSONSerialization.jsonObject(with: Data(contentsOf: staging.appendingPathComponent("index.json"))) as? [String: Any], let title = index["title"] as? String, !title.isEmpty, title != ".", title != "..", !title.contains("/"), !title.contains("\\") else { throw ReaderError.message("Invalid Yomitan dictionary title") }
            let result = hd_import(url.path, destination.path, 0)
            defer { hd_import_result_free(result) }
            guard let result, hd_import_result_success(result) != 0 else { throw ReaderError.message(result.map { String(cString: hd_import_result_error($0)) } ?? "Dictionary import failed") }
            return DictionaryRecord(id: id, title: String(cString: hd_import_result_title(result)), terms: Int(hd_import_result_term_count(result)), frequencies: Int(hd_import_result_freq_count(result)), pitches: Int(hd_import_result_pitch_count(result)), kanji: Int(hd_import_result_kanji_count(result)))
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    func search(_ text: String, scanLength: Int) -> [WordResult] {
        var pointer: UnsafePointer<hd_lookup_result>?; var count = 0
        let results = hd_lookup_run(lookup, text, 32, max(1, scanLength), &pointer, &count)
        defer { hd_lookup_results_free(results) }
        return buffer(pointer, count).map { r in
            let t = r.term
            let glossaries = buffer(t.glossaries, t.glossaries_count).map { g -> Glossary in
                let json = string(g.glossary); let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) ?? json
                let html = StructuredGlossary.glossary(obj, dictionary: string(g.dict_name))
                return Glossary(dictionary: string(g.dict_name), json: json, html: html, plain: StructuredGlossary.plain(obj), definitionTags: string(g.definition_tags).split(whereSeparator: { $0.isWhitespace }).map(String.init), termTags: string(g.term_tags).split(whereSeparator: { $0.isWhitespace }).map(String.init))
            }
            var frequencies: [String] = []; var values: [Int] = []
            for f in buffer(t.frequencies, t.frequencies_count) {
                for v in buffer(f.frequencies, f.frequencies_count) { values.append(Int(v.value)); frequencies.append("\(string(f.dict_name)): \(string(v.display_value).isEmpty ? String(v.value) : string(v.display_value))") }
            }
            var pitches: [String] = []; var positions: [Int] = []
            for p in buffer(t.pitches, t.pitches_count) {
                for v in buffer(p.pitches, p.pitches_count) { positions.append(Int(v.position)); pitches.append("\(string(p.dict_name)): [\(v.position)] \(string(v.pattern))") }
                pitches += buffer(p.transcriptions, p.transcriptions_count).map { string($0) }
            }
            return WordResult(expression: string(t.expression), reading: string(t.reading), matched: string(r.matched), reasons: buffer(r.trace, r.trace_count).map { string($0.name) }, glossaries: glossaries, frequencies: frequencies, frequencyValues: values, pitches: pitches, pitchPositions: positions)
        }
    }
    func kanji(_ text: String) -> String {
        var ptr: UnsafePointer<hd_kanji_entry>?; var count = 0
        let result = hd_query_run_kanji(query, text, &ptr, &count); defer { hd_kanji_results_free(result) }
        return buffer(ptr, count).map { k in "\(string(k.dict_name))\n音: \(string(k.onyomi))\n訓: \(string(k.kunyomi))\n" + buffer(k.definitions, k.definitions_count).map { string($0) }.joined(separator: "; ") }.joined(separator: "\n\n")
    }
    func media(dictionary: String, path: String) -> Data {
        let file = hd_query_get_media_file(query, dictionary, path)
        guard let ptr = file.data, file.size > 0 else { return Data() }; return Data(bytes: ptr, count: file.size)
    }
    func css() -> String { styles }
    private func string(_ s: hd_str) -> String { guard let ptr = s.ptr, s.len > 0 else { return "" }; return String(decoding: UnsafeRawBufferPointer(start: ptr, count: s.len), as: UTF8.self) }
    private func buffer<T>(_ p: UnsafePointer<T>?, _ count: Int) -> [T] { guard let p, count > 0 else { return [] }; return Array(UnsafeBufferPointer(start: p, count: count)) }
}
struct StructuredGlossary {
    static func plain(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let a = value as? [Any] { return a.map(plain).joined(separator: "\n") }
        if let d = value as? [String: Any] { return plain(d["content"] ?? d["text"] ?? d["description"] ?? "") }
        return ""
    }
    static func glossary(_ value: Any, dictionary: String) -> String {
        if let entries = value as? [Any], entries.count > 1, entries.allSatisfy({ $0 is String }) {
            return "<ul class=\"glossary-list\">" + entries.map { "<li>" + render($0, dictionary: dictionary) + "</li>" }.joined() + "</ul>"
        }
        return render(value, dictionary: dictionary)
    }
    static func render(_ value: Any, dictionary: String) -> String {
        if let s = value as? String { return escapeHTML(s).replacingOccurrences(of: "\n", with: "<br>") }
        if let a = value as? [Any] { return a.map { render($0, dictionary: dictionary) }.joined() }
        guard let d = value as? [String: Any] else { return "" }
        if d["type"] as? String == "structured-content" { return "<span class=\"structured-content\">" + render(d["content"] ?? "", dictionary: dictionary) + "</span>" }
        if d["type"] as? String == "image" || d["tag"] as? String == "img", let path = d["path"] as? String {
            var components = URLComponents(); components.scheme = "dictmedia"; components.host = "resource"; components.queryItems = [URLQueryItem(name: "dictionary", value: dictionary), URLQueryItem(name: "path", value: path)]
            return "<img src=\"\(escapeHTML(components.url?.absoluteString ?? ""))\" alt=\"\(escapeHTML(d["description"] as? String ?? ""))\" style=\"max-width:100%\">"
        }
        let allowed: Set<String> = ["div", "span", "p", "ruby", "rt", "rp", "table", "thead", "tbody", "tfoot", "tr", "td", "th", "ol", "ul", "li", "br", "b", "i", "strong", "em", "small", "details", "summary"]
        let tag = d["tag"] as? String ?? "span"
        let safeTag = allowed.contains(tag) ? tag : "span"
        var attrs = " class=\"gloss-sc-\(safeTag)\""
        if let style = d["style"] as? [String: Any] {
            let styles = style.compactMap { key, val -> String? in
                guard key.range(of: "^[a-zA-Z]+$", options: .regularExpression) != nil else { return nil }
                let cssKey = key.replacingOccurrences(of: "([A-Z])", with: "-$1", options: .regularExpression).lowercased()
                return "\(cssKey):\(escapeHTML(String(describing: val)))"
            }.joined(separator: ";"); attrs += " style=\"\(styles)\""
        }
        if let data = d["data"] as? [String: Any] {
            for (key, val) in data where key.range(of: "^[\\p{L}\\p{N}_-]+$", options: .regularExpression) != nil {
                let name = key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1-$2", options: .regularExpression).lowercased()
                let cjk = key.unicodeScalars.first.map { (0x3000...0x9fff).contains($0.value) || (0xf900...0xfaff).contains($0.value) } ?? false
                attrs += " data-sc\(cjk ? "" : "-")\(name)=\"\(escapeHTML(String(describing: val)))\""
            }
        }
        for key in ["colSpan", "rowSpan", "title", "lang"] { if let val = d[key] { attrs += " \(key.lowercased())=\"\(escapeHTML(String(describing: val)))\"" } }
        return "<\(safeTag)\(attrs)>\(render(d["content"] ?? "", dictionary: dictionary))</\(safeTag)>"
    }
}
