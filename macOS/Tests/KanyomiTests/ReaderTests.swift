import Testing
import Foundation
import ZIPFoundation
@testable import Kanyomi

@Suite(.serialized)
final class ReaderTests {
    var root: URL!
    init() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("KanyomiTests-\(UUID())"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    func sample(_ name: String, ext: String) -> URL { Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")! }
    @Test func testEPUB3RubyNavigationAndAssets() throws {
        let b = try EPUBImporter.load(sample("Sample", ext: "epub"), root: root)
        XCTAssertEqual(b.title, "雨の日の喫茶店"); XCTAssertEqual(b.author, "SimpleReader sample")
        XCTAssertEqual(b.chapters.count, 2); XCTAssertEqual(b.contents.count, 2); XCTAssertTrue(b.contents[1].path.hasSuffix("#evening"))
        XCTAssertTrue(b.chapters[0].text.contains("喫茶店で過ごす午後。")); XCTAssertFalse(b.chapters[0].text.contains("きっさてん"))
        XCTAssertEqual(b.chapters[1].start, b.chapters[0].count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Books/\(b.id)/Content/\(b.cover!)").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Books/\(b.id)/Original.epub").path))
    }
    @Test func testEPUB2NCXAndRelativePaths() throws {
        let url = root.appendingPathComponent("epub2.epub"); let a = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ text: String) throws { let d = Data(text.utf8); try a.addEntry(with: path, type: .file, uncompressedSize: Int64(d.count)) { pos, size in d.subdata(in: Int(pos)..<min(d.count, Int(pos) + size)) } }
        try add("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>")
        try add("OPS/book.opf", "<package><metadata><title>Legacy book</title></metadata><manifest><item id=\"a\" href=\"text/a%20b.xhtml\"/><item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/></manifest><spine><itemref idref=\"a\"/></spine></package>")
        try add("OPS/text/a b.xhtml", "<html><body><p>日本語</p></body></html>")
        try add("OPS/toc.ncx", "<ncx><navMap><navPoint><navLabel><text>Chapter A</text></navLabel><content src=\"text/a%20b.xhtml#one\"/><navPoint><navLabel><text>Child</text></navLabel><content src=\"text/a%20b.xhtml#two\"/></navPoint></navPoint></navMap></ncx>")
        let b = try EPUBImporter.load(url, root: root)
        XCTAssertEqual(b.contents.count, 2); XCTAssertEqual(b.contents[1].depth, 1); XCTAssertEqual(b.chapters[0].title, "Chapter A")
    }
    @Test func testArchiveTraversalAndSymlinkProtection() throws {
        XCTAssertThrowsError(try EPUBImporter.safeURL("../../escape.txt", under: root))
        XCTAssertThrowsError(try EPUBImporter.safeURL("/tmp/escape", under: root))
        XCTAssertThrowsError(try EPUBImporter.safeURL("%2E%2E/%2E%2E/escape", under: root))
        let zip = root.appendingPathComponent("bad.zip"); let a = try Archive(url: zip, accessMode: .create)
        let data = Data("bad".utf8); try a.addEntry(with: "../escape", type: .file, uncompressedSize: Int64(3)) { _, _ in data }
        XCTAssertThrowsError(try EPUBImporter.extract(zip, to: root.appendingPathComponent("extract")))
    }
    @Test func testPrivateTmpAliasImport() throws {
        let alias = URL(fileURLWithPath: "/private/tmp/KanyomiAlias-\(UUID())")
        defer { try? FileManager.default.removeItem(at: alias) }
        let book = try EPUBImporter.load(sample("Sample", ext: "epub"), root: alias)
        XCTAssertEqual(book.chapters.count, 2)
    }
    @Test func testReaderEncodingAndContentIsolation() {
        let html = ReaderHTML.prepare("<html><head><title>日本語</title></head><body><p>読む</p><script>fetch('https://example.com')</script></body></html>")
        XCTAssertTrue(html.contains("<head><meta charset=\"UTF-8\">"))
        XCTAssertTrue(html.contains("script-src 'none'")); XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("<p>読む</p>"))
    }
    @Test func testSelfClosingXHTMLScriptsPreserveIllustrations() {
        let html = ReaderHTML.prepare("""
        <html><head><script xmlns="http://www.w3.org/1999/xhtml" src="../../js/kobo.js"/></head>
        <body><div><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100%" height="100%" viewBox="0 0 1443 2048"><image width="1443" height="2048" xlink:href="../image/picture.jpg"/></svg></div><script>bad()</script><p>読む</p></body></html>
        """)
        XCTAssertFalse(html.contains("<script"))
        XCTAssertTrue(html.contains("xlink:href=\"../image/picture.jpg\""))
        XCTAssertTrue(html.contains("<p>読む</p>"))
    }
    @Test func testTextCountAndEntities() {
        let text = EPUBImporter.visibleText("<html><head><title>Hidden</title></head><body><ruby>食<rt>た</rt></ruby>べる&nbsp; &amp; &#x96E8; &#38632;<script>bad()</script></body></html>")
        XCTAssertEqual(text, "食べる&雨雨")
    }
    @Test func testTtuBookdataRoundTrip() throws {
        let b = try EPUBImporter.load(sample("Sample", ext: "epub"), root: root)
        let zip = root.appendingPathComponent("bookdata.zip"); try TtuArchive.export(b, root: root, to: zip)
        let archive = try Archive(url: zip, accessMode: .read); XCTAssertNotNil(archive["staticdata.json"]); XCTAssertNotNil(archive["blobs/OEBPS/cover.svg"])
        let restored = try TtuArchive.importBook(zip, root: root)
        XCTAssertEqual(restored.title, b.title); XCTAssertEqual(restored.totalCharacters, b.totalCharacters)
        XCTAssertEqual(restored.contents.count, 2); XCTAssertNotNil(restored.cover)
        XCTAssertEqual(TtuArchive.sanitizeTitle("test* ."), "test~ttu-star~ ~ttu-dend~")
    }
    @Test func testDictionaryImportLookupDeinflectionMetadataAndMedia() async throws {
        let engine = DictionaryEngine(); let d = try await engine.importZip(sample("SampleDictionary", ext: "zip"), root: root)
        XCTAssertEqual(d.terms, 8); XCTAssertEqual(d.frequencies, 2); XCTAssertEqual(d.pitches, 1); XCTAssertEqual(d.kanji, 1)
        await engine.rebuild([d], root: root)
        let conjugated = await engine.search("食べました", scanLength: 24)
        XCTAssertEqual(conjugated.first?.expression, "食べる"); XCTAssertEqual(conjugated.first?.reading, "たべる")
        XCTAssertFalse(conjugated.first?.reasons.isEmpty ?? true); XCTAssertEqual(conjugated.first?.frequencyValues, [75])
        let reading = await engine.search("読んでいた", scanLength: 24); XCTAssertEqual(reading.first?.expression, "読む")
        let rain = await engine.search("雨", scanLength: 24); XCTAssertEqual(rain.first?.pitchPositions, [1])
        let cafe = await engine.search("喫茶店", scanLength: 24); XCTAssertTrue(cafe.first?.html.contains("dictmedia:") ?? false)
        let image = await engine.media(dictionary: d.title, path: "cup.svg"); XCTAssertFalse(image.isEmpty)
        let kanji = await engine.kanji("雨"); XCTAssertTrue(kanji.contains("rain"))
        var disabled = d; disabled.enabled = false; await engine.rebuild([disabled], root: root)
        let empty = await engine.search("食べる", scanLength: 24); XCTAssertTrue(empty.isEmpty)
    }
    func word() -> WordResult { WordResult(expression: "食べる", reading: "たべる", matched: "食べました", reasons: [], glossaries: [Glossary(dictionary: "Test", json: "[]", html: "<div>to eat</div>", plain: "to eat")], frequencies: ["Test: 75"], frequencyValues: [75], pitches: ["1"], pitchPositions: [1]) }
    @Test func testAllCardMarkersAndCloze() throws {
        let markers = CardTemplate.supported.map { "{\($0)}" }.joined(separator: "|")
        let value = try CardTemplate.render(markers, result: word(), sentence: "パンを食べました。", selection: "食べました", title: "Book <one>", dictionaries: [])
        XCTAssertFalse(value.contains("{expression}")); XCTAssertTrue(value.contains("Book &lt;one&gt;")); XCTAssertTrue(value.contains("<svg"))
        XCTAssertEqual(try CardTemplate.render("{cloze-prefix}|{cloze-body}|{cloze-suffix}", result: word(), sentence: "パンを食べました。", selection: "", title: "", dictionaries: []), "パンを|食べました|。")
        XCTAssertThrowsError(try CardTemplate.render("{unknown-marker}", result: word(), sentence: "", selection: "", title: "", dictionaries: []))
        XCTAssertEqual(CardTemplate.morae("きょう"), ["きょ", "う"])
        XCTAssertEqual(CardTemplate.furigana(expression: "取り戻す", reading: "とりもどす"), "取[と]り戻[もど]す")
    }
    @Test func testStructuredGlossaryEscapesTextAndScripts() {
        XCTAssertEqual(StructuredGlossary.render("<script>alert(1)</script>", dictionary: "Test"), "&lt;script&gt;alert(1)&lt;/script&gt;")
        let html = StructuredGlossary.render(["tag": "script", "content": "bad()"], dictionary: "Test"); XCTAssertFalse(html.contains("<script"))
    }
    @Test func testSubtitleParsingMatchingAndUTF16Offsets() {
        let srt = "1\r\n00:00:01,500 --> 00:00:03,000\r\n雨が降っていた。\r\n\r\n2\r\n00:00:04,000 --> 00:00:06,000\r\nパンを食べました。"
        let cues = Audiobook.parseSRT(srt); XCTAssertEqual(cues.count, 2); XCTAssertEqual(cues[0].start, 1.5)
        let chapters = [Chapter(title: "One", path: "one", text: "😀雨が降っていた。私はパンを食べました。")]
        let matched = Audiobook.match(cues, chapters: chapters); XCTAssertEqual(matched[0].offset, 2); XCTAssertEqual(matched[1].chapter, 0); XCTAssertEqual(matched[1].offset, 12)
    }
    @Test @MainActor func testPersistencePositionVocabularyAndStats() throws {
        let store = ReaderStore(root: root, startTimer: false)
        let b = try EPUBImporter.load(sample("Sample", ext: "epub"), root: root); store.state.books = [b]; store.openBook(b.id)
        store.updatePosition(40, count: b.chapters[0].count, reading: true); store.addBookmark(); store.record(seconds: 20, lookups: 2)
        store.state.words.append(MinedWord(expression: "雨", reading: "あめ", sentence: "雨が降っていた。", definition: "rain", book: b.title)); store.save()
        let restored = ReaderStore(root: root, startTimer: false)
        XCTAssertEqual(restored.state.books.first?.offset, 40); XCTAssertEqual(restored.state.passages.count, 1); XCTAssertEqual(restored.state.words.count, 1)
        XCTAssertEqual(restored.state.days.first?.characters, 40); XCTAssertEqual(restored.state.days.first?.seconds, 20)
        store.updatePosition(3000, count: b.chapters[0].count, reading: true); XCTAssertEqual(store.state.days.first?.characters, 40)
        store.moveChapter(1); XCTAssertEqual(store.book?.chapter, 1); XCTAssertEqual(store.book?.offset, 0)
    }
    @Test func testAnkiConnectProtocolAndErrorPropagation() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AnkiMock.self]
        let session = URLSession(configuration: config); var p = Preferences(); p.ankiKey = "test-key"
        let client = AnkiClient(p, session: session)
        let version = try await client.request("version"); XCTAssertEqual((version as? NSNumber)?.intValue, 6)
        do { _ = try await client.request("addNote"); XCTFail("Expected duplicate error") } catch { XCTAssertTrue(error.localizedDescription.contains("duplicate")) }
    }
}
final class AnkiMock: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream { stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096); while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count)) } }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        XCTAssertEqual(json["version"] as? Int, 6); XCTAssertEqual(json["key"] as? String, "test-key")
        let isVersion = json["action"] as? String == "version"
        let obj: [String: Any] = ["result": isVersion ? 6 : NSNull(), "error": isVersion ? NSNull() : "duplicate note"]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a == b, sourceLocation: sourceLocation) }
func XCTAssertTrue(_ a: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a, sourceLocation: sourceLocation) }
func XCTAssertFalse(_ a: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!a, sourceLocation: sourceLocation) }
func XCTAssertNotNil<T>(_ a: T?, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a != nil, sourceLocation: sourceLocation) }
func XCTAssertThrowsError(_ expression: @autoclosure () throws -> Any, sourceLocation: SourceLocation = #_sourceLocation) { do { _ = try expression(); Issue.record("Expected an error", sourceLocation: sourceLocation) } catch {} }
func XCTFail(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) { Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation) }
