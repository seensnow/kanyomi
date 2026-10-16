import Testing
import Foundation
import WebKit
@testable import Kanyomi

struct FuriganaTests {
    @Test func systemReadingsAlignKanjiAndOkurigana() {
        let readings = FuriganaGenerator.readings(in: FuriganaBlock(id: 0, text: "😀 今日は学校で勉強して、食べました。取り戻した。"))
        #expect(readings.first(where: { $0.text == "学校" })?.reading == "がっこう")
        #expect(readings.first(where: { $0.text == "勉強" })?.reading == "べんきょう")
        #expect(readings.first(where: { $0.text == "食" })?.reading == "た")
        #expect(readings.first(where: { $0.text == "取" })?.reading == "と")
        #expect(readings.first(where: { $0.text == "戻" })?.reading == "もど")
        #expect(!readings.contains { $0.text.contains("べ") })
        let source = "😀 今日は学校で勉強して、食べました。取り戻した。" as NSString
        for reading in readings {
            #expect(source.substring(with: NSRange(location: reading.offset, length: reading.length)) == reading.text)
        }
        #expect(FuriganaGenerator.align(word: "食べ", reading: "くう").isEmpty)
        #expect(FuriganaGenerator.align(word: "かな", reading: "かな").isEmpty)
        #expect(FuriganaGenerator.align(word: "聞き取り", reading: "ききとり").map(\.reading) == ["き", "と"])
    }

