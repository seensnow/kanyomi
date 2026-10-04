import Foundation
import ZIPFoundation

struct TtuSection: Codable {
    var reference: String
    var charactersWeight: Int
    var label: String?
    var startCharacter: Int?
    var characters: Int?
    var parentChapter: String?
}
struct TtuStaticData: Codable {
    var title: String
    var styleSheet: String
    var elementHtml: String
    var sections: [TtuSection]
}
struct TtuProgress: Codable {
    var dataId: Int = 0
    var exploredCharCount: Int
    var progress: Double
    var lastBookmarkModified: Date
}
struct TtuStatistic: Codable {
    var title: String
    var dateKey: String
    var charactersRead: Int
    var readingTime: Double
    var minReadingSpeed: Int = 0
    var altMinReadingSpeed: Int = 0
    var lastReadingSpeed: Int = 0
    var maxReadingSpeed: Int = 0
    var lastStatisticModified: Int
}
struct TtuAudioProgress: Codable { var title: String; var playbackPosition: Double; var lastAudioBookModified: Int }
struct TtuArchive {
    static func export(_ book: Book, root: URL, to output: URL) throws {
        let content = root.appendingPathComponent("Books/\(book.id)/Content").resolvingSymlinksInPath()
        let archive = try Archive(url: output, accessMode: .create)
        func add(_ path: String, data: Data) throws { try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in data.subdata(in: Int(position)..<min(data.count, Int(position) + size)) } }
        var parts: [String] = []; var sections: [TtuSection] = []
        for (i, ch) in book.chapters.enumerated() {
            let file = content.appendingPathComponent(ch.path)
            let html = try String(contentsOf: file, encoding: .utf8)
            let regex = try NSRegularExpression(pattern: "(?is)<body\\b[^>]*>(.*?)</body>")
            let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html))
            var body = match.flatMap { Range($0.range(at: 1), in: html).map { String(html[$0]) } } ?? html
            let imageRegex = try NSRegularExpression(pattern: "(?i)(?:src|href)=([\"'])([^\"']+)\\1")
            for m in imageRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)).reversed() {
                guard let r = Range(m.range(at: 2), in: body) else { continue }; let src = String(body[r])
                guard let url = try? EPUBImporter.resolve(src, base: file.deletingLastPathComponent(), root: content), ["png", "jpg", "jpeg", "gif", "svg", "webp"].contains(url.pathExtension.lowercased()), let data = try? Data(contentsOf: url) else { continue }
                let relative = String(url.path.dropFirst(content.path.count + 1))
                let mime = url.pathExtension.lowercased() == "svg" ? "image/svg+xml" : url.pathExtension.lowercased() == "jpg" ? "image/jpeg" : "image/\(url.pathExtension)"
                body.replaceSubrange(r, with: "data:\(mime);ttu:\(relative);base64,\(data.base64EncodedString())")
            }
            parts.append("<div id=\"ttu-sr\(i)\"><div class=\"ttu-book-html-wrapper\"><div class=\"ttu-book-body-wrapper\">\(body)</div></div></div>")
            sections.append(TtuSection(reference: "ttu-sr\(i)", charactersWeight: max(1, ch.count), label: ch.title, startCharacter: ch.start, characters: ch.count))
        }
        var css = ""
        let files = FileManager.default.enumerator(at: content, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = files?.nextObject() as? URL {
            let relative = String(file.resolvingSymlinksInPath().path.dropFirst(content.path.count + 1))
            if file.pathExtension == "css" { css += (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
            if ["png", "jpg", "jpeg", "gif", "svg", "webp"].contains(file.pathExtension.lowercased()) { try add("blobs/\(relative)", data: Data(contentsOf: file)) }
        }
        let data = TtuStaticData(title: book.title, styleSheet: css, elementHtml: parts.joined(), sections: sections)
        try add("staticdata.json", data: JSONEncoder().encode(data))
        if let cover = book.cover { let file = content.appendingPathComponent(cover); try add("cover.\(file.pathExtension)", data: Data(contentsOf: file)) }
    }
    static func importBook(_ zip: URL, root: URL) throws -> Book {
        let staging = root.appendingPathComponent("Staging/\(UUID())"); defer { try? FileManager.default.removeItem(at: staging) }
        try EPUBImporter.extract(zip, to: staging)
        let data = try JSONDecoder().decode(TtuStaticData.self, from: Data(contentsOf: staging.appendingPathComponent("staticdata.json")))
        let package = staging.appendingPathComponent("Converted"); try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let epub = package.appendingPathComponent("converted.epub"); let archive = try Archive(url: epub, accessMode: .create)
        func add(_ name: String, _ s: String, compress: Bool = true) throws { let data = Data(s.utf8); try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: compress ? .deflate : .none) { position, size in data.subdata(in: Int(position)..<min(data.count, Int(position) + size)) } }
        try add("mimetype", "application/epub+zip", compress: false)
        try add("META-INF/container.xml", "<?xml version=\"1.0\"?><container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\" version=\"1.0\"><rootfiles><rootfile full-path=\"book.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>")
        try add("style.css", data.styleSheet)
        var body = data.elementHtml
        body = body.replacingOccurrences(of: "data:image/[^;\"']+;ttu:([^;\"']+);base64,[^\"']*", with: "$1", options: .regularExpression).replacingOccurrences(of: "ttu:([^\"']+)", with: "$1", options: .regularExpression)
        try add("chapter.xhtml", "<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>\(escapeHTML(data.title))</title><link rel=\"stylesheet\" href=\"style.css\"/></head><body>\(body)</body></html>")
        let nav = data.sections.filter { $0.label != nil }.map { "<li><a href=\"chapter.xhtml#\(escapeHTML($0.reference))\">\(escapeHTML($0.label!))</a></li>" }.joined()
        try add("nav.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><head><title>Contents</title></head><body><nav epub:type=\"toc\"><ol>\(nav)</ol></nav></body></html>")
        let blobs = staging.appendingPathComponent("blobs").resolvingSymlinksInPath()
        var manifest = ""
        if let files = FileManager.default.enumerator(at: blobs, includingPropertiesForKeys: [.isRegularFileKey]) {
            var i = 0
            for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let path = String(file.resolvingSymlinksInPath().path.dropFirst(blobs.path.count + 1)); _ = try EPUBImporter.safeURL(path, under: package)
                try archive.addEntry(with: path, fileURL: file, compressionMethod: .deflate)
                let mime = file.pathExtension == "svg" ? "image/svg+xml" : file.pathExtension == "jpg" ? "image/jpeg" : "image/\(file.pathExtension)"
                manifest += "<item id=\"img\(i)\" href=\"\(escapeHTML(path))\" media-type=\"\(mime)\"/>"; i += 1
            }
        }
        if let cover = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent.hasPrefix("cover.") }) {
            try archive.addEntry(with: cover.lastPathComponent, fileURL: cover, compressionMethod: .deflate)
            manifest += "<item id=\"cover\" properties=\"cover-image\" href=\"\(cover.lastPathComponent)\" media-type=\"image/\(cover.pathExtension == "jpg" ? "jpeg" : cover.pathExtension)\"/>"
        }
        try add("book.opf", "<?xml version=\"1.0\"?><package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"id\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(escapeHTML(data.title))</dc:title><dc:language>ja</dc:language><dc:identifier id=\"id\">\(UUID())</dc:identifier></metadata><manifest><item id=\"ch\" href=\"chapter.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"nav\" properties=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>\(manifest)</manifest><spine><itemref idref=\"ch\"/></spine></package>")
        return try EPUBImporter.load(epub, root: root)
    }
    static func sanitizeTitle(_ title: String) -> String {
        var result = title
        if result.hasSuffix(" ") { result = String(result.dropLast()) + "~ttu-spc~" }
        if result.hasSuffix(".") { result = String(result.dropLast()) + "~ttu-dend~" }
        result = result.replacingOccurrences(of: "*", with: "~ttu-star~")
        return result.unicodeScalars.map { "/?<>\\:*|%\"".unicodeScalars.contains($0) ? String(format: "%%%02X", $0.value) : String($0) }.joined()
    }
}
