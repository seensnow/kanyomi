import Foundation

// Previous identifiers are only used to read and migrate existing installations.
enum ProductMigration {
    static let legacyService = "SimpleReaderMac"
    static func defaultLibraryRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KanyomiMac")
    }
    static func prepareLibrary(at destination: URL) throws {
        guard destination.standardizedFileURL == defaultLibraryRoot().standardizedFileURL else { return }
        let old = destination.deletingLastPathComponent().appendingPathComponent(legacyService)
        try moveLibrary(from: old, to: destination)
    }
    static func moveLibrary(from old: URL, to destination: URL) throws {
        if !FileManager.default.fileExists(atPath: destination.path), FileManager.default.fileExists(atPath: old.path) {
            try FileManager.default.moveItem(at: old, to: destination)
        }
    }
    static func preferences() {
        let defaults = UserDefaults.standard
        if let old = defaults.persistentDomain(forName: "local.simplereader.macos") {
            for (key, value) in old where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
        if defaults.string(forKey: "KanyomiGoogleClient") == nil, let old = defaults.string(forKey: "SimpleReaderGoogleClient") {
            defaults.set(old, forKey: "KanyomiGoogleClient")
        }
    }
    static func isSampleDictionary(_ title: String) -> Bool {
        title == "Kanyomi Sample Dictionary" || title == "SimpleReader Sample Dictionary"
    }
}
