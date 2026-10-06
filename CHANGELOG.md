# Changelog

## macOS 0.1.0-beta.5 — 2026-10-06

- Add a persistent Follow system / English / 简体中文 interface selector in Settings → Appearance, with Chinese labels across library, reader, dictionary, settings, vocabulary, statistics and sync screens. Source book/dictionary content and provider errors retain their original language; some technical status messages remain English.
- Remove the machine-translated Japanese–Chinese dictionary download recommendation and its unused Chinese label. Document the publisher-backed Shogakukan / Monokakido option and that no publisher-authorized Yomitan ZIP has been verified. Removal validation: release packaging rebuild and signature verification; dictionary importer and lookup behavior are unchanged.
- Add the Shogakukan Japanese–Chinese official product page and Monokakido application download page to Dictionary and Settings, labeled as external paid dictionary content rather than importable ZIPs. Keep Settings dictionary management vertically scrollable with the longer link list. Validation: release package builds, signature verification and native UI checks.
- Replace left/right match paging with one continuous vertical WebKit document containing every lookup match. “Use for mining” and selecting definition text choose the corresponding result for saving, pronunciation, original-book highlighting and Anki; selection preserves scroll position and expanded cards.
- Validation: 21 native tests pass, including eight-match narrow-viewport vertical scrolling, retained scroll/card state on mining selection, language fallback, and existing EPUB/highlighting/glossary tests. Apple Silicon release app builds and is ad-hoc signed; not notarized. Packaged beta 5 was checked with the existing Jitendex が lookup: eight result sections scroll through one document, and Chinese interface labels are visible after relaunch.

## macOS 0.1.0-beta.4 — 2026-10-04

- Hide the dictionary lookup loading spinner; lookups continue without the circular indicator.

- Highlight the dictionary's matched surface text in the original EPUB, across text spans and ruby, retaining the highlight when focus moves to the dictionary. Update it when switching matches and clear it on nonmatches or manual dictionary searches.
- Use actual grapheme rectangles for pointer scanning in horizontal and vertical text. Both halves of a glyph resolve to that glyph; whitespace and ruby readings do not scan a neighboring word.
- Replace the 180 ms Shift-hover debounce with one scan per animation frame, deduplicating scans within a character. Reuse the glossary document and replace its content instead of navigating on every lookup.
- Validation: 19 native tests pass, including WebKit glyph hit tests, cross-ruby highlights, repeated hover and glossary document reuse. Local installed Jitendex queries measured 1–5 ms; full end-to-end parity with Hoshi is not claimed.

## macOS 0.1.0-beta.3 — 2026-10-04

- Present dictionary entries as collapsible source cards with colored part-of-speech tags, example sentences, highlighted keywords and pitch graphs when pitch data is installed. Frequency dictionaries appear as compact badges.
- Keep ruby and nested structured-content fragments inline instead of inserting breaks between every fragment. Match Yomitan/Hoshi `data-sc-*` selectors, including CJK data keys, so dictionary-provided styles work.
- Add a labeled Listen button and Japanese voice action; validate source audio before playback and fall back to macOS Japanese speech when loading or decoding fails.
- Support both dark and light dictionary themes and narrow reader panels.
- Validation: 17 native tests pass, including narrow WebKit glossary rendering, ruby, tags, example sections and pitch graphs in both themes. Source audio remains dependent on the configured provider and network; speech requires an installed Japanese voice.

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
