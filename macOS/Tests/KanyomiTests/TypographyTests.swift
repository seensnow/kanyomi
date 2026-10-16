import Testing
import AppKit
import WebKit
import CoreText
@testable import Kanyomi

@MainActor
struct TypographyTests {
    let chinese = "与恋爱相关的常见悲剧，我早已见识过无数次。"
    let japanese = "恋にまつわるありがちな悲劇を、もう散々見てきた。"

    @Test func fallbackCoversWholeChineseSentence() {
        let plans = ReaderTypography.fallbacks(font: "Hiragino Mincho ProN", text: chinese + japanese)
        let plan = plans.first { $0["missing"]!.contains("爱") }!
        #expect(plan["missing"]!.contains("见"))
        let font = CTFontCreateWithName(plan["font"]! as CFString, 23, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: chinese, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        #expect(runs.count == 1)
        #expect(ReaderTypography.fallbacks(font: plan["font"]!, text: chinese).isEmpty)
        #expect(ReaderTypography.fallbacks(font: "Hiragino Mincho ProN", text: japanese).isEmpty)
    }

    @Test func bilingualParagraphsKeepUniformGlyphMetricsAndOffsets() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let handler = TypographyMessages()
        config.userContentController.add(handler, name: "reader")
        let script = try String(contentsOf: Bundle.module.url(forResource: "reader", withExtension: "js", subdirectory: "Resources")!)
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 1000), configuration: config)
        defer { config.userContentController.removeScriptMessageHandler(forName: "reader"); web.stopLoading() }
        // The source book labels the whole document Japanese, including translations.
        web.loadHTMLString("""
        <html lang="ja"><body><div><p id="zh">与恋<span>爱相关的常见悲剧</span>，我早已见识过无数次。</p>
        <p id="ja" style="opacity:.4">恋にまつわるありがちな悲劇を、もう散々見てきた。</p>
        <div id="container">爱<p id="nested"><span>日本語</span></p></div>
        <p id="ruby"><ruby>爱<rt>あい</rt></ruby></p></div></body></html>
        """, baseURL: nil)
        for _ in 0..<100 { if handler.ready { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(handler.ready); guard handler.ready else { return }
        let text = chinese + japanese + "爱日本語爱"
        let fallbacks = ReaderTypography.fallbacks(font: "Hiragino Mincho ProN", text: text)
        func configure(vertical: Bool, font: String, plans: [[String: String]]) async throws {
            let value = jsonString(["font": font, "fontFallbacks": plans, "vertical": vertical, "fontSize": 23, "lineHeight": 1.9, "background": "#252525", "foreground": "#e8e5e2", "showRuby": true, "scanLength": 24])
            _ = try await web.evaluateJavaScript("sr.configure(\(value));window.scrollTo(0,0)")
            try await Task.sleep(for: .milliseconds(250))
        }
        for vertical in [false, true] {
            try await configure(vertical: vertical, font: "Hiragino Mincho ProN", plans: fallbacks)
            let values = try await web.evaluateJavaScript("""
            (()=>{const zh=document.querySelector('#zh'),ja=document.querySelector('#ja');
            const walker=document.createTreeWalker(zh,NodeFilter.SHOW_TEXT),rects=[];
            while(walker.nextNode()){const n=walker.currentNode;for(let i=0;i<n.length;i++){const r=document.createRange();r.setStart(n,i);r.setEnd(n,i+1);rects.push(r.getBoundingClientRect())}}
            return {zh:getComputedStyle(zh).fontFamily,span:getComputedStyle(zh.querySelector('span')).fontFamily,
              ja:getComputedStyle(ja).fontFamily,nested:getComputedStyle(document.querySelector('#nested span')).fontFamily,
              spread:Math.max(...rects.map(r=>\(vertical ? "r.left" : "r.top")))-Math.min(...rects.map(r=>\(vertical ? "r.left" : "r.top"))),
              opacity:getComputedStyle(ja).opacity,text:zh.textContent};})()
            """) as! [String: Any]
            #expect((values["zh"] as! String).contains(fallbacks[0]["font"]!))
            #expect(values["zh"] as? String == values["span"] as? String)
            #expect((values["ja"] as! String).hasPrefix("\"Hiragino Mincho ProN\""))
            #expect(values["ja"] as? String == values["nested"] as? String)
            #expect((values["spread"] as! Double) < 0.5)
            #expect(values["opacity"] as? String == "0.4")
            #expect(values["text"] as? String == chinese)
            let offset = chinese.utf16.count
            let highlighted = try await web.evaluateJavaScript("sr.lookupHighlight(\(offset),2);[...CSS.highlights.get('sr-lookup')].map(r=>r.toString()).join('')") as? String
            #expect(highlighted == "恋に")
        }
        try await configure(vertical: false, font: "Songti SC", plans: [])
        #expect(try await web.evaluateJavaScript("document.querySelectorAll('[data-sr-font]').length") as? Int == 0)
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.querySelector('#zh')).fontFamily") as? String == "\"Songti SC\", serif")
    }
}

@MainActor private final class TypographyMessages: NSObject, WKScriptMessageHandler {
    var ready = false
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.body as? [String: Any])?["type"] as? String == "ready" { ready = true }
    }
}
