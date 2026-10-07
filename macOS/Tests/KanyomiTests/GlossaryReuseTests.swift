import Testing
import WebKit
@testable import Kanyomi

@MainActor struct GlossaryReuseTests {
    @Test func newEntriesReuseDocumentAndKeepLatestPendingResult() async throws {
        let handler = MediaHandler(DictionaryEngine(), onSelection: { _ in })
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(handler, forURLScheme: "dictmedia")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 600), configuration: configuration)
        web.navigationDelegate = handler
        defer { web.stopLoading() }
        handler.pendingBody = "<p>latest pending</p>"
        web.loadHTMLString(GlossaryDocument.prepare(html: "<p>initial</p>", css: "", theme: "Night"), baseURL: nil)
        for _ in 0..<100 { if handler.documentReady { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(handler.documentReady); guard handler.documentReady else { return }
        #expect(try await web.evaluateJavaScript("document.body.textContent") as? String == "latest pending")
        _ = try await web.evaluateJavaScript("window.documentMarker='same document'")
        handler.pendingBody = "<p data-word='次'>次の意味</p>"
        let start = Date(); handler.updateBody(web)
        let result = try await web.evaluateJavaScript("[window.documentMarker,document.body.textContent,getComputedStyle(document.documentElement).getPropertyValue('--canvas')]") as! [String]
        print("Reused glossary update: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        #expect(result[0] == "same document")
        #expect(result[1] == "次の意味")
        #expect(result[2].contains("#252525"))
    }
}
