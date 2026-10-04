import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ReaderWebView: NSViewRepresentable {
    @EnvironmentObject var store: ReaderStore
    let book: Book
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let jsURL = Bundle.readerResources.url(forResource: "reader", withExtension: "js", subdirectory: "Resources")!
        config.userContentController.addUserScript(WKUserScript(source: (try? String(contentsOf: jsURL)) ?? "", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: "reader")
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = context.coordinator; context.coordinator.web = web
        web.setValue(false, forKey: "drawsBackground"); return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        let c = context.coordinator; c.store = store
        guard book.chapters.indices.contains(book.chapter), let root = store.contentRoot else { return }
        let path = root.appendingPathComponent(book.chapters[book.chapter].path)
        let key = "\(book.id):\(book.chapter)"
        if c.chapterKey != key {
            c.chapterKey = key; c.ready = false; c.revision = store.navigationRevision
            do {
                let html = try String(contentsOf: path, encoding: .utf8)
                let document = ReaderHTML.prepare(html)
                let rendered = path.deletingLastPathComponent().appendingPathComponent(".sr-\(book.chapter).html")
                try document.write(to: rendered, atomically: true, encoding: .utf8)
                web.loadFileURL(rendered, allowingReadAccessTo: root)
            } catch { store.error = error.localizedDescription }
            return
        }
        guard c.ready else { return }
        c.configure()
        if c.revision != store.navigationRevision { c.revision = store.navigationRevision; c.restore() }
        let markKey = store.state.passages.filter { $0.bookID == book.id && $0.chapter == book.chapter && $0.kind == "highlight" }.map { $0.id.uuidString + $0.text }.joined()
        if markKey != c.marksKey { c.marksKey = markKey; c.marks() }
    }
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) { nsView.configuration.userContentController.removeScriptMessageHandler(forName: "reader"); nsView.stopLoading() }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var store: ReaderStore
        weak var web: WKWebView?
        var chapterKey = ""; var ready = false; var revision = -1; var preferencesKey = ""; var marksKey = ""
        init(_ store: ReaderStore) { self.store = store }
        func configure() {
            let p = store.preferences
            let value = jsonString(["vertical": p.vertical, "font": p.font, "fontSize": p.fontSize, "lineHeight": p.lineHeight, "background": p.background, "foreground": p.foreground, "showRuby": p.showRuby, "customCSS": p.customCSS, "scanLength": p.scanLength])
            guard value != preferencesKey else { return }; preferencesKey = value
            web?.evaluateJavaScript("window.sr?.configure(\(value));")
            if let book = store.book { web?.evaluateJavaScript("setTimeout(()=>window.sr?.restore(\(book.offset),null),200)") }
        }
        func restore() { web?.evaluateJavaScript("window.sr?.restore(\(store.jumpOffset ?? store.book?.offset ?? 0),\(jsonString(store.jumpFragment as Any? ?? NSNull())));") }
        func marks() { let passages = store.state.passages.filter { $0.bookID == store.book?.id && $0.chapter == store.book?.chapter && $0.kind == "highlight" }.map { ["offset": $0.offset, "text": $0.text] as [String: Any] }; web?.evaluateJavaScript("window.sr?.marks(\(jsonString(passages)))") }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let data = message.body as? [String: Any], let type = data["type"] as? String else { return }
            switch type {
            case "ready": ready = true; preferencesKey = ""; configure(); restore(); marks()
            case "position": store.updatePosition(data["offset"] as? Int ?? 0, count: data["count"] as? Int ?? 0, reading: data["reading"] as? Bool ?? false)
            case "lookup": store.lookup(data["text"] as? String ?? "", sentence: data["sentence"] as? String ?? "", offset: data["offset"] as? Int ?? 0, fromBook: true)
            case "activity": store.activity()
            case "link": if let href = data["href"] as? String, let url = URL(string: href), url.isFileURL, let root = store.contentRoot, url.path.hasPrefix(root.path + "/") { store.navigate(path: String(url.path.dropFirst(root.path.count + 1)) + (url.fragment.map { "#" + $0 } ?? "")) }
            default: break
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { store.error = "Could not display chapter: \(error.localizedDescription)" }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated { decisionHandler(.cancel) } else { decisionHandler(.allow) }
        }
    }
}
struct GlossaryWebView: NSViewRepresentable {
    let html: String
    let css: String
    let engine: DictionaryEngine
    let theme: String
    var onSelection: (String) -> Void = { _ in }
    func makeCoordinator() -> MediaHandler { MediaHandler(engine, onSelection: onSelection) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.userContentController.add(context.coordinator, name: "glossarySelection"); config.userContentController.addUserScript(WKUserScript(source: "document.addEventListener('mouseup',()=>window.webkit.messageHandlers.glossarySelection.postMessage(window.getSelection().toString()))", injectionTime: .atDocumentEnd, forMainFrameOnly: true)); config.setURLSchemeHandler(context.coordinator, forURLScheme: "dictmedia")
        let web = WKWebView(frame: .zero, configuration: config); web.setValue(false, forKey: "drawsBackground"); return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        let key = html + css + theme; guard context.coordinator.lastHTML != key else { return }; context.coordinator.lastHTML = key
        context.coordinator.onSelection = onSelection
        web.loadHTMLString(GlossaryDocument.prepare(html: html, css: css, theme: theme), baseURL: nil)
    }
    static func dismantleNSView(_ web: WKWebView, coordinator: MediaHandler) { web.configuration.userContentController.removeScriptMessageHandler(forName: "glossarySelection"); web.stopLoading() }
}
final class MediaHandler: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
    let engine: DictionaryEngine
    var lastHTML = ""
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    var onSelection: (String) -> Void
    init(_ engine: DictionaryEngine, onSelection: @escaping (String) -> Void) { self.engine = engine; self.onSelection = onSelection }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { if let text = message.body as? String { onSelection(text) } }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url, let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, let dictionary = query.first(where: { $0.name == "dictionary" })?.value, let path = query.first(where: { $0.name == "path" })?.value else { urlSchemeTask.didFailWithError(URLError(.badURL)); return }
        tasks[key] = Task { @MainActor in
            let data = await engine.media(dictionary: dictionary, path: path)
            guard !Task.isCancelled else { return }
            if data.isEmpty { urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)) }
            else { let type = UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension)?.preferredMIMEType ?? "application/octet-stream"; urlSchemeTask.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil)); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish() }
            tasks.removeValue(forKey: key)
        }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) { tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel() }
}