    @Test func translationsAndLegacyPreferencesArePreserved() throws {
        #expect(FuriganaGenerator.readings(in: FuriganaBlock(id: 0,
            text: "与恋爱相关的常见悲剧，我早已见识过无数次。", language: "ja")).isEmpty)
        #expect(FuriganaGenerator.readings(in: FuriganaBlock(id: 0,
            text: "学校へ行く。", language: "zh-Hans")).isEmpty)
        #expect(FuriganaGenerator.readings(in: FuriganaBlock(id: 0, text: "This is English.")).isEmpty)
        let old = try JSONEncoder().encode(Preferences())
        let decoded = try JSONDecoder().decode(Preferences.self, from: old)
        #expect(decoded.autoFurigana == nil)
        #expect(decoded.showRuby)
        var updated = decoded; updated.autoFurigana = true
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(updated)).autoFurigana == true)
    }

    @Test @MainActor func nativeBridgePreservesPublisherRubySelectionAndOffsets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KanyomiFurigana-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReaderStore(root: root, startTimer: false)
        store.state.preferences.autoFurigana = true
        store.state.preferences.vertical = false
        let text = "今日は学校で勉強して、食べました。東京へ行く。与恋爱相关的常见悲剧，我早已见识过无数次。😀学校へ行く。"
        let book = Book(id: UUID(), title: "Furigana fixture", author: "", chapters: [Chapter(title: "One", path: "one.html", text: text)], contents: [])
        store.state.books = [book]; store.selectedBookID = book.id
        let coordinator = ReaderWebView.Coordinator(store)
        coordinator.chapterKey = "\(book.id):0"
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(coordinator, name: "reader")
        let script = try String(contentsOf: Bundle.module.url(forResource: "reader", withExtension: "js", subdirectory: "Resources")!)
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 1000), configuration: config)
        coordinator.web = web
        defer { coordinator.furiganaTask?.cancel(); config.userContentController.removeScriptMessageHandler(forName: "reader"); web.stopLoading() }
        web.loadHTMLString("""
        <html lang="ja"><body><p id="jp">今日は<span id="school">学校</span>で勉強して、食べました。<ruby id="publisher">東京<rt>とうきょう</rt></ruby>へ行く。</p>
        <p id="zh" style="opacity:.4">与恋爱相关的常见悲剧，我早已见识过无数次。</p><p id="emoji">😀学校へ行く。</p></body></html>
        """, baseURL: nil)
        func waitForRuby() async throws {
            for _ in 0..<100 {
                if coordinator.ready, try await web.evaluateJavaScript("document.querySelectorAll('ruby[data-sr-auto-ruby]').length") as? Int ?? 0 > 0 { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            Issue.record("Automatic furigana did not arrive through the native bridge")
        }
        try await waitForRuby()
        for vertical in [false, true] {
            store.state.preferences.vertical = vertical; coordinator.configure()
            try await Task.sleep(for: .milliseconds(250))
            let result = try await web.evaluateJavaScript("""
            (()=>{const clone=document.body.cloneNode(true);clone.querySelectorAll('rt,rp').forEach(el=>el.remove());
            return {base:clone.textContent.replace(/\\s/g,''),publisher:document.querySelector('#publisher').outerHTML,
              chinese:document.querySelector('#zh ruby')===null,school:document.querySelector('#school rt')?.textContent,
              nested:document.querySelector('ruby ruby')!==null,opacity:getComputedStyle(document.querySelector('#zh')).opacity,
              writing:getComputedStyle(document.body).writingMode};})()
            """) as! [String: Any]
            #expect(result["base"] as? String == text)
            #expect(result["publisher"] as? String == "<ruby id=\"publisher\">東京<rt>とうきょう</rt></ruby>")
            #expect(result["chinese"] as? Bool == true)
            #expect(result["school"] as? String == "がっこう")
            #expect(result["nested"] as? Bool == false)
            #expect(result["opacity"] as? String == "0.4")
            #expect(result["writing"] as? String == (vertical ? "vertical-rl" : "horizontal-tb"))
            let highlighted = try await web.evaluateJavaScript("sr.lookupHighlight(3,2);[...CSS.highlights.get('sr-lookup')].map(r=>r.toString()).join('')") as? String
            #expect(highlighted == "学校")
            let emojiOffset = (text as NSString).range(of: "😀学校").location + 2
            #expect(try await web.evaluateJavaScript("sr.lookupHighlight(\(emojiOffset),2);[...CSS.highlights.get('sr-lookup')].map(r=>r.toString()).join('')") as? String == "学校")
        }
        // A selection spanning ruby must send base text, without generated kana.
        _ = try await web.evaluateJavaScript("""
        (()=>{const ruby=document.querySelector('#school ruby'),r=document.createRange();r.setStart(ruby.firstChild,0);r.setEndAfter(ruby.lastChild);const s=getSelection();s.removeAllRanges();s.addRange(r);ruby.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0}))})()
        """)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.lookupText == "学校")
        #expect(store.selectionOffset == 3)
        _ = try await web.evaluateJavaScript("getSelection().removeAllRanges();sr.marks([{offset:3,text:'学校'}])")
        try await waitForRuby()
        #expect(try await web.evaluateJavaScript("document.querySelector('mark.sr-highlight').textContent.includes('学校')") as? Bool == true)
        store.state.preferences.showRuby = false; coordinator.configure()
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await web.evaluateJavaScript("document.querySelectorAll('ruby[data-sr-auto-ruby]').length") as? Int == 0)
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.querySelector('#publisher rt')).visibility") as? String == "hidden")
        store.state.preferences.showRuby = true; coordinator.configure()
        try await waitForRuby()
        store.state.preferences.autoFurigana = false; coordinator.configure()
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await web.evaluateJavaScript("document.querySelectorAll('ruby[data-sr-auto-ruby]').length") as? Int == 0)
        #expect(try await web.evaluateJavaScript("document.querySelector('#publisher rt').textContent") as? String == "とうきょう")
        // A late result cannot re-enable annotations after the setting is disabled.
        _ = try await web.evaluateJavaScript("sr.applyFurigana(1,[{id:0,readings:[{offset:0,length:2,text:'今日',reading:'きょう'}]}])")
        #expect(try await web.evaluateJavaScript("document.querySelectorAll('ruby[data-sr-auto-ruby]').length") as? Int == 0)
    }
}
