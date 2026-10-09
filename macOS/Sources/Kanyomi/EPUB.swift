import Foundation
import ZIPFoundation

final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var value = ""
    init(_ name: String, _ attributes: [String: String] = [:]) { self.name = name.split(separator: ":").last.map(String.init) ?? name; self.attributes = attributes }
    func all(_ name: String) -> [XMLNode] { (self.name == name ? [self] : []) + children.flatMap { $0.all(name) } }
    var text: String { value }
}
final class XMLTree: NSObject, XMLParserDelegate {
    private var stack: [XMLNode] = []
    private var root: XMLNode?
    static func parse(_ data: Data) throws -> XMLNode {
        let tree = XMLTree(); let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = tree
        guard parser.parse(), let root = tree.root else { throw ReaderError.message("Invalid EPUB XML: \(parser.parserError?.localizedDescription ?? "empty document")") }; return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let node = XMLNode(elementName, attributeDict)
        stack.last?.children.append(node)
        if root == nil { root = node }; stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { for node in stack { node.value += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if !stack.isEmpty { stack.removeLast() } }
}
struct EPUBImporter {
    static func safeURL(_ path: String, under root: URL) throws -> URL {
        let clean = path.removingPercentEncoding ?? path
        guard !clean.hasPrefix("/"), !clean.contains("\\"), !clean.contains("\0") else { throw ReaderError.message("Unsafe archive path") }
        let normalizedRoot = root.standardizedFileURL
        let url = normalizedRoot.appendingPathComponent(clean).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ReaderError.message("Archive path escapes its folder") }; return url
    }
    static func extract(_ url: URL, to destination: URL) throws {
        let archive = try Archive(url: url, accessMode: .read)
        var size: UInt64 = 0
        for entry in archive {
            size += entry.uncompressedSize
            guard size < 2_000_000_000, entry.type != .symlink else { throw ReaderError.message("Archive is too large or contains symbolic links") }
            _ = try safeURL(entry.path, under: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in archive { _ = try archive.extract(entry, to: safeURL(entry.path, under: destination)) }
    }
    static func load(_ url: URL, root: URL) throws -> Book {
        let id = UUID(); let directory = root.standardizedFileURL.appendingPathComponent("Books/\(id)")
        let content = directory.appendingPathComponent("Content")
        do {
            try extract(url, to: content)
            let container = try XMLTree.parse(Data(contentsOf: content.appendingPathComponent("META-INF/container.xml")))
            guard let opfPath = container.all("rootfile").first?.attributes["full-path"] else { throw ReaderError.message("EPUB has no package document") }
            let opfURL = try safeURL(opfPath, under: content)
            let opf = try XMLTree.parse(Data(contentsOf: opfURL)); let base = opfURL.deletingLastPathComponent()
            var manifest: [String: XMLNode] = [:]
            for node in opf.all("item") { if let id = node.attributes["id"] { manifest[id] = node } }
            var paths: [String] = []
            for spine in opf.all("itemref") {
                guard spine.attributes["linear"] != "no", let ref = spine.attributes["idref"], let item = manifest[ref], let href = item.attributes["href"] else { continue }
                let file = try resolve(href, base: base, root: content)
                paths.append(String(file.path.dropFirst(content.standardizedFileURL.path.count + 1)))
            }
            guard !paths.isEmpty else { throw ReaderError.message("EPUB has no readable chapters (DRM-protected books aren't supported)") }
            var toc: [NavigationItem] = []
            if let nav = manifest.values.first(where: { ($0.attributes["properties"] ?? "").split(separator: " ").contains("nav") }), let href = nav.attributes["href"] {
                let navURL = try resolve(href, base: base, root: content)
                if let tree = try? XMLTree.parse(Data(contentsOf: navURL)), let node = tree.all("nav").first(where: { ($0.attributes["epub:type"] ?? "").contains("toc") }) ?? tree.all("nav").first {
                    func walk(_ n: XMLNode, depth: Int) {
                        if n.name == "a", let href = n.attributes["href"], let path = try? relative(href, base: navURL.deletingLastPathComponent(), root: content) { toc.append(NavigationItem(title: n.text.trimmingCharacters(in: .whitespacesAndNewlines), path: path, depth: max(0, depth - 1))) }
                        for c in n.children { walk(c, depth: depth + (n.name == "ol" ? 1 : 0)) }
                    }; walk(node, depth: 0)
                }
            }
            if toc.isEmpty, let ncx = manifest.values.first(where: { $0.attributes["media-type"] == "application/x-dtbncx+xml" }), let href = ncx.attributes["href"] {
                let ncxURL = try resolve(href, base: base, root: content)
                if let tree = try? XMLTree.parse(Data(contentsOf: ncxURL)) {
                    func walk(_ n: XMLNode, depth: Int) {
                        if n.name == "navPoint", let label = n.children.first(where: { $0.name == "navLabel" })?.text, let src = n.children.first(where: { $0.name == "content" })?.attributes["src"], let path = try? relative(src, base: ncxURL.deletingLastPathComponent(), root: content) { toc.append(NavigationItem(title: label, path: path, depth: depth)) }
                        for c in n.children { walk(c, depth: depth + (n.name == "navPoint" ? 1 : 0)) }
                    }; walk(tree, depth: 0)
                }
            }
            var start = 0
            let chapters = try paths.enumerated().map { index, path -> Chapter in
                let html = try String(contentsOf: safeURL(path, under: content), encoding: .utf8)
                let text = visibleText(html)
                let title = toc.first(where: { $0.path.components(separatedBy: "#")[0] == path })?.title ?? "Chapter \(index + 1)"
                let chapter = Chapter(title: title, path: path, text: text, start: start); start += chapter.count; return chapter
            }
            let coverID = opf.all("meta").first(where: { $0.attributes["name"] == "cover" })?.attributes["content"]
            let coverItem = manifest.values.first(where: { ($0.attributes["properties"] ?? "").contains("cover-image") }) ?? coverID.flatMap { manifest[$0] }
            let cover = try coverItem?.attributes["href"].map { try relative($0, base: base, root: content) }
            try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent("Original.epub"))
            return Book(id: id, title: opf.all("title").first?.text ?? url.deletingPathExtension().lastPathComponent, author: opf.all("creator").first?.text ?? "Unknown author", cover: cover, chapters: chapters, contents: toc)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    static func resolve(_ href: String, base: URL, root: URL) throws -> URL {
        let path = href.components(separatedBy: "#")[0]
        guard !path.contains("://"), !path.hasPrefix("/") else { throw ReaderError.message("Invalid EPUB resource URL") }
        let url = base.appendingPathComponent(path.removingPercentEncoding ?? path).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw ReaderError.message("EPUB resource escapes book folder") }; return url
    }
    static func relative(_ href: String, base: URL, root: URL) throws -> String {
        let url = try resolve(href, base: base, root: root)
        let fragment = href.components(separatedBy: "#").dropFirst().joined(separator: "#")
        return String(url.path.dropFirst(root.standardizedFileURL.path.count + 1)) + (fragment.isEmpty ? "" : "#" + fragment)
    }
    static func visibleText(_ html: String) -> String {
        // Match the reader's text walker: ruby readings, script/style and indentation aren't counted.
        var s = html
        for tag in ["head", "script", "style", "rt", "rp"] { s = s.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>", with: "", options: .regularExpression) }
        s = s.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
        let regex = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        for m in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let range = Range(m.range, in: s), let valueRange = Range(m.range(at: 1), in: s) else { continue }
            let token = String(s[valueRange]); let value = token.hasPrefix("x") ? UInt32(token.dropFirst(), radix: 16) : UInt32(token)
            if let value, let scalar = UnicodeScalar(value) { s.replaceSubrange(range, with: String(scalar)) }
        }
        return s.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
    }
}

struct ReaderHTML {
    static func prepare(_ html: String) -> String {
        // XHTML permits self-closing scripts. In text/html WebKit treats them as an
        // open script and consumes the rest of the chapter, including illustrations.
        let withoutEmptyScripts = html.replacingOccurrences(of: "(?is)<script\\b[^>]*?/\\s*>", with: "", options: .regularExpression)
        let cleaned = withoutEmptyScripts.replacingOccurrences(of: "(?is)<script\\b[^>]*>.*?</script>", with: "", options: .regularExpression).replacingOccurrences(of: "(?is)<meta\\b[^>]*http-equiv[^>]*>", with: "", options: .regularExpression)
        let policy = "<meta charset=\"UTF-8\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src file: data:; style-src file: 'unsafe-inline'; font-src file: data:; script-src 'none'; connect-src 'none'; media-src file:; frame-src 'none';\">"
        if cleaned.range(of: "(?i)<head[^>]*>", options: .regularExpression) != nil { return cleaned.replacingOccurrences(of: "(?i)<head[^>]*>", with: "$0\(policy)", options: .regularExpression) }
        return "<html><head>\(policy)</head><body>\(cleaned)</body></html>"
    }
}
