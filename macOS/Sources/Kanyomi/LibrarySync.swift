import Foundation
import CryptoKit

struct LibrarySyncPosition: Codable, Hashable {
    let path: String
    let offset: Int
    let updatedAt: Int64
    var cfi: String? = nil
}

struct LibrarySyncRecord: Codable {
    let id: String
    let title: String
    let addedAt: Int64
    var removedAt: Int64? = nil
    var position: LibrarySyncPosition? = nil
    var isOnShelf: Bool { addedAt > (removedAt ?? 0) }
}

func syncTimestamp(_ date: Date = Date()) -> Int64 { Int64(date.timeIntervalSince1970 * 1_000) }

struct LibrarySyncClient {
    let base: URL
    let key: String

    static func endpoint(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host(), url.user() == nil, url.password() == nil,
              url.query() == nil, url.fragment() == nil, url.path.isEmpty || url.path == "/" else { return nil }
        if url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) { return url }
        return nil
    }

    static func bookID(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func request(_ id: String? = nil, state: Bool = false, method: String = "GET") -> URLRequest {
        var url = base.appendingPathComponent("api/sync/books")
        if let id { url.appendPathComponent(id) }
        if state { url.appendPathComponent("state") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ReaderError.message("Sync server unavailable.") }
        switch http.statusCode {
        case 200...299: return
        case 401: throw ReaderError.message("Sync key rejected. Check the key for this server.")
        case 413: throw ReaderError.message("This EPUB exceeds the sync limit of 128 MiB.")
        default: throw ReaderError.message("Sync server returned HTTP \(http.statusCode).")
        }
    }

    func shelf() async throws -> [LibrarySyncRecord] {
        let (data, response) = try await URLSession.shared.data(for: request())
        try check(response)
        return try JSONDecoder().decode([LibrarySyncRecord].self, from: data)
    }

    func upload(_ file: URL, id: String) async throws {
        var request = request(id, method: "PUT")
        request.setValue("application/epub+zip", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        try check(response)
    }

    func publish(_ record: LibrarySyncRecord) async throws -> LibrarySyncRecord {
        var request = request(record.id, state: true, method: "PUT")
        request.httpBody = try JSONEncoder().encode(record)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return try JSONDecoder().decode(LibrarySyncRecord.self, from: data)
    }

    func download(_ record: LibrarySyncRecord, root: URL) async throws -> Book {
        guard record.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw ReaderError.message("Invalid synced book identifier.")
        }
        let (file, response) = try await URLSession.shared.download(for: request(record.id))
        try check(response)
        return try await Task.detached {
            defer { try? FileManager.default.removeItem(at: file) }
            guard try Self.bookID(file) == record.id else { throw ReaderError.message("Downloaded EPUB checksum mismatch.") }
            var book = try EPUBImporter.load(file, root: root)
            book.title = record.title
            book.syncID = record.id
            book.syncAddedAt = record.addedAt
            return book
        }.value
    }
}

