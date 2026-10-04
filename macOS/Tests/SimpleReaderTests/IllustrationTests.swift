import Testing
import AppKit
import WebKit
@testable import SimpleReader

@MainActor
struct IllustrationTests {
    @Test func imageOnlyXHTMLRendersInBothWritingModes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleReaderIllustration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let picture = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"400\" height=\"600\"><rect width=\"400\" height=\"600\" fill=\"red\"/></svg>"
        try picture.write(to: root.appendingPathComponent("picture.svg"), atomically: true, encoding: .utf8)
        let document = ReaderHTML.prepare("""
        <html><head><script src="kobo.js"/><style>body{width:1443px;height:2048px}.main{width:100%;height:100%}</style></head>
        <body><div class="main"><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100%" height="100%" viewBox="0 0 400 600"><image width="400" height="600" xlink:href="picture.svg"/></svg></div></body></html>
        """)
        let page = root.appendingPathComponent("page.html")
        try document.write(to: page, atomically: true, encoding: .utf8)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let handler = IllustrationMessageHandler()
        config.userContentController.add(handler, name: "reader")
        let script = try String(contentsOf: Bundle.module.url(forResource: "reader", withExtension: "js", subdirectory: "Resources")!)
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 650), configuration: config)
        defer { config.userContentController.removeScriptMessageHandler(forName: "reader"); web.stopLoading() }
        web.loadFileURL(page, allowingReadAccessTo: root)
        for _ in 0..<100 {
            if handler.ready { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(handler.ready)
        guard handler.ready else { return }
        for vertical in [true, false] {
            _ = try await web.evaluateJavaScript("window.sr.configure({vertical:\(vertical),font:'serif',fontSize:22,lineHeight:1.8,background:'#fff',foreground:'#000',showRuby:true,customCSS:''});window.sr.restore(0,null)")
            try await Task.sleep(for: .milliseconds(400))
            let values = try await web.evaluateJavaScript("""
            (()=>{const s=document.querySelector('svg'),r=s.getBoundingClientRect();return [document.body.classList.contains('sr-illustration'),getComputedStyle(document.body).writingMode,r.width,r.height,r.left,r.top,document.querySelector('image').href.baseVal]})()
            """) as! [Any]
            #expect(values[0] as? Bool == true)
            #expect(values[1] as? String == "horizontal-tb")
            #expect((values[2] as! Double) > 300 && (values[2] as! Double) <= 800)
            #expect((values[3] as! Double) > 300 && (values[3] as! Double) <= 650)
            #expect((values[4] as! Double) >= 0 && (values[5] as! Double) >= 0)
            #expect(values[6] as? String == "picture.svg")
            let imageLoaded = try await web.callAsyncJavaScript("""
            return await new Promise(resolve=>{const i=new Image();i.onload=()=>resolve(i.naturalWidth>0);i.onerror=()=>resolve(false);i.src=document.querySelector('image').href.baseVal;});
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool
            #expect(imageLoaded == true)
        }
    }
}
@MainActor private final class IllustrationMessageHandler: NSObject, WKScriptMessageHandler {
    var ready = false
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.body as? [String: Any])?["type"] as? String == "ready" { ready = true }
    }
}
