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
            ? "--text-color:#e8e9ec;--fg:#e8e9ec;--muted:#a6abb5;--canvas:#202226;--card:#282b30;--border:#3b4048;--blue:#91baff;--blue-bg:#243345;--green:#8bdbbc;--green-bg:#233b34;--amber:#f0cd87;--amber-bg:#453c2a;--purple:#c9b3ff;--purple-bg:#342c45;"
            : "--text-color:#26313b;--fg:#26313b;--muted:#617080;--canvas:#f4f6f9;--card:#fff;--border:#dce3ea;--blue:#2766ad;--blue-bg:#edf4fd;--green:#267257;--green-bg:#edf7f2;--amber:#80590c;--amber-bg:#fff4d9;--purple:#7450a5;--purple-bg:#f2edfc;"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src dictmedia: data:;"><style>:root{\(palette)color-scheme:\(night ? "dark" : "light");}\(css)\(styles)</style></head><body>\(html)</body></html>
        """
    }
}
