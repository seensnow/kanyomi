import Testing
import AppKit
import WebKit
@testable import Kanyomi

@MainActor
struct PointerTests {
    @Test func glyphBoundsAndPersistentMatchedHighlight() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let handler = PointerMessages()
        config.userContentController.add(handler, name: "reader")
        let script = try String(contentsOf: Bundle.module.url(forResource: "reader", withExtension: "js", subdirectory: "Resources")!)
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 650), configuration: config)
        defer { config.userContentController.removeScriptMessageHandler(forName: "reader"); web.stopLoading() }
        web.loadHTMLString("<html><body><p><span id='verb'>憑かれて</span><ruby><span id='word'>優先順位</span><rt id='reading'>ゆうせんじゅんい</rt></ruby>。</p><p id='space'>空　白</p></body></html>", baseURL: nil)
        for _ in 0..<100 { if handler.ready { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(handler.ready); guard handler.ready else { return }
        for vertical in [true, false] {
            _ = try await web.evaluateJavaScript("sr.configure({vertical:\(vertical),font:'serif',fontSize:28,lineHeight:2,background:'#fff',foreground:'#000',showRuby:true,scanLength:24});window.scrollTo(0,0)")
            try await Task.sleep(for: .milliseconds(250))
            for fraction in [0.2, 0.8] {
                handler.lookups = []
                _ = try await web.evaluateJavaScript("""
                (()=>{const n=document.querySelector('#verb').firstChild,r=document.createRange();r.setStart(n,3);r.setEnd(n,4);const b=r.getBoundingClientRect();document.elementFromPoint(b.left+b.width*\(vertical ? 0.5 : fraction),b.top+b.height*\(vertical ? fraction : 0.5)).dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0,clientX:b.left+b.width*\(vertical ? 0.5 : fraction),clientY:b.top+b.height*\(vertical ? fraction : 0.5)}))})()
                """)
                try await Task.sleep(for: .milliseconds(30))
                #expect(handler.lookups.count == 1)
                #expect(handler.lookups.first?["offset"] as? Int == 3)
                #expect((handler.lookups.first?["text"] as? String)?.hasPrefix("て優先順位") == true)
            }
            // A caret can be placed in whitespace, but a lookup must not start there.
            handler.lookups = []
            for selector in ["#space", "#reading"] {
                _ = try await web.evaluateJavaScript("""
                (()=>{const n=document.querySelector('\(selector)').firstChild,r=document.createRange();r.setStart(n,1);r.setEnd(n,2);const b=r.getBoundingClientRect();document.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,button:0,clientX:b.left+b.width/2,clientY:b.top+b.height/2}))})()
                """)
            }
            try await Task.sleep(for: .milliseconds(30))
            #expect(handler.lookups.isEmpty)
            // Moving within the same glyph should not queue repeated dictionary searches.
            _ = try await web.evaluateJavaScript("""
            (()=>{const n=document.querySelector('#word').firstChild,r=document.createRange();r.setStart(n,0);r.setEnd(n,1);const b=r.getBoundingClientRect();window.moveOnWord=()=>document.dispatchEvent(new MouseEvent('mousemove',{bubbles:true,shiftKey:true,clientX:b.left+b.width/2,clientY:b.top+b.height/2}));moveOnWord()})()
            """)
            try await Task.sleep(for: .milliseconds(100))
            _ = try await web.evaluateJavaScript("moveOnWord();moveOnWord()")
            try await Task.sleep(for: .milliseconds(100))
            #expect(handler.lookups.count == 1)
            #expect(handler.lookups.first?["offset"] as? Int == 4)
            // The match may cross spans/ruby. Ruby readings are excluded from the highlight.
            let highlighted = try await web.evaluateJavaScript("sr.lookupHighlight(3,5);[...CSS.highlights.get('sr-lookup')].map(r=>r.toString()).join('')") as? String
            #expect(highlighted == "て優先順位")
            _ = try await web.evaluateJavaScript("window.getSelection().removeAllRanges();window.dispatchEvent(new Event('blur'))")
            let retained = try await web.evaluateJavaScript("[...CSS.highlights.get('sr-lookup')].map(r=>r.toString()).join('')") as? String
            #expect(retained == highlighted)
            _ = try await web.evaluateJavaScript("sr.lookupHighlight(0,0)")
            #expect(try await web.evaluateJavaScript("CSS.highlights.get('sr-lookup').size") as? Int == 0)
        }
    }
}
@MainActor private final class PointerMessages: NSObject, WKScriptMessageHandler {
    var ready = false
    var lookups: [[String: Any]] = []
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let data = message.body as? [String: Any] else { return }
        if data["type"] as? String == "ready" { ready = true }
        if data["type"] as? String == "lookup" { lookups.append(data) }
    }
}
