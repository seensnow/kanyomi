# Changelog

## macOS 0.1.0-beta.2 — 2026-10-04

### Added

- Native SwiftUI/AppKit EPUB library, shelves, search, bookmarks and highlights.
- WebKit reading with vertical/horizontal text, ruby, themes, fonts and custom CSS.
- Offline Yomitan dictionaries with deinflection, frequency, pitch, kanji and glossary media.
- AnkiConnect mining, local vocabulary, reading statistics and audiobook/SRT support.
- Local backup/restore, TTU bookdata/progress exchange and optional Google Drive sync.
- Jitendex, JMnedict and KANJIDIC ZIP download links in Dictionary and Settings.

### Fixed

- Portrait library covers fill their cards without leftover background or padding.
- Self-closing XHTML scripts no longer consume illustration pages during HTML parsing.
- Image-only SVG/image pages fit the viewport in both reading orientations.
- Dictionary management scrolls within the window, keeping titles, import buttons,
  download links and navigation visible.
- Packaging leaves one app in `macOS/dist`; temporary distribution copies are removed.
  The app displays a beta 2 version label to distinguish it from older builds.

### Validation and limits

- 15 native tests pass, including real WebKit SVG resource loading in both orientations.
- Packaged Apple Silicon app builds and is ad-hoc signed. Not notarized.
- Dictionary layout and covers were checked in the running packaged app.
- Live Google Drive OAuth/sync, real Anki collections and large commercial dictionaries
  have not been verified. See `macOS/FEATURES.md` for detailed limits.

## Browser 0.1.0-beta.1 — 2026-10-04

### Added

- Local EPUB import, linked folders, IndexedDB book storage and restored reading positions.
- EPUB contents navigation, themes and reading preferences.
- Japanese Yomitan term-bank lookup and English online lookup.
- Configurable desktop AnkiConnect mining with escaped note fields and error reporting.

### Validation

- Production build and ESLint checks pass.
- Three AnkiConnect protocol tests pass.
