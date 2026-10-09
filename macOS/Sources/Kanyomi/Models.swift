import Foundation

struct Chapter: Codable, Identifiable, Hashable {
    var id: String { path }
    var title: String
    var path: String
    var text: String
    var start: Int = 0
    var count: Int { text.utf16.count }
}
struct NavigationItem: Codable, Identifiable, Hashable {
    var id: String { path + title }
    var title: String
    var path: String
    var depth: Int
}
struct Book: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var author: String
    var cover: String?
    var chapters: [Chapter]
    var contents: [NavigationItem]
    var chapter = 0
    var offset = 0
    var lastOpened = Date.distantPast
    var shelf = ""
    var audio: String?
    var subtitles: [Cue] = []
    var audioPosition: Double = 0
    var audioRate: Float = 1
    var audioDelay: Double = 0
    var totalCharacters: Int { chapters.reduce(0) { $0 + $1.count } }
    var characterPosition: Int { guard chapters.indices.contains(chapter) else { return 0 }; return chapters[chapter].start + offset }
    var progress: Double { totalCharacters > 0 ? Double(characterPosition) / Double(totalCharacters) : 0 }
}
struct SavedPassage: Codable, Identifiable {
    var id = UUID()
    var bookID: UUID
    var chapter: Int
    var offset: Int
    var text: String
    var note = ""
    var kind = "bookmark"
    var created = Date()
}
struct ReadingDay: Codable, Identifiable {
    var id: String { "\(bookID)-\(date)" }
    var bookID: UUID
    var date: String
    var seconds: Double = 0
    var characters = 0
    var lookups = 0
    var cards = 0
    var modified = Date()
}
struct DictionaryRecord: Codable, Identifiable {
    var id: String
    var title: String
    var terms: Int
    var frequencies: Int
    var pitches: Int
    var kanji: Int
    var enabled = true
    var category = "bilingual"
    var summary: String { [terms > 0 ? "\(terms) terms" : nil, frequencies > 0 ? "frequency" : nil, pitches > 0 ? "pitch" : nil, kanji > 0 ? "kanji" : nil].compactMap { $0 }.joined(separator: " · ") }
}
struct Glossary: Identifiable {
    var id: String { dictionary + json }
    var dictionary: String
    var json: String
    var html: String
    var plain: String
    var definitionTags: [String] = []
    var termTags: [String] = []
}
struct WordResult: Identifiable {
    var id: String { expression + "|" + reading }
    var expression: String
    var reading: String
    var matched: String
    var reasons: [String]
    var glossaries: [Glossary]
    var frequencies: [String]
    var frequencyValues: [Int]
    var pitches: [String]
    var pitchPositions: [Int]
    var html: String { glossaries.map { "<section><small>\(escapeHTML($0.dictionary))</small>\($0.html)</section>" }.joined() }
}
struct MinedWord: Codable, Identifiable {
    var id = UUID()
    var expression: String
    var reading: String
    var sentence: String
    var definition: String
    var book: String
    var created = Date()
}
struct FieldMapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var field: String
    var template: String
}
struct Preferences: Codable, Equatable {
    var vertical = true
    var font = "Hiragino Mincho ProN"
    var fontSize: Double = 24
    var lineHeight: Double = 1.9
    var theme = "Night"
    var customBackground = "#f5f1e8"
    var customForeground = "#302c28"
    var customCSS = ""
    var showRuby = true
    var paged = false
    var scanLength = 24
    var dailyGoal = 30
    var ankiEndpoint = "http://127.0.0.1:8765"
    var ankiKey = ""
    var ankiDeck = "Default"
    var ankiModel = "Basic"
    var ankiTags = "Kanyomi Japanese"
    var allowDuplicates = false
    var mappings = [FieldMapping(field: "Front", template: "{expression}<br>{reading}<br>{sentence}"), FieldMapping(field: "Back", template: "{glossary}")]
    var audioURL = "https://assets.languagepod101.com/dictionary/japanese/audiomp3.php?kanji={term}&kana={reading}"
    var audioSourceType = "Direct audio"
    var background: String { theme == "Night" ? "#252525" : theme == "White" ? "#ffffff" : theme == "Custom" ? customBackground : "#f5f1e8" }
    var foreground: String { theme == "Night" ? "#e8e5e2" : theme == "Custom" ? customForeground : "#302c28" }
}
struct LibraryState: Codable {
    var version = 1
    var books: [Book] = []
    var shelves: [String] = []
    var passages: [SavedPassage] = []
    var days: [ReadingDay] = []
    var dictionaries: [DictionaryRecord] = []
    var words: [MinedWord] = []
    var preferences = Preferences()
}
struct Cue: Codable, Identifiable, Hashable {
    var id: Int
    var start: Double
    var end: Double
    var text: String
    var chapter: Int?
    var offset: Int?
}
enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
func escapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
}
func jsonString(_ value: Any) -> String { guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), let s = String(data: data, encoding: .utf8) else { return "null" }; return s }
