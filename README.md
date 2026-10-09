# Kanyomi beta

The app mark is the Japanese kanji **簡**. The display and internal project name is **Kanyomi**.

A local-first EPUB reader for the browser. Import books into this browser, or link an EPUB folder where the File System Access API is supported. Books and imported dictionaries are stored in IndexedDB; appearance and Anki settings are stored in localStorage.

## Native macOS beta

The native macOS 0.1.0-beta.7 adds compact Hoshi-inspired dictionary layouts with grouped sources, inline synonyms and name-type tags, alongside an English / 简体中文 / system interface selector in Settings → Appearance and continuous vertical scrolling through all dictionary matches with an explicit mining selection. Vocabulary supports manual word entry and visible per-word deletion, alongside reader lookup saving and TSV export. Saved words no longer retain or display per-word Anki status. Dictionary recommendations contain compatible Yomitan downloads.

A separate native SwiftUI/AppKit app now lives in [`macOS/`](macOS/README.md), with Hoshi-style offline Yomitan lookup, exact character scanning and persistent matched-text highlighting, EPUB reading, AnkiConnect, vocabulary, statistics, audiobook/SRT support, and ッツ exchange/sync. See the [feature comparison and beta limits](macOS/FEATURES.md). Build with `macOS/scripts/package-app.sh release`, or open the generated `macOS/dist/Kanyomi.app`.

Version history and validation are recorded in [CHANGELOG.md](CHANGELOG.md). GitHub Actions checks the browser build/tests and the native macOS tests/package.

## Start

Requires Node.js 24 or newer.

```sh
npm install
npm run dev
```

Open the local URL printed by Vite. For a production build, run `npm run build` and serve `dist/` over HTTP or HTTPS. Run `npm run lint` and `npm test` to check the source.

## Use

1. Import an `.epub` file. On browsers with folder access, **Open Folder** links all EPUBs in that folder and its subfolders without copying the files. Reopen a folder to refresh its contents.
2. Open a book and scroll to read. Your position is saved per book and restored next time. Use **Contents** to jump between chapters when the EPUB includes a table of contents.
3. Select text to look it up. With a mouse, you can also hover over a word and press Shift. English lookup uses an online dictionary, with a few built-in demo entries. Japanese lookup uses imported Yomitan term-bank dictionaries offline, with an online fallback.
4. To use Anki, run Anki with AnkiConnect installed, then configure the local endpoint, deck, note type, and field names in **Anki settings**. Test the connection before adding a card. No cloud API key is required; the AnkiConnect API key field is optional if your local setup uses one.

**Remove book** deletes an imported EPUB from this browser. **Unlink folder** removes that folder's books from the library without deleting disk files. Both actions ask for confirmation. Browser storage and folder permissions are specific to each browser profile and origin; clearing site data removes imported books, dictionaries, and positions.

## Beta limits

- Folder linking depends on the browser's File System Access API. Importing an EPUB is the fallback where that API is unavailable.
- Anki integration requires the desktop Anki app and AnkiConnect running on the same computer, with the reader's origin allowed by your local AnkiConnect configuration.
- English online lookup and Japanese online fallback require a network connection. Imported Japanese dictionaries work offline.
- Reading position uses the EPUB's CFI. If a book is replaced with a substantially different file, its old position may no longer resolve; the reader falls back to the beginning.
- Data stays in one browser profile. There is no account or cross-device sync in this beta.

The macOS beta 6 AnkiConnect path has also been tested live: dictionary-search note creation with localized front/back fields, correct definition content, duplicate prevention and persistence after Anki restart. Audio/media upload and Lapis were not covered by that live check.

Kanyomi uses its own storage and bundle identifiers. Existing libraries and browser settings migrate automatically; legacy identifiers are read only for upgrade compatibility. Google credentials fall back to the previous Keychain service on a user-initiated connection.

The 「簡」 logo uses the user-supplied 青柳衡山 calligraphy PNG across the native icon/sidebar and web brand/favicon. The original source pixels, transparency and proportions are preserved; rendered marks use burnt orange (#c77c5c) and center the visible ink using the new image’s ink bounds and visual center. No installed font is required.

The native app uses dark chrome with burnt-orange accents throughout navigation, controls, statistics and dictionary content. New reading preferences default to Night; the reader still supports Paper, White and Custom page themes. Web defaults to dark and uses the same orange accents in both selectable themes.
