import Testing
import Foundation
import WebKit
@testable import SimpleReader

struct GlossaryTests {
    static var content: [String: Any] {
        ["type": "structured-content", "content": ["tag": "div", "data": ["content": "sense-group"], "content": [
            ["tag": "span", "data": ["class": "tag", "content": "part-of-speech-info"], "content": "noun"],
            ["tag": "ul", "data": ["content": "glossary"], "content": [["tag": "li", "content": "romantic love"]]],
            ["tag": "div", "data": ["content": "example-sentence"], "content": [
                ["tag": "div", "data": ["content": "example-sentence-a"], "content": [
                    "それは", ["tag": "ruby", "content": ["片", ["tag": "rt", "content": "かた"]]],
                    ["tag": "ruby", "content": ["思", ["tag": "rt", "content": "おも"]]], "いの",
                    ["tag": "span", "data": ["content": "example-keyword"], "content": ["tag": "ruby", "content": ["恋", ["tag": "rt", "content": "こい"]]]], "だった。"
                ]],
                ["tag": "div", "data": ["content": "example-sentence-b"], "content": "It was a one-sided love affair."]
            ]]
        ]]]
    }
    @Test func structuredChildrenStayInlineAndPreserveDictionarySelectors() {
        let html = StructuredGlossary.glossary([Self.content], dictionary: "Fixture")
        #expect(!html.contains("<br>"))
        #expect(html.contains("data-sc-content=\"example-sentence-a\""))
        #expect(html.contains("<ruby class=\"gloss-sc-ruby\">片<rt"))
        #expect(StructuredGlossary.glossary(["one", "two"], dictionary: "Fixture").contains("<li>one</li><li>two</li>"))
        let attributes = StructuredGlossary.render(["tag": "span", "data": ["someKey": "x", "見出": "雨", "bad\"onclick": "x"], "content": "雨"], dictionary: "Fixture")
        #expect(attributes.contains("data-sc-some-key=\"x\""))
        #expect(attributes.contains("data-sc見出=\"雨\""))
        #expect(!attributes.contains("onclick"))
    }
    @Test func repeatedSourcesGroupWithoutChangingMiningIndices() {
        let word = WordResult(expression: "学", reading: "がく", matched: "学", reasons: [], glossaries: [
            Glossary(dictionary: "Names", json: "1", html: "あきら | ゆたか", plain: "names", definitionTags: ["unclass"]),
            Glossary(dictionary: "Other", json: "2", html: "study", plain: "study"),
            Glossary(dictionary: "Names", json: "3", html: "がく", plain: "がく", definitionTags: ["place", "<unsafe>"])
        ], frequencies: [], frequencyValues: [], pitches: [], pitchPositions: [])
        let html = GlossaryDocument.entries(word)
        #expect(html.components(separatedBy: "class=\"dictionary-card\"").count - 1 == 2)
        #expect(html.contains("<summary>Names</summary>"))
        #expect(html.contains("data-glossary-index=\"2\""))
        #expect(html.contains("class=\"glossary-tag\">place</span>"))
        #expect(html.contains("&lt;unsafe&gt;"))
        #expect(html.range(of: "<summary>Names")!.lowerBound < html.range(of: "<summary>Other")!.lowerBound)
    }
    @Test @MainActor func narrowGlossaryRendersRubyTagsExamplesAndPitchInBothThemes() async throws {
        let word = WordResult(expression: "恋", reading: "こい", matched: "恋", reasons: [], glossaries: [Glossary(dictionary: "Fixture", json: "[]", html: StructuredGlossary.glossary([Self.content], dictionary: "Fixture"), plain: "love"), Glossary(dictionary: "Fixture", json: "synonyms", html: StructuredGlossary.glossary(["learning", "scholarship", "study", "erudition", "knowledge", "education"], dictionary: "Fixture"), plain: "study", definitionTags: ["noun"])], frequencies: [], frequencyValues: [], pitches: ["1"], pitchPositions: [1])
        for theme in ["Night", "White"] {
            let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
            let ready = GlossaryReady()
            configuration.userContentController.add(ready, name: "glossaryReady")
            configuration.userContentController.addUserScript(WKUserScript(source: "window.webkit.messageHandlers.glossaryReady.postMessage('ready')", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 650), configuration: configuration)
            web.loadHTMLString(GlossaryDocument.prepare(html: GlossaryDocument.entries(word), css: "", theme: theme), baseURL: nil)
            for _ in 0..<100 {
                if ready.received { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(ready.received)
            if ready.received {
                let result = try await web.evaluateJavaScript("""
                (()=>{const sentence=document.querySelector('[data-sc-content="example-sentence-a"]');return [document.querySelectorAll('br').length,sentence.getBoundingClientRect().height,document.documentElement.scrollWidth<=innerWidth,getComputedStyle(document.querySelector('[data-sc-class="tag"]')).backgroundColor,getComputedStyle(document.querySelector('[data-sc-content="example-sentence"]')).backgroundColor,document.querySelectorAll('.pitch-card svg').length,getComputedStyle(document.querySelector('ruby')).display]})()
                """) as! [Any]
                #expect((result[0] as! Int) == 0)
                #expect((result[1] as! Double) < 110)
                #expect(result[2] as? Bool == true)
                #expect(result[3] as? String != "rgba(0, 0, 0, 0)")
                #expect(result[4] as? String != "rgba(0, 0, 0, 0)")
                #expect((result[5] as! Int) == 1)
                #expect(result[6] as? String == "ruby")
                let layout = try await web.evaluateJavaScript("""
                (()=>{const items=[...document.querySelectorAll('.glossary-list > li')];return [document.querySelectorAll('.dictionary-card').length,items[0].getBoundingClientRect().top===items[1].getBoundingClientRect().top,document.querySelector('.glossary-list').getBoundingClientRect().height<90,document.querySelector('.glossary-tag').textContent]})()
                """) as! [Any]
                #expect(layout[0] as? Int == 1)
                #expect(layout[1] as? Bool == true)
                #expect(layout[2] as? Bool == true)
                #expect(layout[3] as? String == "noun")
            }
            configuration.userContentController.removeScriptMessageHandler(forName: "glossaryReady"); web.stopLoading()
        }
    }
}
@MainActor private final class GlossaryReady: NSObject, WKScriptMessageHandler {
    var received = false
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { received = true }
}