extension ReaderStore {
    func connectLibrarySync(server: String, key: String) {
        guard let url = LibrarySyncClient.endpoint(server), key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            librarySyncStatus = "Enter an HTTPS server address and its 64-character sync key."
            return
        }
        run("Connecting library sync…") { [self] in
            let client = LibrarySyncClient(base: url, key: key)
            _ = try await client.shelf()
            try Keychain.set(syncCredential(url.absoluteString), data: Data(key.utf8))
            state.syncServer = url.absoluteString
            librarySyncStatus = "Connected. Syncing library…"
            save()
            startLibrarySync()
        }
    }

    func disconnectLibrarySync() {
        if let server = state.syncServer { Keychain.remove(syncCredential(server)) }
        librarySyncTask?.cancel()
        state.syncServer = nil
        librarySyncStatus = ""
        save()
    }

    private func syncCredential(_ server: String) -> String { "LibrarySync:\(server)" }

    func startLibrarySync() {
        guard librarySyncTask == nil, let server = state.syncServer, let url = LibrarySyncClient.endpoint(server) else { return }
        nextLibrarySync = Date().addingTimeInterval(10)
        guard let data = Keychain.get(syncCredential(server)), let key = String(data: data, encoding: .utf8) else {
            librarySyncStatus = "Reconnect library sync to save its key on this Mac."
            return
        }
        let client = LibrarySyncClient(base: url, key: key)
        librarySyncTask = Task {
            defer { librarySyncTask = nil }
            do {
                try await reconcileLibrary(client)
                try Task.checkCancellation()
                librarySyncStatus = "Library synced"
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { librarySyncStatus = "Changes saved on this Mac. Sync will retry. \(error.localizedDescription)" }
            }
        }
    }

    func scheduleLibrarySync() {
        nextLibrarySync = min(nextLibrarySync, Date().addingTimeInterval(1))
    }

    func markLibraryPosition(_ book: inout Book) {
        book.syncPosition = LibrarySyncPosition(path: book.chapters[book.chapter].path, offset: book.offset, updatedAt: syncTimestamp())
        scheduleLibrarySync()
    }

    func libraryRemoval(for uuid: UUID) throws -> LibrarySyncRecord? {
        guard state.syncServer != nil, let book = state.books.first(where: { $0.id == uuid }) else { return nil }
        let file = originalEPUB(uuid)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let id = try book.syncID ?? LibrarySyncClient.bookID(file)
        return LibrarySyncRecord(id: id, title: book.title, addedAt: book.syncAddedAt ?? 1, removedAt: syncTimestamp())
    }

    func reconcileLibrary(_ client: LibrarySyncClient) async throws {
        let remote = try await client.shelf()
        try Task.checkCancellation()
        var records = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for removal in state.syncRemovals ?? [] {
            records[removal.id] = try await client.publish(removal)
            try Task.checkCancellation()
            state.syncRemovals?.removeAll { $0.id == removal.id && $0.removedAt == removal.removedAt }
            save()
        }

        var localIDs = Set<String>()
        let root = root
        var firstError: Error?
        for uuid in state.books.map(\.id) {
            do {
                try Task.checkCancellation()
                guard let snapshot = state.books.first(where: { $0.id == uuid }) else { continue }
                let file = originalEPUB(uuid)
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 128 * 1024 * 1024 else { continue }
                let id: String
                if let existing = snapshot.syncID { id = existing }
                else { id = try await Task.detached { try LibrarySyncClient.bookID(file) }.value }
                try Task.checkCancellation()
                guard let index = state.books.firstIndex(where: { $0.id == uuid }) else { continue }
                if state.books[index].syncID == nil {
                    state.books[index].syncID = id
                    save()
                }
                localIDs.insert(id)
                let book = state.books[index]
                let addedAt = book.syncAddedAt ?? 1
                var record = records[id]
                let position = book.syncPosition ?? (record?.position == nil ? legacySyncPosition(book) : nil)
                if record == nil { try await client.upload(file, id: id) }
                let newerPosition = (position?.updatedAt ?? 0) > (record?.position?.updatedAt ?? 0)
                if record.map({ $0.isOnShelf ? newerPosition : addedAt > ($0.removedAt ?? 0) }) ?? true {
                    record = try await client.publish(LibrarySyncRecord(id: id, title: book.title, addedAt: addedAt, position: position))
                    records[id] = record
                }
                try Task.checkCancellation()
                if let record, let index = state.books.firstIndex(where: { $0.id == uuid }), selectedBookID != uuid {
                    applyLibraryRecord(record, index: index)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { firstError = firstError ?? error }
        }

        for record in records.values where record.isOnShelf && !localIDs.contains(record.id) {
            do {
                try Task.checkCancellation()
                let book = try await client.download(record, root: root)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: originalEPUB(book.id).deletingLastPathComponent())
                    throw CancellationError()
                }
                state.books.append(book)
                applyLibraryRecord(record, index: state.books.count - 1)
                save()
            } catch is CancellationError { throw CancellationError() }
            catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    private func originalEPUB(_ id: UUID) -> URL { root.appendingPathComponent("Books/\(id)/Original.epub") }

    private func legacySyncPosition(_ book: Book) -> LibrarySyncPosition? {
        guard book.lastOpened.timeIntervalSince1970 > 0, book.chapters.indices.contains(book.chapter) else { return nil }
        return LibrarySyncPosition(path: book.chapters[book.chapter].path, offset: book.offset, updatedAt: syncTimestamp(book.lastOpened))
    }

    private func applyLibraryRecord(_ record: LibrarySyncRecord, index: Int) {
        var book = state.books[index]
        let hidden = !record.isOnShelf
        var changed = (book.syncHidden ?? false) != hidden
        if changed { book.syncHidden = hidden }
        if let position = record.position, !hidden,
           position.updatedAt > (book.syncPosition?.updatedAt ?? 0),
           let chapter = book.chapters.firstIndex(where: { $0.path == position.path }) {
            book.chapter = chapter
            book.offset = min(position.offset, max(0, book.chapters[chapter].count - 1))
            book.syncPosition = position
            changed = true
        }
        if changed { state.books[index] = book; save() }
    }
}
