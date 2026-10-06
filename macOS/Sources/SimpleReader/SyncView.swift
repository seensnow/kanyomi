import SwiftUI
import AppKit

struct SyncView: View {
    @EnvironmentObject var store: ReaderStore
    @StateObject private var auth = GoogleAuthorization()
    @State private var selectedLocal: UUID?
    @State private var selectedRemote: String?
    @State private var remoteBooks: [DriveFile] = []
    @State private var rootFolder: String?
    @State private var includeStatistics = true
    @State private var includeAudio = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(L("Keep your place.")).font(.system(size: 32, design: .serif))
                Text(L("Back up this Mac, or exchange books and reading progress with ッツ Reader.")).foregroundStyle(.secondary)
                GroupBox(L("Local backup")) {
                    HStack { Text(L("Books, dictionaries, saved words, bookmarks and settings.")).foregroundStyle(.secondary); Spacer(); Button(L("Create backup…")) { store.backup() }; Button(L("Restore…")) { store.restore() } }.padding(12)
                }
                GroupBox(L("ッツ files")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Exchange the bookdata ZIP used by ッツ. Progress can also be exported or imported as a separate JSON file.")).foregroundStyle(.secondary)
                        localPicker
                        HStack { Button(L("Export bookdata…")) { exportBook() }.disabled(selectedLocal == nil); Button(L("Import bookdata…")) { importBook() }; Button(L("Export progress…")) { progress(export: true) }.disabled(selectedLocal == nil); Button(L("Import progress…")) { progress(export: false) }.disabled(selectedLocal == nil) }
                    }.padding(12)
                }
                GroupBox(L("Google Drive · ッツ sync")) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Use a Google OAuth Desktop client from the same Cloud project as your ッツ client. Enable the Drive API and drive.file scope. Credentials are stored in macOS Keychain.")).foregroundStyle(.secondary)
                        TextField(L("Desktop client ID"), text: $auth.clientID).textFieldStyle(.roundedBorder)
                        SecureField(L("Desktop client secret (if supplied by Google)"), text: $auth.clientSecret).textFieldStyle(.roundedBorder)
                        HStack { Button(L(auth.connected ? "Reconnect Google Drive" : "Connect Google Drive")) { store.run("Waiting for Google sign-in…") { try await auth.connect(); store.message = "Google Drive connected" } }; if store.busy == "Waiting for Google sign-in…" { Button(L("Cancel sign-in")) { auth.cancel() } }; if auth.connected { Button(L("Disconnect")) { auth.disconnect(); remoteBooks = []; rootFolder = nil } }; Spacer(); Link(L("Setup guide"), destination: URL(string: "https://github.com/Manhhao/Hoshi-Reader/blob/main/TTUSYNC.md")!) }
                        Divider()
                        Toggle(L("Sync reading statistics"), isOn: $includeStatistics); Toggle(L("Sync audiobook position"), isOn: $includeAudio)
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 12) { Text(L("THIS MAC")).font(.caption).foregroundStyle(.secondary); localPicker; Button(L("Push selected book to ッツ")) { push() }.disabled(selectedLocal == nil) }
                            Divider()
                            VStack(alignment: .leading, spacing: 12) { HStack { Text(L("GOOGLE DRIVE")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(L("Refresh")) { refresh() } }; Picker(L("Remote book"), selection: $selectedRemote) { Text(L("Choose a book")).tag(nil as String?); ForEach(remoteBooks) { remote in Text(remote.name.removingPercentEncoding ?? remote.name).tag(remote.id as String?) } }; Button(L("Pull selected book from ッツ")) { pull() }.disabled(selectedRemote == nil) }
                        }
                        Text(L("Push replaces remote progress with the selected local position. Pull replaces local progress for a matching title. Statistics keep the newer record for each day. In ッツ, disable password encryption and sync from Browser DB to GDrive before pulling here.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(12)
                }
            }.padding(30).disabled(store.busy != nil && store.busy != "Waiting for Google sign-in…")
        }.navigationTitle(L("Sync & Backup"))
    }
    var localPicker: some View { Picker(L("Local book"), selection: $selectedLocal) { Text(L("Choose a book")).tag(nil as UUID?); ForEach(store.state.books) { book in Text(book.title).tag(book.id as UUID?) } } }
    var localBook: Book? { store.state.books.first { $0.id == selectedLocal } }
    func exportBook() {
        guard let book = localBook else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = "bookdata_1_6_\(book.totalCharacters)_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int(book.lastOpened.timeIntervalSince1970 * 1000)).zip"; panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }; store.run("Exporting ッツ bookdata…") { let root = store.root; try await Task.detached { try TtuArchive.export(book, root: root, to: url) }.value; store.message = "ッツ bookdata exported" }
    }
    func importBook() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]; guard panel.runModal() == .OK, let url = panel.url else { return }
        store.run("Importing ッツ bookdata…") { let root = store.root; let book = try await Task.detached { try TtuArchive.importBook(url, root: root) }.value; store.state.books.append(book); store.save(); store.message = "ッツ book imported" }
    }
    func progress(export: Bool) {
        guard let book = localBook else { return }
        if export {
            let panel = NSSavePanel(); panel.nameFieldStringValue = "progress_1_6_\(Int(Date().timeIntervalSince1970 * 1000))_\(book.progress).json"; guard panel.runModal() == .OK, let url = panel.url else { return }
            do { let value = TtuProgress(exploredCharCount: book.characterPosition, progress: book.progress, lastBookmarkModified: Date()); let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; try encoder.encode(value).write(to: url, options: .atomic); store.message = "Progress exported" } catch { store.error = error.localizedDescription }
        } else {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; guard panel.runModal() == .OK, let url = panel.url else { return }
            do { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; let value = try decoder.decode(TtuProgress.self, from: Data(contentsOf: url)); applyProgress(value, bookID: book.id); store.save(); store.message = "Progress imported" } catch { store.error = error.localizedDescription }
        }
    }
    func refresh() {
        store.run("Listing ッツ books…") {
            let client = GoogleDriveClient(auth: auth); let root = try await client.folder("ttu-reader-data", create: false); rootFolder = root
            remoteBooks = try await client.list("trashed=false and '\(root)' in parents and mimeType='application/vnd.google-apps.folder'").sorted { $0.name < $1.name }
            store.message = "\(remoteBooks.count) remote books"
        }
    }
    func push() {
        guard let book = localBook else { return }
        store.run("Pushing book to ッツ…") {
            let client = GoogleDriveClient(auth: auth); let root = try await client.folder("ttu-reader-data"); rootFolder = root
            let folder = try await client.folder(TtuArchive.sanitizeTitle(book.title), parent: root)
            let files = try await client.children(folder)
            let ms = Int(Date().timeIntervalSince1970 * 1000)
            if !files.contains(where: { $0.name.hasPrefix("bookdata_") }) {
                let zip = store.root.appendingPathComponent("ttu-\(UUID()).zip"); defer { try? FileManager.default.removeItem(at: zip) }
                let localRoot = store.root; try await Task.detached { try TtuArchive.export(book, root: localRoot, to: zip) }.value
                try await client.upload(Data(contentsOf: zip), name: "bookdata_1_6_\(book.totalCharacters)_\(ms)_\(ms).zip", mime: "application/zip", folder: folder)
            }
            if !files.contains(where: { $0.name.hasPrefix("cover_") }), let cover = book.cover {
                let file = store.root.appendingPathComponent("Books/\(book.id)/Content/\(cover)")
                try await client.upload(Data(contentsOf: file), name: "cover_1_6.\(file.pathExtension)", mime: "image/\(file.pathExtension == "jpg" ? "jpeg" : file.pathExtension)", folder: folder)
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
            let position = TtuProgress(exploredCharCount: book.characterPosition, progress: book.progress, lastBookmarkModified: Date())
            try await client.upload(encoder.encode(position), name: "progress_1_6_\(ms)_\(book.progress).json", mime: "application/json", folder: folder, replacing: latest(files, prefix: "progress_"))
            if includeStatistics {
                var stats = localStats(book)
                if let remote = latest(files, prefix: "statistics_") { let remoteStats = try JSONDecoder().decode([TtuStatistic].self, from: await client.download(remote)); stats = mergeStats(stats, remoteStats) }
                let seconds = stats.reduce(0.0) { $0 + $1.readingTime }; let count = stats.reduce(0) { $0 + $1.charactersRead }; let speed = seconds > 0 ? Int(3600 * Double(count) / seconds) : 0; let days = max(1, stats.count)
                let name = "statistics_1_6_\(ms)_\(count)_\(seconds)_0_0_\(speed)_\(speed)_\(Int(seconds) / days)_0_\(count / days)_0_\(speed)_\(speed)_na.json"
                try await client.upload(encoder.encode(stats), name: name, mime: "application/json", folder: folder, replacing: latest(files, prefix: "statistics_"))
            }
            if includeAudio && book.audio != nil { let position = TtuAudioProgress(title: book.title, playbackPosition: book.audioPosition, lastAudioBookModified: ms); try await client.upload(encoder.encode(position), name: "audioBook_1_6_\(ms)_\(book.audioPosition).json", mime: "application/json", folder: folder, replacing: latest(files, prefix: "audioBook_")) }
            store.message = "Pushed \(book.title) to ッツ"
        }
    }
    func pull() {
        guard let id = selectedRemote, let remote = remoteBooks.first(where: { $0.id == id }) else { return }
        store.run("Pulling book from ッツ…") {
            let client = GoogleDriveClient(auth: auth); let files = try await client.children(id)
            var book = store.state.books.first { TtuArchive.sanitizeTitle($0.title) == remote.name }
            if book == nil {
                guard let data = latest(files, prefix: "bookdata_") else { throw ReaderError.message("This remote book has no bookdata ZIP") }
                let zip = store.root.appendingPathComponent("ttu-\(UUID()).zip"); defer { try? FileManager.default.removeItem(at: zip) }
                try await client.download(data).write(to: zip)
                let root = store.root; book = try await Task.detached { try TtuArchive.importBook(zip, root: root) }.value
                store.state.books.append(book!); store.save()
            }
            guard let book else { return }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            if let progress = latest(files, prefix: "progress_") { let value = try decoder.decode(TtuProgress.self, from: await client.download(progress)); applyProgress(value, bookID: book.id) }
            if includeStatistics, let file = latest(files, prefix: "statistics_") {
                let incoming = try decoder.decode([TtuStatistic].self, from: await client.download(file))
                let merged = mergeStats(localStats(book), incoming)
                let oldDays = store.state.days.filter { $0.bookID == book.id }
                store.state.days.removeAll { $0.bookID == book.id }
                for s in merged { let old = oldDays.first { $0.date == s.dateKey }; store.state.days.append(ReadingDay(bookID: book.id, date: s.dateKey, seconds: max(0, s.readingTime), characters: max(0, s.charactersRead), lookups: old?.lookups ?? 0, cards: old?.cards ?? 0, modified: Date(timeIntervalSince1970: Double(s.lastStatisticModified) / 1000))) }
            }
            if includeAudio, let file = latest(files, prefix: "audioBook_") { let value = try decoder.decode(TtuAudioProgress.self, from: await client.download(file)); if let index = store.state.books.firstIndex(where: { $0.id == book.id }) { store.state.books[index].audioPosition = max(0, value.playbackPosition) } }
            store.save(); store.message = "Pulled \(book.title) from ッツ"
        }
    }
    func applyProgress(_ progress: TtuProgress, bookID: UUID) {
        guard let i = store.state.books.firstIndex(where: { $0.id == bookID }) else { return }
        let book = store.state.books[i]; let offset = min(max(0, progress.exploredCharCount), max(0, book.totalCharacters - 1))
        let index = book.chapters.lastIndex(where: { $0.start <= offset }) ?? 0
        store.state.books[i].chapter = index; store.state.books[i].offset = offset - book.chapters[index].start
    }
    func latest(_ files: [DriveFile], prefix: String) -> DriveFile? { files.filter { $0.name.hasPrefix(prefix) }.max { $0.name.compare($1.name, options: .numeric) == .orderedAscending } }
    func localStats(_ book: Book) -> [TtuStatistic] { store.state.days.filter { $0.bookID == book.id }.map { TtuStatistic(title: book.title, dateKey: $0.date, charactersRead: $0.characters, readingTime: $0.seconds, lastStatisticModified: Int($0.modified.timeIntervalSince1970 * 1000)) } }
    func mergeStats(_ local: [TtuStatistic], _ remote: [TtuStatistic]) -> [TtuStatistic] {
        var days: [String: TtuStatistic] = [:]
        for s in local + remote { if let old = days[s.dateKey], old.lastStatisticModified >= s.lastStatisticModified { continue }; days[s.dateKey] = s }; return days.values.sorted { $0.dateKey < $1.dateKey }
    }
}
