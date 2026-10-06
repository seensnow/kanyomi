import SwiftUI
import AppKit
import Charts

private let accent = Color(red: 0.66, green: 0.36, blue: 0.25)
struct MainView: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    @State private var shelfName = ""
    @State private var addingShelf = false
    var body: some View {
        let _ = interfaceLocale
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) { Image(systemName: "sparkle").font(.title).foregroundStyle(accent); VStack(alignment: .leading) { Text("SimpleReader").font(.headline); Text("macOS · beta 5").font(.caption).foregroundStyle(.secondary) } }.padding(20)
                List(selection: $store.section) {
                    Label(L("Library"), systemImage: "books.vertical").tag("Library")
                    Label(L("Dictionary"), systemImage: "character.book.closed").tag("Dictionary")
                    Label(L("Vocabulary"), systemImage: "tray.full").tag("Vocabulary")
                    Label(L("Statistics"), systemImage: "chart.bar.xaxis").tag("Statistics")
                    Label(L("Sync & Backup"), systemImage: "arrow.triangle.2.circlepath").tag("Sync")
                    Section(L("Bookshelves")) {
                        Button { store.selectedShelf = ""; store.section = "Library"; store.closeBook() } label: { Label(L("All books"), systemImage: "square.grid.2x2") }.buttonStyle(.plain)
                        ForEach(store.state.shelves, id: \.self) { shelf in
                            Button { store.selectedShelf = shelf; store.section = "Library"; store.closeBook() } label: { Label(shelf, systemImage: "folder") }.buttonStyle(.plain)
                                .contextMenu { Button(L("Remove shelf")) { store.state.shelves.removeAll { $0 == shelf }; for i in store.state.books.indices where store.state.books[i].shelf == shelf { store.state.books[i].shelf = "" }; if store.selectedShelf == shelf { store.selectedShelf = "" }; store.saveSoon() } }
                        }
                        Button { addingShelf = true } label: { Label(L("New shelf"), systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.listStyle(.sidebar)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    let today = store.state.days.filter { $0.date == ReaderStore.dateKey(Date()) }.reduce(0.0) { $0 + $1.seconds } / 60
                    HStack { Text(L("TODAY")).font(.caption2).tracking(1.8); Spacer(); Text("\(Int(today)) / \(store.preferences.dailyGoal) min").font(.caption) }.foregroundStyle(.secondary)
                    ProgressView(value: min(1, today / Double(max(1, store.preferences.dailyGoal)))).tint(accent)
                }.padding(18)
                SettingsLink { Label(L("Settings"), systemImage: "gearshape") }.buttonStyle(.plain).padding(.horizontal, 18).padding(.bottom, 18)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch store.section {
                case "Dictionary": DictionaryPage()
                case "Vocabulary": VocabularyView()
                case "Statistics": StatisticsView()
                case "Sync": SyncView()
                default: if let book = store.book { ReadingView(book: book) } else { LibraryView() }
                }
            }
        }
        .tint(accent)
        .overlay(alignment: .bottom) {
            if let busy = store.busy { HStack { ProgressView().controlSize(.small); Text(busy) }.padding(12).background(.regularMaterial, in: Capsule()).padding(18) }
            else if let message = store.message { Text(message).padding(12).background(.regularMaterial, in: Capsule()).padding(18).onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if store.message == message { store.message = nil } } }.id(message) }
        }
        .alert("SimpleReader", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button(L("OK")) { store.error = nil } } message: { Text(store.error ?? "") }
        .alert(L("New Bookshelf"), isPresented: $addingShelf) { TextField(L("Name"), text: $shelfName); Button(L("Create")) { let name = shelfName.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty && !store.state.shelves.contains(name) { store.state.shelves.append(name); store.saveSoon() }; shelfName = "" }; Button(L("Cancel"), role: .cancel) {} }
        .onChange(of: store.section) { _, value in if value != "Library" { store.closeBook() } }
    }
}
struct LibraryView: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    var body: some View {
        let _ = interfaceLocale
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading, spacing: 8) { Text(store.selectedShelf.isEmpty ? L("Your reading room") : store.selectedShelf).font(.system(size: 32, weight: .medium, design: .serif)); Text(L("%d books · A little Japanese, every day.", store.filteredBooks.count)).foregroundStyle(.secondary) }; Spacer(); Button { store.pickBooks() } label: { Label(L("Import EPUB"), systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(store.busy != nil) }.padding(30)
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(L("Search title or author"), text: $store.librarySearch).textFieldStyle(.plain); Spacer(); Picker(L("Sort"), selection: $store.sortByTitle) { Text(L("Recently read")).tag(false); Text(L("Title")).tag(true) }.frame(width: 190) }.padding(.horizontal, 30).padding(.bottom, 20)
            Divider()
            if store.state.books.isEmpty {
                ContentUnavailableView { Label(L("Make room for a good book"), systemImage: "book.closed") } description: { Text(L("Import a Japanese EPUB, add your Yomitan dictionaries, and start reading.\nYour library lives on this Mac.")) } actions: { Button(L("Import EPUB…")) { store.pickBooks() }.buttonStyle(.borderedProminent); Button(L("Try sample book & dictionary")) { store.loadSample() } }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 28)], alignment: .leading, spacing: 30) {
                        ForEach(store.filteredBooks) { book in BookTile(book: book) }
                    }.padding(30)
                }
            }
        }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle(L("Library"))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers { _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in store.importBooks([url]) } } } }; return true
        }
    }
}
struct BookTile: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    let book: Book
    var body: some View {
        let _ = interfaceLocale
        Button { store.openBook(book.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.87, green: 0.84, blue: 0.76).gradient)
                    if let cover = book.cover, let image = NSImage(contentsOf: store.root.appendingPathComponent("Books/\(book.id)/Content/\(cover)")) { GeometryReader { geometry in
                        Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } }
                    else { VStack(spacing: 18) { Image(systemName: "sparkle").font(.largeTitle); Text(book.title).font(.system(size: 24, design: .serif)).multilineTextAlignment(.center); Text(book.author).font(.caption) }.foregroundStyle(Color(red: 0.29, green: 0.29, blue: 0.25)).padding(20) }
                }.aspectRatio(0.7, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8)).shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                Text(book.title).font(.headline).lineLimit(2).frame(height: 38, alignment: .topLeading)
                Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack { ProgressView(value: max(0, min(1, book.progress))).tint(accent); Text("\(Int(book.progress * 100))%").font(.caption2).foregroundStyle(.secondary) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
        .contextMenu {
            Button(L("Read")) { store.openBook(book.id) }
            Menu("Move to shelf") {
                Button(L("None")) { setShelf("") }
                ForEach(store.state.shelves, id: \.self) { shelf in Button(shelf) { setShelf(shelf) } }
            }
            Button(L("Reveal imported EPUB")) { NSWorkspace.shared.activateFileViewerSelecting([store.root.appendingPathComponent("Books/\(book.id)/Original.epub")]) }
            Divider(); Button(L("Remove book…"), role: .destructive) { store.deleteBook(book.id) }
        }
    }
    func setShelf(_ value: String) { if let i = store.state.books.firstIndex(where: { $0.id == book.id }) { store.state.books[i].shelf = value; store.saveSoon() } }
}
struct ReadingView: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    let book: Book
    @State private var showContents = false
    @State private var showDictionary = true
    @State private var showAppearance = false
    @State private var tab = "Contents"
    @State private var bookSearch = ""
    var body: some View {
        let _ = interfaceLocale
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { store.closeBook() } label: { Image(systemName: "chevron.left") }.help(L("Back to library"))
                Button { showContents.toggle() } label: { Image(systemName: "list.bullet") }.help(L("Contents, search and bookmarks"))
                VStack(alignment: .leading, spacing: 3) { Text(book.title).font(.headline).lineLimit(1); Text(book.chapters[book.chapter].title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Button { store.isTiming.toggle() } label: { Image(systemName: store.isTiming ? "pause.circle" : "play.circle") }.help(L("Pause / resume reading statistics"))
                Button { store.addBookmark() } label: { Image(systemName: "bookmark") }.help(L("Add bookmark · ⌘D"))
                Button { showAppearance.toggle() } label: { Image(systemName: "textformat.size") }.popover(isPresented: $showAppearance) { AppearanceControls().environmentObject(store).padding(20).frame(width: 340) }
                Button { showDictionary.toggle() } label: { Image(systemName: "character.book.closed") }.help(L("Dictionary"))
            }.buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            HStack(spacing: 0) {
                if showContents { contentsPanel.frame(width: 245); Divider() }
                ReaderWebView(book: book).environmentObject(store)
                if showDictionary { Divider(); DictionaryPanel().frame(width: 350) }
            }
            Divider()
            if book.audio != nil { AudiobookBar() }
            HStack {
                Button { store.moveChapter(-1) } label: { Image(systemName: "chevron.left") }.disabled(book.chapter == 0)
                Text("\(book.chapter + 1) / \(book.chapters.count)").font(.caption).monospacedDigit()
                Button { store.moveChapter(1) } label: { Image(systemName: "chevron.right") }.disabled(book.chapter + 1 >= book.chapters.count)
                Spacer(); Text(L("Click a word · Shift + hover to look up")).font(.caption).foregroundStyle(.secondary); Spacer()
                Text("\(Int(book.progress * 100))% · \(book.characterPosition.formatted()) / \(book.totalCharacters.formatted()) 字").font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.borderless).padding(12)
        }.navigationTitle(book.title)
    }
    var contentsPanel: some View {
        VStack(spacing: 8) {
            Picker(L("Navigation"), selection: $tab) { Text(L("Contents")).tag("Contents"); Text(L("Saved")).tag("Saved"); Text(L("Search")).tag("Search") }.pickerStyle(.segmented).padding(10)
            if tab == "Contents" {
                List {
                    if !book.contents.isEmpty { ForEach(book.contents) { entry in Button { store.navigate(path: entry.path) } label: { Text(entry.title).padding(.leading, CGFloat(entry.depth) * 8).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) } }
                    else { ForEach(Array(book.chapters.enumerated()), id: \.offset) { i, ch in Button(ch.title) { store.navigate(chapter: i, offset: 0) }.buttonStyle(.plain) } }
                }
            } else if tab == "Saved" {
                List { ForEach(store.state.passages.filter { $0.bookID == book.id }) { passage in
                    VStack(alignment: .leading) { Button { store.jump(to: passage) } label: { Label(passage.text, systemImage: passage.kind == "highlight" ? "highlighter" : "bookmark").lineLimit(3) }.buttonStyle(.plain); TextField(L("Add a note…"), text: Binding(get: { store.state.passages.first(where: { $0.id == passage.id })?.note ?? "" }, set: { value in if let i = store.state.passages.firstIndex(where: { $0.id == passage.id }) { store.state.passages[i].note = value; store.saveSoon() } })).font(.caption) }
                        .contextMenu { Button(L("Remove")) { store.state.passages.removeAll { $0.id == passage.id }; store.saveSoon() } }
                } }
            } else {
                TextField("Search in book", text: $bookSearch).textFieldStyle(.roundedBorder).padding(.horizontal, 10)
                List { ForEach(searchHits, id: \.id) { hit in Button { store.navigate(chapter: hit.chapter, offset: hit.offset) } label: { VStack(alignment: .leading, spacing: 5) { Text(book.chapters[hit.chapter].title).font(.caption).foregroundStyle(.secondary); Text(hit.preview).lineLimit(3) } }.buttonStyle(.plain) } }
            }
            Menu(L("Audiobook")) { Button(L("Import audio…")) { store.pickAudiobook() }; Button(L("Match SRT subtitles…")) { store.pickSubtitles() } }.padding(10)
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    struct Hit { var chapter: Int; var offset: Int; var preview: String; var id: String { "\(chapter)-\(offset)" } }
    var searchHits: [Hit] {
        guard bookSearch.count >= 2 else { return [] }; var hits: [Hit] = []
        for (index, chapter) in book.chapters.enumerated() {
            let text = chapter.text as NSString; var start = 0
            while start < text.length && hits.count < 150 {
                let found = text.range(of: bookSearch, options: [.caseInsensitive], range: NSRange(location: start, length: text.length - start)); if found.location == NSNotFound { break }
                let lo = max(0, found.location - 16); let length = min(text.length - lo, found.length + 55)
                hits.append(Hit(chapter: index, offset: found.location, preview: text.substring(with: NSRange(location: lo, length: length)))); start = found.location + max(1, found.length)
            }
        }; return hits
    }
}
struct DictionaryPanel: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    var body: some View {
        let _ = interfaceLocale
        VStack(alignment: .leading, spacing: 0) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(L("Look up Japanese"), text: $query).textFieldStyle(.plain).onSubmit { store.lookup(query) } }.padding(16)
            Divider()
            if let word = store.activeResult {
                VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(word.expression).font(.system(size: 32, weight: .semibold, design: .serif)).textSelection(.enabled)
                                if word.reading != word.expression { Text(word.reading).font(.system(size: 17)).foregroundStyle(.secondary).textSelection(.enabled) }
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 8) {
                                Button { store.playWord(word) } label: {
                                    Label(L(store.pronunciationLoading ? "Loading…" : "Listen"), systemImage: "speaker.wave.2.fill")
                                }.buttonStyle(.borderedProminent).tint(.blue).disabled(store.pronunciationLoading).help(L("Play source audio; use Japanese speech if unavailable"))
                                Button { store.speak(word) } label: { Label(L("Japanese voice"), systemImage: "waveform") }.font(.caption).buttonStyle(.borderless).help(L("Read aloud using the Mac's Japanese voice"))
                            }
                        }
                        if !store.pronunciationStatus.isEmpty { Text(store.pronunciationStatus).font(.caption2).foregroundStyle(.secondary) }
                        if !word.reasons.isEmpty { Text(word.reasons.joined(separator: " → ")).font(.caption).foregroundStyle(.orange) }
                        if !word.frequencies.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                                ForEach(Array(word.frequencies.enumerated()), id: \.offset) { _, value in
                                    Text(value).font(.caption2).foregroundStyle(.purple).padding(.horizontal, 8).padding(.vertical, 4).background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 5)).textSelection(.enabled)
                                }
                            }
                        }
                        if store.results.count > 1 {
                            Text(L("%d matches · Scroll for all definitions", store.results.count)).font(.caption)
                        }
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(16).background(Color.blue.opacity(0.06))
                Divider()
                if word.glossaries.count > 1 { Picker(L("Mining definition"), selection: $store.selectedGlossary) { ForEach(Array(word.glossaries.enumerated()), id: \.offset) { i, glossary in Text(glossary.dictionary).tag(i) } }.padding(.horizontal, 12).padding(.vertical, 8) }
                GlossaryWebView(html: GlossaryDocument.matches(store.results), css: store.dictionaryCSS, engine: store.engine, theme: colorScheme == .dark ? "Night" : "White", onSelection: { store.popupSelectionText = $0 }, selectedMatch: store.selectedResult, onMatch: { index in
                    guard store.results.indices.contains(index), store.selectedResult != index else { return }
                    store.selectedGlossary = 0; store.popupSelectionText = ""; store.stopPronunciation(); store.selectedResult = index
                })
                if !store.sentence.isEmpty { Text(store.sentence).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled).padding(12) }
                HStack { Button(L("Save word")) { store.mine(word, toAnki: false) }; Button(L("Add to Anki")) { store.mine(word, toAnki: true) }.buttonStyle(.borderedProminent) }.disabled(store.busy != nil).padding(12)
                if store.book != nil { Button { store.addBookmark(kind: "highlight") } label: { Label(L("Highlight selection"), systemImage: "highlighter") }.buttonStyle(.borderless).padding(.horizontal, 12).padding(.bottom, 12) }
            } else if !store.kanjiText.isEmpty { ScrollView { Text(store.kanjiText).textSelection(.enabled).padding(20) } }
            else {
                VStack(spacing: 14) {
                    Image(systemName: "character.book.closed").font(.system(size: 42)).foregroundStyle(accent.opacity(0.7))
                    Text(L(store.lookupText.isEmpty ? "A word opens a world." : "No matching entries")).font(.system(size: 21, design: .serif))
                    Text(L(store.state.dictionaries.isEmpty ? "Import a Yomitan dictionary ZIP to look up words offline, including conjugated forms." : store.lookupText.isEmpty ? "Click a word in your book, or search above." : "Try another term, or add another dictionary.")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if store.state.dictionaries.isEmpty { Button(L("Import dictionary…")) { store.pickDictionary() } }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(nsColor: .controlBackgroundColor)).onChange(of: store.lookupText) { _, _ in store.stopPronunciation() }
    }
}
struct DictionaryPage: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    var body: some View {
        let _ = interfaceLocale
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(L("Your dictionaries")).font(.system(size: 30, design: .serif))
                        Text(L("Yomitan terms, frequencies, pitch accents and kanji. Search works offline after import.")).foregroundStyle(.secondary)
                        Button { store.pickDictionary() } label: { Label(L("Import dictionary ZIP…"), systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(store.busy != nil)
                        DictionaryDownloads()
                        Text(L("Installed dictionaries")).font(.headline)
                        DictionaryList().frame(height: max(220, geometry.size.height - 450))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                DictionaryPanel().frame(width: min(460, geometry.size.width * 0.46), height: geometry.size.height)
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.navigationTitle(L("Dictionary"))
    }
}
struct DictionaryDownloads: View {
    @Environment(\.locale) private var interfaceLocale
    @State private var expanded = true
    var body: some View {
        let _ = interfaceLocale
        DisclosureGroup(L("Recommended dictionaries · Download"), isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                download("Jitendex", detail: "Japanese–English definitions and examples · Start here", url: "https://github.com/stephenmk/stephenmk.github.io/releases/latest/download/jitendex-yomitan.zip")
                download("JMnedict", detail: "Japanese names: people and places", url: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMnedict.zip")
                download("KANJIDIC", detail: "Kanji meanings and readings · English", url: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/KANJIDIC_english.zip")
                Text(L("Download a ZIP, then choose Import dictionary ZIP… without unzipping it.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link(L("Jitendex website"), destination: URL(string: "https://jitendex.org/pages/downloads.html")!)
                    Link(L("More dictionaries"), destination: URL(string: "https://github.com/yomidevs/jmdict-yomitan")!)
                }.font(.caption)
            }.fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func download(_ title: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Link(destination: URL(string: url)!) { Label(title, systemImage: "arrow.down.circle") }
            Text(L(detail)).font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct DictionaryList: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    var body: some View {
        let _ = interfaceLocale
        List {
            ForEach(Array(store.state.dictionaries.enumerated()), id: \.element.id) { index, d in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Toggle(d.title, isOn: Binding(get: { store.state.dictionaries.first(where: { $0.id == d.id })?.enabled ?? false }, set: { enabled in if let i = store.state.dictionaries.firstIndex(where: { $0.id == d.id }) { store.state.dictionaries[i].enabled = enabled; store.updateDictionaries() } })); Spacer(); Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0); Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == store.state.dictionaries.count) }
                    Text(d.summary).font(.caption).foregroundStyle(.secondary)
                    HStack { Picker(L("Definitions"), selection: Binding(get: { store.state.dictionaries.first(where: { $0.id == d.id })?.category ?? "bilingual" }, set: { category in if let i = store.state.dictionaries.firstIndex(where: { $0.id == d.id }) { store.state.dictionaries[i].category = category; store.saveSoon() } })) { Text(L("Bilingual")).tag("bilingual"); Text(L("Monolingual")).tag("monolingual"); Text(L("Exclude from Anki")).tag("exclude") }; Spacer(); Button(L("Remove"), role: .destructive) { store.removeDictionary(d.id) } }
                }.padding(.vertical, 8)
            }
        }.overlay { if store.state.dictionaries.isEmpty { Text(L("No dictionaries imported yet")).foregroundStyle(.secondary) } }
    }
    func move(_ index: Int, _ delta: Int) { let next = index + delta; guard store.state.dictionaries.indices.contains(next) else { return }; store.state.dictionaries.swapAt(index, next); store.updateDictionaries() }
}
struct VocabularyView: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    @State private var search = ""
    var words: [MinedWord] { store.state.words.reversed().filter { search.isEmpty || ($0.expression + $0.reading + $0.definition).localizedCaseInsensitiveContains(search) } }
    var body: some View {
        let _ = interfaceLocale
        VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 7) { Text(L("Words worth keeping")).font(.system(size: 30, design: .serif)); Text(L("%d saved · %d sent to Anki", store.state.words.count, store.state.words.filter { $0.ankiID != nil }.count)).foregroundStyle(.secondary) }; Spacer(); Button(L("Export TSV…")) { store.exportVocabulary() } }
            TextField("Search vocabulary", text: $search).textFieldStyle(.roundedBorder)
            List(words) { word in
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) { Text(word.expression).font(.title2); Text(word.reading).foregroundStyle(.secondary) }.frame(width: 150, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) { Text(word.definition).lineLimit(3); Text(word.sentence).font(.caption).foregroundStyle(.secondary).lineLimit(2); Text(word.book).font(.caption2).foregroundStyle(accent) }
                    Spacer(); if word.ankiID != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help(L("Added to Anki")) }
                }.padding(.vertical, 10).textSelection(.enabled)
                .contextMenu { Button(L("Look up")) { store.section = "Dictionary"; store.lookup(word.expression) }; Button(L("Remove saved word")) { store.state.words.removeAll { $0.id == word.id }; store.saveSoon() } }
            }
        }.padding(30).navigationTitle(L("Vocabulary"))
    }
}
struct StatisticsView: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    @State private var period = 30
    struct Day: Identifiable { var id: String; var minutes: Double; var characters: Int }
    var days: [Day] {
        (0..<period).reversed().map { i in let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!; let key = ReaderStore.dateKey(date); let records = store.state.days.filter { $0.date == key }; return Day(id: key, minutes: records.reduce(0) { $0 + $1.seconds } / 60, characters: records.reduce(0) { $0 + $1.characters }) }
    }
    var body: some View {
        let _ = interfaceLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack { Text(L("Every page adds up.")).font(.system(size: 32, design: .serif)); Spacer(); Picker(L("Period"), selection: $period) { Text(L("7 days")).tag(7); Text(L("30 days")).tag(30); Text(L("90 days")).tag(90) }.frame(width: 170) }
                HStack(spacing: 18) {
                    metric("READING TIME", String(format: "%.1f h", store.state.days.reduce(0) { $0 + $1.seconds } / 3600))
                    metric("CHARACTERS", store.state.days.reduce(0) { $0 + $1.characters }.formatted())
                    metric("WORDS LOOKED UP", store.state.days.reduce(0) { $0 + $1.lookups }.formatted())
                    metric("ANKI NOTES", store.state.words.filter { $0.ankiID != nil }.count.formatted())
                }
                Text(L("Reading minutes")).font(.headline)
                Chart(days) { day in BarMark(x: .value("Date", String(day.id.suffix(5))), y: .value("Minutes", day.minutes)).foregroundStyle(accent.gradient) }.frame(height: 240)
                Text(L("Characters read")).font(.headline)
                Chart(days) { day in BarMark(x: .value("Date", String(day.id.suffix(5))), y: .value("Characters", day.characters)).foregroundStyle(Color(red: 0.42, green: 0.51, blue: 0.43).gradient) }.frame(height: 180)
                Text(L("Reading time pauses when this app is in the background or idle for 90 seconds. Large jumps and backward scrolling don't count as newly read characters.")).font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(store.state.books) { book in let records = store.state.days.filter { $0.bookID == book.id }; HStack { Text(book.title); Spacer(); Text("\(Int(records.reduce(0) { $0 + $1.seconds } / 60)) min · \(records.reduce(0) { $0 + $1.characters }.formatted()) 字").foregroundStyle(.secondary) } }
            }.padding(30)
        }.navigationTitle(L("Statistics"))
    }
    func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 14) { Text(L(title)).font(.caption2).tracking(1).foregroundStyle(.secondary); Text(value).font(.system(size: 28, design: .rounded)) }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12)) }
}
struct AudiobookBar: View {
    @Environment(\.locale) private var interfaceLocale
    @EnvironmentObject var store: ReaderStore
    var body: some View {
        let _ = interfaceLocale
        HStack(spacing: 14) {
            Button { store.seekAudio(store.audioTime - 10) } label: { Image(systemName: "gobackward.10") }
            Button { store.toggleAudiobook() } label: { Image(systemName: store.playingAudio ? "pause.fill" : "play.fill") }
            Button { store.seekAudio(store.audioTime + 10) } label: { Image(systemName: "goforward.10") }
            Text(String(format: "%02d:%02d", Int(store.audioTime) / 60, Int(store.audioTime) % 60)).font(.caption).monospacedDigit()
            Text(store.currentCue?.text ?? "Audiobook").font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Button(L("Replay line")) { store.replayCue() }.disabled(store.currentCue == nil)
            Picker(L("Speed"), selection: Binding(get: { store.book?.audioRate ?? 1 }, set: { store.setAudioRate($0) })) { ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { rate in Text(String(format: "%.2g×", rate)).tag(rate) } }.frame(width: 130)
            Stepper("Delay \(String(format: "%.1f", store.book?.audioDelay ?? 0))s", value: Binding(get: { store.book?.audioDelay ?? 0 }, set: { value in store.mutateBook { $0.audioDelay = value } }), in: -30...30, step: 0.5).font(.caption).frame(width: 130)
        }.buttonStyle(.borderless).padding(12).background(Color(nsColor: .controlBackgroundColor))
    }
}
