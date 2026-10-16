import Foundation
import Testing
@testable import Kanyomi

struct ProductMigrationTests {
    @Test func libraryMovesWithoutLosingFilesAndPreservesExistingDestination() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let old = base.appendingPathComponent("legacy"), new = base.appendingPathComponent("KanyomiMac")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let data = Data("saved library".utf8)
        try data.write(to: old.appendingPathComponent("library.json"))
        try ProductMigration.moveLibrary(from: old, to: new)
        #expect(try Data(contentsOf: new.appendingPathComponent("library.json")) == data)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("another library".utf8).write(to: old.appendingPathComponent("library.json"))
        try ProductMigration.moveLibrary(from: old, to: new)
        #expect(try Data(contentsOf: new.appendingPathComponent("library.json")) == data)
        #expect(FileManager.default.fileExists(atPath: old.path))
    }
}
