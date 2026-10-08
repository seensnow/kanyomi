# Changelog

## Kanyomi naming completion — 2026-10-08

- Use Kanyomi for sample book/dictionary metadata, native data folder, bundle identifier, Google client setting and Keychain writes; use kanyomi for browser databases, preferences and folder-picker identity. Copy browser data atomically on first access and preserve the old database; move the default native library on first launch, preserve explicit data-directory overrides, and read old preferences/credentials for compatibility. Legacy identifiers remain only in upgrade and generated-package cleanup code.
- Confirmed main is unprotected. GitHub rejects branch-protection/ruleset access for this private repository with an upgrade-to-Pro-or-make-public message; visibility and account plan remain unchanged.
- Validation: web lint, six tests and production build pass; 23 native tests pass, including library migration and WebKit checks, after rerunning outside the process-restricted sandbox. Release packaging and strict signature verification pass. Existing web large-chunk warning remains. Live OAuth/credential migration and a complete existing-user upgrade have not been checked interactively.

## macOS 0.1.0-beta.7 — 2026-10-07

- Unify native and web styling around charcoal/black with burnt-orange accents, including the icon/logo, controls, dictionary examples/tags/pitch/mining selection, highlights and statistics. Native chrome is dark; sidebar navigation uses explicit buttons with a contrasting gray selected row to avoid system blue highlighting. New reading settings and the web default to dark. Keep selectable reading page themes and saved web theme choices. Validation: web lint/tests/build, native tests/release packaging, signature verification and packaged UI/icon review.

- Use the newly supplied 青柳衡山 running-script 「簡」 PNG, preserving the sage green rendering and recalculating scale/alignment from its visible ink. Keep the source PNG untouched. Use **Kanyomi** for all current display names, app bundle filename, titles and project documentation; retain the existing storage identifiers. Validation: web lint/tests/build, native tests/release packaging, signature and packaged UI/icon checks.

- Restore sage green (#4d6657) for the supplied calligraphy mark and center its visible ink by shifting it left in the native icon/sidebar and web brand/favicon. Keep the original PNG source unchanged. Validation: web lint/build, native release packaging/signature verification and visual icon/sidebar checks.

- Replace the font-based 「簡」 approximation with the user-supplied 趙孟頫 calligraphy PNG in the app icon, sidebar, web brand and favicon. Preserve the original PNG bytes and transparency, fit its proportions without stretching, and remove unused Yuji assets and attribution. Validation: matching source/asset SHA-256 hashes, web lint/build, native release packaging, signature verification and visual icon review.

- Replace the macOS app icon/sidebar mark and web brand/favicon with the requested Japanese kanji 「簡」. Use the supplied calligraphy image for the native icon and rebuild cached icons when their generator changes. Rename the display name to 「簡読み」 and internal Swift/npm targets to Kanyomi, including packaging, exports and CI artifacts. Keep legacy data directories, storage keys, bundle identifier and Keychain service so existing libraries and settings remain accessible. Add KANYOMI_DATA_DIR with the old environment variable as a fallback.
- Validation: web lint, three tests and production build pass (existing large-chunk warning); 22 native tests pass under the renamed module. The generated 512 px icon was visually checked. macOS release packaging and signature verification pass; packaged beta 7 retains the existing book, installed Jitendex/JMnedict dictionaries, Chinese interface selection and working 学 lookup.

## macOS 0.1.0-beta.6 — 2026-10-06

- Live AnkiConnect validation: the packaged app added a dictionary-search word to a dedicated test deck using localized Basic note fields. Verify term/reading, Jitendex definitions/examples/source, tags and rendered card HTML; duplicate retry is rejected with no extra note, and the note survives an Anki restart. Audio/media upload and book-context mining remain outside this live check.

- Adopt compact Hoshi-inspired dictionary typography: inline wrapping synonyms separated by `|`, smaller match/mining controls, quieter source headings and compact examples. Keep continuous vertical scrolling and ruby.
- Group each dictionary’s entries under one collapsible source heading with numbered rows. Display imported definition/term tags, including JMnedict name categories; preserve original glossary indices for mining.
- Validation: 22 native tests pass, including source grouping, tag escaping, compact synonym layout at 320 px in light/dark themes, and existing scroll/selection regression coverage. Release packaging and signature verification pass; packaged beta 6 was checked with installed Jitendex/JMnedict 学 entries, confirming inline synonyms and one source heading for all six name rows. Apple Silicon app remains ad-hoc signed, not notarized.

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
