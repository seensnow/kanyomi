import SwiftUI
import AppKit

@main
struct SimpleReaderApp: App {
    @StateObject private var store = ReaderStore()
    var body: some Scene {
        WindowGroup {
            MainView().environmentObject(store).frame(minWidth: 980, minHeight: 660)
                .onOpenURL { store.importBooks([$0]) }
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Books…") { store.pickBooks() }.keyboardShortcut("o")
                Button("Import Dictionary…") { store.pickDictionary() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Reading") {
                Button("Previous Chapter") { store.moveChapter(-1) }.keyboardShortcut("[", modifiers: .command)
                Button("Next Chapter") { store.moveChapter(1) }.keyboardShortcut("]", modifiers: .command)
                Button("Add Bookmark") { store.addBookmark() }.keyboardShortcut("d")
                Button("Pause / Resume Statistics") { store.isTiming.toggle() }.keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
        Settings { PreferencesView().environmentObject(store).frame(width: 740, height: 630) }
    }
}
