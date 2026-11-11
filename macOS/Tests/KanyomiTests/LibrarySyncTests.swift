import Foundation
import Testing
@testable import Kanyomi

struct LibrarySyncTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KANYOMI_SYNC_TEST_URL"] != nil))
    func webKitRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try #require(environment["KANYOMI_SYNC_TEST_URL"].flatMap(LibrarySyncClient.endpoint))
        let key = try #require(environment["KANYOMI_SYNC_TEST_KEY"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let sample = try #require(Bundle.readerResources.url(forResource: "Sample", withExtension: "epub", subdirectory: "Resources"))
        let client = LibrarySyncClient(base: url, key: key)
        let id = try LibrarySyncClient.bookID(sample)
        let book = try EPUBImporter.load(sample, root: root)
        let store = ReaderStore(root: root, startTimer: false)
        store.state.books = [book]
        store.openBook(book.id)
        store.navigate(chapter: 1, offset: 12)
        store.closeBook()
        try await store.reconcileLibrary(client)

        let deadline = Date().addingTimeInterval(65)
        while Date() < deadline {
            let records = try await client.shelf()
            if records.first(where: { $0.id == id })?.position?.path == book.chapters[0].path,
               records.contains(where: { $0.id != id && $0.isOnShelf }) {
                let restarted = ReaderStore(root: root, startTimer: false)
                try await restarted.reconcileLibrary(client)
                let synced = try #require(restarted.state.books.first(where: { $0.id == book.id }))
                #expect(synced.chapter == 0)
                #expect(synced.offset == 0)
                #expect(restarted.filteredBooks.contains(where: { $0.title == "iPhone Sync Fixture" }))
                return
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        Issue.record("The web client did not reconnect and publish its offline EPUB and reading position")
    }
}
