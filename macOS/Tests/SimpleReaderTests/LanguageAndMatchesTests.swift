import Testing
import WebKit
@testable import SimpleReader

struct LanguageAndMatchesTests {
    @Test func simplifiedChineseAndEnglishFallback() {
        #expect(AppLanguage.text("Library", language: "zh-Hans") == "书库")
        #expect(AppLanguage.text("Use for mining", language: "zh_Hans_CN") == "用于制卡")
        #expect(AppLanguage.text("Library", language: "en") == "Library")
        #expect(AppLanguage.text("Library", language: "zh_Hant_TW") == "Library")
        #expect(AppLanguage.text("Imported dictionary title", language: "zh-Hans") == "Imported dictionary title")
        #expect(AppLanguage.locale("system", preferred: ["zh-Hans-CN"]).identifier.hasPrefix("zh"))
        #expect(AppLanguage.locale("en", preferred: ["zh-Hans"]).identifier == "en")
    }

    @Test @MainActor func eightMatchesScrollVerticallyAndMiningSelectionKeepsPosition() async throws {
        let words = (0..<8).map { index in
            WordResult(expression: "が", reading: "が", matched: "が", reasons: [], glossaries: [Glossary(dictionary: "Fixture \(index)", json: "[]", html: "<p>\(String(repeating: "释义与例句。", count: 120))</p>", plain: "Definition \(index)")], frequencies: [], frequencyValues: [], pitches: [], pitchPositions: [])
        }
        let handler = MediaHandler(DictionaryEngine(), onSelection: { _ in })
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.userContentController.add(handler, name: "glossaryMatch")
        config.userContentController.add(handler, name: "glossarySelection")
        for script in [GlossaryWebView.matchScript, GlossaryWebView.selectionScript] {
            config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        var selected: Int?; var selection = ""
        handler.onMatch = { selected = $0 }; handler.onSelection = { selection = $0 }
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 500), configuration: config)
        web.navigationDelegate = handler
        defer { config.userContentController.removeScriptMessageHandler(forName: "glossaryMatch"); config.userContentController.removeScriptMessageHandler(forName: "glossarySelection"); web.stopLoading() }
        handler.pendingBody = GlossaryDocument.matches(words)
        web.loadHTMLString(GlossaryDocument.prepare(html: handler.pendingBody, css: "", theme: "Night"), baseURL: nil)
        for _ in 0..<100 { if handler.documentReady { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(handler.documentReady); guard handler.documentReady else { return }
        let dimensions = try await web.evaluateJavaScript("[document.querySelectorAll('.match-card').length,document.querySelectorAll('.dictionary-card').length,document.documentElement.scrollWidth<=innerWidth,document.documentElement.scrollHeight>innerHeight]") as! [Any]
        #expect(dimensions[0] as? Int == 8); #expect(dimensions[1] as? Int == 8)
        #expect(dimensions[2] as? Bool == true); #expect(dimensions[3] as? Bool == true)
        _ = try await web.evaluateJavaScript("document.querySelector('[data-match=\"7\"]').scrollIntoView();document.querySelector('details').open=false;window.documentMarker='retained'")
        let before = try await web.evaluateJavaScript("scrollY") as! Double
        #expect(before > 0)
        handler.selectedMatch = 7; handler.updateSelection(web)
        let after = try await web.evaluateJavaScript("[scrollY,document.querySelector('[data-select-match=\"7\"]').getAttribute('aria-pressed'),document.querySelector('[data-select-match=\"0\"]').getAttribute('aria-pressed'),document.querySelector('details').open,window.documentMarker]") as! [Any]
        #expect(after[0] as? Double == before); #expect(after[1] as? String == "true")
        #expect(after[2] as? String == "false"); #expect(after[3] as? Bool == false)
        #expect(after[4] as? String == "retained")
        _ = try await web.evaluateJavaScript("document.querySelector('[data-select-match=\"6\"]').click()")
        for _ in 0..<20 { if selected == 6 { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(selected == 6)
        _ = try await web.evaluateJavaScript("const range=document.createRange();range.selectNodeContents(document.querySelector('[data-match=\"5\"] p'));getSelection().removeAllRanges();getSelection().addRange(range);document.dispatchEvent(new MouseEvent('mouseup'))")
        for _ in 0..<20 { if !selection.isEmpty { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(selected == 5); #expect(selection.contains("释义与例句"))
    }
}
