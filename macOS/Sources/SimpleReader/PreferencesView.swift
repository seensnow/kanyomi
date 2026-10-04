import SwiftUI
import AppKit

struct AppearanceControls: View {
    @EnvironmentObject var store: ReaderStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reading appearance").font(.headline)
            Toggle("Vertical Japanese text", isOn: Binding(get: { store.preferences.vertical }, set: { store.preferences.vertical = $0 }))
            Toggle("Show ruby readings", isOn: Binding(get: { store.preferences.showRuby }, set: { store.preferences.showRuby = $0 }))
            Picker("Theme", selection: Binding(get: { store.preferences.theme }, set: { store.preferences.theme = $0 })) { ForEach(["Paper", "White", "Night", "Custom"], id: \.self) { Text($0).tag($0) } }
            HStack { Text("Size"); Slider(value: Binding(get: { store.preferences.fontSize }, set: { store.preferences.fontSize = $0 }), in: 14...42, step: 1); Text("\(Int(store.preferences.fontSize))").monospacedDigit().frame(width: 28) }
            HStack { Text("Spacing"); Slider(value: Binding(get: { store.preferences.lineHeight }, set: { store.preferences.lineHeight = $0 }), in: 1.2...3, step: 0.1); Text(String(format: "%.1f", store.preferences.lineHeight)).monospacedDigit().frame(width: 28) }
            Picker("Font", selection: Binding(get: { store.preferences.font }, set: { store.preferences.font = $0 })) { ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { Text($0).tag($0) } }
            Button("Import font…") { store.importFont() }
        }
    }
}
struct PreferencesView: View {
    @EnvironmentObject var store: ReaderStore
    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AppearanceControls()
                    HStack { TextField("Background hex", text: bind(\.customBackground)); TextField("Text hex", text: bind(\.customForeground)) }.textFieldStyle(.roundedBorder)
                    Text("Custom CSS").font(.headline)
                    TextEditor(text: bind(\.customCSS)).font(.system(.caption, design: .monospaced)).frame(height: 140).border(.secondary.opacity(0.3))
                    Stepper("Daily reading goal: \(store.preferences.dailyGoal) minutes", value: bind(\.dailyGoal), in: 1...240)
                    Stepper("Dictionary scan length: \(store.preferences.scanLength)", value: bind(\.scanLength), in: 1...64)
                }.padding(24)
            }.tabItem { Label("Appearance", systemImage: "textformat") }
            VStack(alignment: .leading, spacing: 16) { Text("Dictionary order controls definition priority.").foregroundStyle(.secondary); Button("Import Yomitan ZIP…") { store.pickDictionary() }; DictionaryDownloads(); DictionaryList() }.padding(24).tabItem { Label("Dictionaries", systemImage: "character.book.closed") }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("AnkiConnect").font(.title2)
                    Text("Run desktop Anki with AnkiConnect installed. Configure the note fields below, then mine directly from the reader.").foregroundStyle(.secondary)
                    TextField("Endpoint", text: bind(\.ankiEndpoint)); SecureField("Optional API key", text: bind(\.ankiKey))
                    HStack { TextField("Deck", text: bind(\.ankiDeck)); if !store.ankiDecks.isEmpty { Menu("Choose") { ForEach(store.ankiDecks, id: \.self) { deck in Button(deck) { store.preferences.ankiDeck = deck } } } } }
                    HStack { TextField("Note type", text: bind(\.ankiModel)); if !store.ankiModels.isEmpty { Menu("Choose") { ForEach(store.ankiModels, id: \.self) { model in Button(model) { store.preferences.ankiModel = model; store.connectAnki() } } } } }
                    TextField("Tags separated by spaces", text: bind(\.ankiTags)); Toggle("Allow duplicate notes", isOn: bind(\.allowDuplicates))
                    Button("Connect / refresh fields") { store.connectAnki() }.disabled(store.busy != nil)
                    if !store.ankiFields.isEmpty { Text("Fields: " + store.ankiFields.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    Divider(); Text("Field templates").font(.headline)
                    ForEach(store.preferences.mappings) { mapping in
                        VStack(alignment: .leading, spacing: 6) { HStack { TextField("Anki field name", text: mappingBind(mapping.id, \.field)); Button { store.state.preferences.mappings.removeAll { $0.id == mapping.id }; store.saveSoon() } label: { Image(systemName: "minus.circle") } }; TextField("Template", text: mappingBind(mapping.id, \.template), axis: .vertical).font(.system(.caption, design: .monospaced)).lineLimit(2...6) }
                    }
                    HStack { Button("Add field") { store.state.preferences.mappings.append(FieldMapping(field: "", template: "{expression}")); store.saveSoon() }; Button("Lapis preset") { store.state.preferences.mappings = [FieldMapping(field: "Expression", template: "{expression}"), FieldMapping(field: "ExpressionFurigana", template: "{furigana-plain}"), FieldMapping(field: "ExpressionReading", template: "{reading}"), FieldMapping(field: "ExpressionAudio", template: "{audio}"), FieldMapping(field: "MainDefinition", template: "{glossary-first}"), FieldMapping(field: "Sentence", template: "{sentence}"), FieldMapping(field: "Picture", template: "{book-cover}"), FieldMapping(field: "Glossary", template: "{glossary}"), FieldMapping(field: "PitchPosition", template: "{pitch-accent-positions}"), FieldMapping(field: "PitchCategories", template: "{pitch-accent-categories}"), FieldMapping(field: "Frequency", template: "{frequencies}"), FieldMapping(field: "FreqSort", template: "{frequency-harmonic-rank}"), FieldMapping(field: "MiscInfo", template: "{document-title}")]; store.saveSoon() } }
                    DisclosureGroup("Supported Hoshi markers") { Text(CardTemplate.supported.map { "{\($0)}" }.joined(separator: "  ")).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }.textFieldStyle(.roundedBorder).padding(24)
            }.tabItem { Label("Anki", systemImage: "rectangle.on.rectangle") }
            VStack(alignment: .leading, spacing: 20) {
                Text("Word pronunciation").font(.title2)
                Text("Use a direct audio URL or a Yomitan JSON audio source, including a local AnkiConnect Android audio server. {term} and {reading} are replaced with the looked-up word.").foregroundStyle(.secondary)
                Picker("Source type", selection: bind(\.audioSourceType)) { Text("Direct audio").tag("Direct audio"); Text("Yomitan JSON").tag("Yomitan JSON") }
                TextField("Audio URL template", text: bind(\.audioURL), axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
                Text("The waveform button uses the Mac's Japanese speech voice. The speaker button uses this source.").font(.caption).foregroundStyle(.secondary)
                Divider(); Text("Audiobooks").font(.headline); Text("Open a book → Contents → Audiobook. Import an MP3 or M4B and matching SRT subtitles to follow along. Use {sasayaki-audio} to mine the active cue into Anki.").foregroundStyle(.secondary)
                Spacer()
            }.padding(24).tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            VStack(alignment: .leading, spacing: 20) {
                Text("SimpleReader for macOS").font(.title)
                Text("0.1.0 beta 4 · Native SwiftUI + AppKit + WebKit")
                Text("Inspired by Hoshi Reader. Offline dictionary lookup uses its hoshidicts engine, including Yomitan's Japanese deinflection rules. This is an independent GPL-3.0 application.").foregroundStyle(.secondary)
                Link("Hoshi Reader", destination: URL(string: "https://github.com/Manhhao/Hoshi-Reader")!)
                Link("Yomitan dictionaries", destination: URL(string: "https://github.com/yomidevs/jmdict-yomitan/releases")!)
                Button("Show local library folder") { NSWorkspace.shared.open(store.root) }
                Text("No bundled commercial books or dictionaries. Import the dictionaries you use with Yomitan. Online pronunciation and Google Drive sync only run when requested.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(24).tabItem { Label("About", systemImage: "info.circle") }
        }.padding(12)
    }
    func bind<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> { Binding(get: { store.preferences[keyPath: path] }, set: { store.preferences[keyPath: path] = $0 }) }
    func mappingBind(_ id: UUID, _ path: WritableKeyPath<FieldMapping, String>) -> Binding<String> { Binding(get: { store.preferences.mappings.first { $0.id == id }?[keyPath: path] ?? "" }, set: { value in if let i = store.state.preferences.mappings.firstIndex(where: { $0.id == id }) { store.state.preferences.mappings[i][keyPath: path] = value; store.saveSoon() } }) }
}
