import SwiftUI
import AppKit

@main
struct SimpleReaderApp: App {
    @StateObject private var store = ReaderStore()
    @AppStorage("interfaceLanguage") private var language = "system"
    var body: some Scene {
        WindowGroup {
            MainView().id(language).environmentObject(store).environment(\.locale, AppLanguage.locale(language)).frame(minWidth: 980, minHeight: 660)
                .onOpenURL { store.importBooks([$0]) }
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Import Books…")) { store.pickBooks() }.keyboardShortcut("o")
                Button(L("Import Dictionary…")) { store.pickDictionary() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu(L("Reading")) {
                Button(L("Previous Chapter")) { store.moveChapter(-1) }.keyboardShortcut("[", modifiers: .command)
                Button(L("Next Chapter")) { store.moveChapter(1) }.keyboardShortcut("]", modifiers: .command)
                Button(L("Add Bookmark")) { store.addBookmark() }.keyboardShortcut("d")
                Button(L("Pause / Resume Statistics")) { store.isTiming.toggle() }.keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
        Settings { PreferencesView().environmentObject(store).environment(\.locale, AppLanguage.locale(language)).frame(width: 740, height: 630) }
    }
}
