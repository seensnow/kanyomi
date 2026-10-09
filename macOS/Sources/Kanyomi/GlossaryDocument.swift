import Foundation

struct GlossaryDocument {
    static func matches(_ words: [WordResult]) -> String {
        words.enumerated().map { index, word in
            let reading = word.reading == word.expression ? "" : "<span class=\"match-reading\">" + escapeHTML(word.reading) + "</span>"
            return """
            <section class="match-card" data-match="\(index)"><header><h2><span class="match-number">\(index + 1).</span> \(escapeHTML(word.expression))\(reading)</h2><button type="button" data-select-match="\(index)" aria-pressed="false">\(escapeHTML(L("Use for mining")))</button></header>\(entries(word))</section>
            """
        }.joined()
    }
    static func entries(_ word: WordResult) -> String {
        var output = ""
        if !word.pitchPositions.isEmpty {
            let mora = CardTemplate.morae(word.reading)
            let graphs = word.pitchPositions.map { position in
                let category = position == 0 ? "平板" : position == 1 ? "頭高" : position == mora.count ? "尾高" : "中高"
                return "<div class=\"pitch-item\"><span class=\"pitch-label\">\(category) [\(position)]</span>\(CardTemplate.graph(mora: mora, position: position))</div>"
            }.joined()
            output += "<section class=\"pitch-card\"><h2>\(escapeHTML(L("Pitch accent")))</h2>\(graphs)</section>"
        }
        // Preserve dictionary priority and each original glossary index for mining.
        var sources: [String] = []
        for glossary in word.glossaries where !sources.contains(glossary.dictionary) { sources.append(glossary.dictionary) }
        for source in sources {
            let glossaries = word.glossaries.enumerated().filter { $0.element.dictionary == source }
            let rows = glossaries.map { index, glossary in
                var tags: [String] = []
                for tag in glossary.definitionTags + glossary.termTags where !tags.contains(tag) { tags.append(tag) }
                let labels = tags.map { "<span class=\"glossary-tag\">\(escapeHTML($0))</span>" }.joined()
                return "<li data-glossary-index=\"\(index)\"><div class=\"glossary-tags\">\(labels)</div><div class=\"yomitan-glossary\">\(glossary.html)</div></li>"
            }.joined()
            let single = glossaries.count == 1 ? " single-definition" : ""
            output += "<details class=\"dictionary-card\" data-dictionary=\"\(escapeHTML(source))\" open><summary>\(escapeHTML(source))</summary><div class=\"definition-content\"><ol class=\"definition-list\(single)\">\(rows)</ol></div></details>"
        }
        return output
    }
    static func prepare(html: String, css: String, theme: String) -> String {
        let styles = Bundle.readerResources.url(forResource: "glossary", withExtension: "css", subdirectory: "Resources").flatMap { try? String(contentsOf: $0) } ?? ""
        let night = theme == "Night"
        let palette = night
            ? "--text-color:#e8e5e2;--fg:#e8e5e2;--muted:#b5aaa3;--canvas:#252525;--card:#303030;--border:#48413d;--blue:#e3a07d;--blue-bg:#3c302a;--green:#e3a07d;--green-bg:#3c302a;--amber:#e3a07d;--amber-bg:#3c302a;--purple:#e3a07d;--purple-bg:#3c302a;"
            : "--text-color:#26313b;--fg:#26313b;--muted:#617080;--canvas:#f4f6f9;--card:#fff;--border:#dce3ea;--blue:#9b4f31;--blue-bg:#f8eee8;--green:#9b4f31;--green-bg:#f8eee8;--amber:#9b4f31;--amber-bg:#f8eee8;--purple:#9b4f31;--purple-bg:#f8eee8;"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src dictmedia: data:;"><style>:root{\(palette)color-scheme:\(night ? "dark" : "light");}\(css)\(styles)</style></head><body>\(html)</body></html>
        """
    }
}
