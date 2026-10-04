import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import ZIPFoundation
import CoreText

@MainActor
final class ReaderStore: ObservableObject {
    @Published var state = LibraryState()
    @Published var selectedBookID: UUID?
    @Published var section = "Library"
    @Published var selectedShelf = ""
    @Published var librarySearch = ""
    @Published var sortByTitle = false
    @Published var busy: String?
    @Published var error: String?
    @Published var message: String?
    @Published var results: [WordResult] = []
    @Published var lookupText = ""
    @Published var sentence = ""
    @Published var selectionOffset = 0
    @Published var selectedResult = 0
    @Published var selectedGlossary = 0
    @Published var popupSelectionText = ""
    @Published var dictionaryCSS = ""
    @Published var kanjiText = ""
    @Published var searching = false
    @Published var isTiming = true
    @Published var jumpOffset: Int?
    @Published var jumpFragment: String?
    @Published var navigationRevision = 0
    @Published var ankiDecks: [String] = []
    @Published var ankiModels: [String] = []
    @Published var ankiFields: [String] = []
    @Published var playingAudio = false
    @Published var audioTime: Double = 0
    @Published var currentCue: Cue?
    private let rootURL: URL
    var root: URL { rootURL.standardizedFileURL }
    let engine = DictionaryEngine()
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?
    private var lookupGeneration = 0
    private var lastActivity = Date()
    private var lastTick = Date()
    private var player: AVPlayer?
    private var wordPlayer: AVPlayer?
    private let speech = AVSpeechSynthesizer()
    var book: Book? { state.books.first { $0.id == selectedBookID } }
    var activeResult: WordResult? { results.indices.contains(selectedResult) ? results[selectedResult] : nil }
    var contentRoot: URL? { book.map { root.appendingPathComponent("Books/\($0.id)/Content") } }
    var preferences: Preferences { get { state.preferences } set { state.preferences = newValue; saveSoon() } }
    var filteredBooks: [Book] {
        state.books.filter { (selectedShelf.isEmpty || $0.shelf == selectedShelf) && (librarySearch.isEmpty || ($0.title + $0.author).localizedCaseInsensitiveContains(librarySearch)) }.sorted { sortByTitle ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.lastOpened > $1.lastOpened }
    }
    init(root: URL? = nil, startTimer: Bool = true) {
        let override = ProcessInfo.processInfo.environment["SIMPLEREADER_DATA_DIR"]
        self.rootURL = (root ?? override.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SimpleReaderMac")).standardizedFileURL
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            let file = self.root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: file.path) { state = try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: file)) }
        } catch { self.error = "Could not load library. Existing files have been preserved. \(error.localizedDescription)" }
        if let fonts = try? FileManager.default.contentsOfDirectory(at: self.root.appendingPathComponent("Fonts"), includingPropertiesForKeys: nil) { for font in fonts { CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil) } }
        Task { await rebuildDictionaries() }
        if ProcessInfo.processInfo.arguments.contains("--demo"), state.books.isEmpty { Task { loadSample() } }
        if startTimer { timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } } }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.save(); self?.player?.pause() } }
    }
    func saveSoon() {
        saveWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.save() }; saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func save() {
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(state).write(to: root.appendingPathComponent("library.json"), options: .atomic) }
        catch { self.error = "Could not save library: \(error.localizedDescription)" }
    }
    func run(_ label: String, operation: @escaping () async throws -> Void) {
        guard busy == nil else { return }; busy = label
        Task { do { try await operation() } catch { self.error = error.localizedDescription }; busy = nil }
    }
    func pickBooks() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importBooks(panel.urls) }
    }
    func importBooks(_ urls: [URL]) {
        run("Importing books…") { [self] in
            var failures: [String] = []
            for url in urls {
                let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard url.pathExtension.lowercased() == "epub" else { throw ReaderError.message("Choose an EPUB file") }
                    let root = root
                    let book = try await Task.detached { try EPUBImporter.load(url, root: root) }.value
                    state.books.append(book); save()
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            if !failures.isEmpty { throw ReaderError.message(failures.joined(separator: "\n")) }
            section = "Library"
        }
    }
    func loadSample() {
        run("Preparing sample book and dictionary…") { [self] in
            guard let url = Bundle.readerResources.url(forResource: "Sample", withExtension: "epub", subdirectory: "Resources"), let dictionary = Bundle.readerResources.url(forResource: "SampleDictionary", withExtension: "zip", subdirectory: "Resources") else { throw ReaderError.message("Sample resources missing") }
            let root = root; let book = try await Task.detached { try EPUBImporter.load(url, root: root) }.value
            state.books.append(book)
            if !state.dictionaries.contains(where: { $0.title == "SimpleReader Sample Dictionary" }) { let d = try await engine.importZip(dictionary, root: root); state.dictionaries.append(d); await rebuildDictionaries() }
            save(); openBook(book.id)
        }
    }
    func openBook(_ id: UUID) {
        guard let i = state.books.firstIndex(where: { $0.id == id }) else { return }
        player?.pause(); player = nil; playingAudio = false; currentCue = nil
        state.books[i].lastOpened = Date(); selectedBookID = id; section = "Library"
        jumpOffset = state.books[i].offset; jumpFragment = nil; navigationRevision += 1
        results = []; kanjiText = ""; lastActivity = Date(); lastTick = Date(); saveSoon()
        if let audio = state.books[i].audio { player = AVPlayer(url: root.appendingPathComponent("Books/\(id)/\(audio)")); player?.seek(to: CMTime(seconds: state.books[i].audioPosition, preferredTimescale: 600)); audioTime = state.books[i].audioPosition }
    }
    func closeBook() { player?.pause(); playingAudio = false; player = nil; selectedBookID = nil; results = []; save() }
    func mutateBook(_ body: (inout Book) -> Void) { guard let i = state.books.firstIndex(where: { $0.id == selectedBookID }) else { return }; body(&state.books[i]); saveSoon() }
    func moveChapter(_ delta: Int) { guard let book else { return }; navigate(chapter: book.chapter + delta, offset: 0) }
    func navigate(chapter: Int, offset: Int, fragment: String? = nil) {
        guard let book, book.chapters.indices.contains(chapter) else { return }
        mutateBook { $0.chapter = chapter; $0.offset = max(0, min(offset, $0.chapters[chapter].count)) }
        jumpOffset = offset; jumpFragment = fragment; navigationRevision += 1; lastActivity = Date()
    }
    func navigate(path: String) {
        let parts = path.components(separatedBy: "#")
        guard let book, let index = book.chapters.firstIndex(where: { $0.path == parts[0] }) else { return }
        navigate(chapter: index, offset: 0, fragment: parts.count > 1 ? parts[1] : nil)
    }
    func updatePosition(_ offset: Int, count: Int, reading: Bool) {
        guard let book else { return }
        let previous = book.offset
        mutateBook { b in
            let chapter = b.chapter
            b.offset = max(0, min(offset, max(count, b.chapters[chapter].count)))

        }
        if reading { lastActivity = Date(); let delta = offset - previous; if isTiming && delta > 0 && delta <= 2000 { record(characters: delta) } }
    }
    func activity() { lastActivity = Date() }
    func addBookmark(kind: String = "bookmark") {
        guard let book else { return }
        let text = kind == "highlight" ? (activeResult?.matched ?? (lookupText.isEmpty ? sentence : lookupText)) : book.chapters[book.chapter].title
        state.passages.append(SavedPassage(bookID: book.id, chapter: book.chapter, offset: kind == "highlight" ? selectionOffset : book.offset, text: text, kind: kind)); saveSoon(); message = kind == "highlight" ? "Highlight saved" : "Bookmark saved"
    }
    func jump(to passage: SavedPassage) { if selectedBookID != passage.bookID { openBook(passage.bookID) }; navigate(chapter: passage.chapter, offset: passage.offset) }
    func deleteBook(_ id: UUID) {
        let alert = NSAlert(); alert.messageText = "Remove this book?"; alert.informativeText = "The imported copy and its bookmarks will be removed. Your original EPUB stays on disk."; alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try FileManager.default.removeItem(at: root.appendingPathComponent("Books/\(id)")); if selectedBookID == id { closeBook() }; state.books.removeAll { $0.id == id }; state.passages.removeAll { $0.bookID == id }; save() } catch { self.error = error.localizedDescription }
    }
    func pickDictionary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importDictionaries(panel.urls) }
    }
    func importDictionaries(_ urls: [URL]) {
        run("Importing Yomitan dictionaries…") { [self] in
            var failures: [String] = []
            for url in urls {
                let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
                do { let record = try await engine.importZip(url, root: root); state.dictionaries.append(record); save() }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            await rebuildDictionaries()
            if !failures.isEmpty { throw ReaderError.message(failures.joined(separator: "\n")) }
        }
    }
    func rebuildDictionaries() async { await engine.rebuild(state.dictionaries, root: root); dictionaryCSS = await engine.css() }
    func updateDictionaries() { saveSoon(); Task { await rebuildDictionaries() } }
    func removeDictionary(_ id: String) {
        run("Removing dictionary…") { [self] in
            state.dictionaries.removeAll { $0.id == id }; await rebuildDictionaries()
            try FileManager.default.removeItem(at: root.appendingPathComponent("Dictionaries/\(id)")); save()
        }
    }
    func lookup(_ text: String, sentence: String = "", offset: Int = 0, fromBook: Bool = false) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        lookupGeneration += 1; let generation = lookupGeneration
        lookupText = text; self.sentence = sentence; selectionOffset = offset; selectedResult = 0; selectedGlossary = 0; popupSelectionText = ""; searching = true; kanjiText = ""
        if fromBook { record(lookups: 1); if playingAudio { toggleAudiobook() } }; activity()
        Task {
            let found = await engine.search(text, scanLength: preferences.scanLength)
            let kanji = text.count == 1 ? await engine.kanji(text) : ""
            guard generation == lookupGeneration else { return }; results = found; kanjiText = kanji; searching = false
        }
    }
    func record(seconds: Double = 0, characters: Int = 0, lookups: Int = 0, cards: Int = 0) {
        guard let id = selectedBookID else { return }; let date = Self.dateKey(Date())
        if !state.days.contains(where: { $0.bookID == id && $0.date == date }) { state.days.append(ReadingDay(bookID: id, date: date)) }
        if let i = state.days.firstIndex(where: { $0.bookID == id && $0.date == date }) { state.days[i].seconds += seconds; state.days[i].characters += characters; state.days[i].lookups += lookups; state.days[i].cards += cards; state.days[i].modified = Date() }; saveSoon()
    }
    static func dateKey(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: date) }
    private func tick() {
        let now = Date(); let elapsed = min(2, now.timeIntervalSince(lastTick)); lastTick = now
        if isTiming && book != nil && NSApp.isActive && now.timeIntervalSince(lastActivity) < 90 { record(seconds: elapsed) }
        if let player, playingAudio, let book {
            let time = player.currentTime().seconds
            guard time.isFinite else { return }; audioTime = time
            mutateBook { $0.audioPosition = time }
            let cue = book.subtitles.first(where: { time + book.audioDelay >= $0.start && time + book.audioDelay < $0.end })
            if cue?.id != currentCue?.id { currentCue = cue; if let cue, let ch = cue.chapter, let offset = cue.offset { navigate(chapter: ch, offset: offset) } }
            if player.currentItem?.duration.seconds.isFinite == true, time >= player.currentItem!.duration.seconds { playingAudio = false }
        }
    }
    func speak(_ result: WordResult) { speech.stopSpeaking(at: .immediate); let utterance = AVSpeechUtterance(string: result.reading.isEmpty ? result.expression : result.reading); utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP"); speech.speak(utterance) }
    func playWord(_ result: WordResult) {
        run("Loading pronunciation…") { [self] in
            let url = try AudioSource.resolve(preferences.audioURL, result: result)
            let audio = try await AudioSource.download(url, type: preferences.audioSourceType)
            let file = root.appendingPathComponent("pronunciation.\(audio.ext)")
            try audio.data.write(to: file, options: .atomic); wordPlayer = AVPlayer(url: file); wordPlayer?.play()
        }
    }
    func connectAnki() {
        run("Connecting to Anki…") { [self] in
            let client = AnkiClient(preferences)
            _ = try await client.request("version")
            ankiDecks = try await client.request("deckNames") as? [String] ?? []
            ankiModels = try await client.request("modelNames") as? [String] ?? []
            ankiFields = try await client.request("modelFieldNames", ["modelName": preferences.ankiModel]) as? [String] ?? []
            message = "Anki connected · \(ankiDecks.count) decks"
        }
    }
    func mine(_ result: WordResult, toAnki: Bool) {
        let miningSentence = sentence; let miningSelection = popupSelectionText; let miningBook = book; let glossaryIndex = selectedGlossary
        run(toAnki ? "Adding note to Anki…" : "Saving word…") { [self] in
            var word = MinedWord(expression: result.expression, reading: result.reading, sentence: miningSentence, definition: result.glossaries.map(\.plain).joined(separator: "\n"), book: miningBook?.title ?? "Dictionary")
            if toAnki {
                let client = AnkiClient(preferences)
                var media: [String: String] = [:]
                let template = preferences.mappings.map(\.template).joined()
                if template.contains("{audio}") {
                    let audio = try await AudioSource.download(AudioSource.resolve(preferences.audioURL, result: result), type: preferences.audioSourceType)
                    let name = "sr-\(UUID().uuidString).\(audio.ext)"; _ = try await client.request("storeMediaFile", ["filename": name, "data": audio.data.base64EncodedString()]); media["audio"] = "[sound:\(name)]"
                }
                if template.contains("{book-cover}"), let book = miningBook, let cover = book.cover {
                    let file = root.appendingPathComponent("Books/\(book.id)/Content/\(cover)")
                    let name = "sr-cover-\(book.id).\(file.pathExtension)"; _ = try await client.request("storeMediaFile", ["filename": name, "data": try Data(contentsOf: file).base64EncodedString()]); media["book-cover"] = "<img src=\"\(name)\">"
                }
                if template.contains("{sasayaki-audio}") { guard let cue = currentCue, let book = miningBook, let audio = book.audio else { throw ReaderError.message("Play an audiobook cue before mining {sasayaki-audio}") }; let data = try await Audiobook.clip(root.appendingPathComponent("Books/\(book.id)/\(audio)"), start: cue.start, end: cue.end); let name = "sr-line-\(UUID().uuidString).m4a"; _ = try await client.request("storeMediaFile", ["filename": name, "data": data.base64EncodedString()]); media["sasayaki-audio"] = "[sound:\(name)]" }
                var prepared = result
                let imageRegex = try NSRegularExpression(pattern: "dictmedia:[^\"']+")
                var imageNames: [String: String] = [:]
                for i in prepared.glossaries.indices {
                    var html = prepared.glossaries[i].html
                    for match in imageRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
                        guard let range = Range(match.range, in: html) else { continue }
                        let src = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
                        if imageNames[src] == nil, let components = URLComponents(string: src), let query = components.queryItems, let dict = query.first(where: { $0.name == "dictionary" })?.value, let path = query.first(where: { $0.name == "path" })?.value {
                            let data = await engine.media(dictionary: dict, path: path)
                            if !data.isEmpty { let ext = URL(fileURLWithPath: path).pathExtension; let name = "sr-dict-\(UUID().uuidString).\(ext.isEmpty ? "png" : ext)"; _ = try await client.request("storeMediaFile", ["filename": name, "data": data.base64EncodedString()]); imageNames[src] = name }
                        }
                        if let name = imageNames[src] { html.replaceSubrange(range, with: name) }
                    }
                    prepared.glossaries[i].html = html
                }
                let chosen = prepared.glossaries.indices.contains(glossaryIndex) ? prepared.glossaries[glossaryIndex] : nil
                var fields: [String: String] = [:]
                for mapping in preferences.mappings where !mapping.field.isEmpty { fields[mapping.field] = try CardTemplate.render(mapping.template, result: prepared, sentence: miningSentence, selection: miningSelection, title: word.book, dictionaries: state.dictionaries, media: media, selectedGlossary: chosen) }
                guard !fields.isEmpty else { throw ReaderError.message("Configure Anki field mappings in Settings") }
                let note: [String: Any] = ["deckName": preferences.ankiDeck, "modelName": preferences.ankiModel, "fields": fields, "tags": preferences.ankiTags.split(separator: " ").map(String.init), "options": ["allowDuplicate": preferences.allowDuplicates]]
                let response = try await client.request("addNote", ["note": note]); guard let id = response as? NSNumber else { throw ReaderError.message("Anki did not return a note ID") }; word.ankiID = id.int64Value; record(cards: 1)
            }
            state.words.append(word); save(); message = toAnki ? "Added to Anki" : "Saved to vocabulary"
        }
    }
    func exportVocabulary() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "SimpleReader-vocabulary.tsv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func cell(_ s: String) -> String { s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "\r", with: "") }
        let text = "Expression\tReading\tSentence\tDefinition\tBook\n" + state.words.map { [$0.expression, $0.reading, $0.sentence, $0.definition, $0.book].map(cell).joined(separator: "\t") }.joined(separator: "\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
    }
    func importFont() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "ttf") ?? .data, UTType(filenameExtension: "otf") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let directory = root.appendingPathComponent("Fonts"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); let destination = directory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension); try FileManager.default.copyItem(at: url, to: destination); CTFontManagerRegisterFontsForURL(destination as CFURL, .process, nil); if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(destination as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first, let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String { preferences.font = name }; message = "Font imported" } catch { self.error = error.localizedDescription }
    }
    func pickAudiobook() {
        guard let book else { return }; let id = book.id
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run("Importing audiobook…") { [self] in let name = "audio.\(url.pathExtension)"; let destination = root.appendingPathComponent("Books/\(id)/\(name)"); if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }; try FileManager.default.copyItem(at: url, to: destination); mutateBook { $0.audio = name; $0.audioPosition = 0 }; player = AVPlayer(url: destination); audioTime = 0; message = "Audiobook ready" }
    }
    func pickSubtitles() {
        guard let book else { return }; let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run("Matching subtitles to book…") { [self] in
            let text = try String(contentsOf: url, encoding: .utf8)
            let cues = await Task.detached { Audiobook.match(Audiobook.parseSRT(text), chapters: book.chapters) }.value
            guard !cues.isEmpty else { throw ReaderError.message("No valid SRT cues found") }; mutateBook { $0.subtitles = cues }
            message = "Matched \(cues.filter { $0.chapter != nil }.count) / \(cues.count) cues"
        }
    }
    func toggleAudiobook() { guard let player else { return }; playingAudio.toggle(); if playingAudio { player.playImmediately(atRate: book?.audioRate ?? 1) } else { player.pause() }; activity() }
    func seekAudio(_ seconds: Double) { player?.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600)); audioTime = max(0, seconds); activity() }
    func setAudioRate(_ rate: Float) { mutateBook { $0.audioRate = rate }; if playingAudio { player?.rate = rate } }
    func replayCue() { if let cue = currentCue { seekAudio(cue.start); if !playingAudio { toggleAudiobook() } } }
    func backup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "SimpleReader-backup.zip"; panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }; save()
        run("Creating backup…") { [self] in let root = root; try await Task.detached { try FileManager.default.zipItem(at: root, to: url, shouldKeepParent: false) }.value; message = "Backup saved" }
    }
    func restore() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert(); alert.messageText = "Restore library from backup?"; alert.informativeText = "The current library will be replaced. A recovery copy is kept beside the library folder."; alert.addButton(withTitle: "Restore"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run("Restoring backup…") { [self] in
            let staging = root.deletingLastPathComponent().appendingPathComponent("SimpleReaderRestore-\(UUID())")
            defer { try? FileManager.default.removeItem(at: staging) }
            try EPUBImporter.extract(url, to: staging)
            let decoded = try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: staging.appendingPathComponent("library.json")))
            try Self.validateBackup(decoded, root: staging)
            saveWork?.cancel(); closeBook(); saveWork?.cancel()
            await engine.rebuild([], root: root)
            let old = root.deletingLastPathComponent().appendingPathComponent("SimpleReaderRecovery-\(UUID())")
            try FileManager.default.moveItem(at: root, to: old)
            do { try FileManager.default.moveItem(at: staging, to: root) } catch { try? FileManager.default.moveItem(at: old, to: root); throw error }
            state = decoded; await rebuildDictionaries(); save(); message = "Backup restored"
        }
    }
    static func validateBackup(_ state: LibraryState, root: URL) throws {
        guard state.version == 1 else { throw ReaderError.message("Unsupported backup version") }
        for b in state.books {
            let content = root.appendingPathComponent("Books/\(b.id)/Content")
            guard b.chapters.indices.contains(b.chapter) else { throw ReaderError.message("Invalid chapter in backup") }
            for ch in b.chapters { let url = try EPUBImporter.safeURL(ch.path, under: content); guard FileManager.default.fileExists(atPath: url.path) else { throw ReaderError.message("Backup is missing a chapter") } }
            if let cover = b.cover { _ = try EPUBImporter.safeURL(cover, under: content) }
            if let audio = b.audio { _ = try EPUBImporter.safeURL(audio, under: content.deletingLastPathComponent()) }
        }
        for d in state.dictionaries { guard UUID(uuidString: d.id) != nil, !d.title.contains("/"), !d.title.contains("\\"), d.title != "..", d.title != "." else { throw ReaderError.message("Invalid dictionary in backup") } }
    }
}
