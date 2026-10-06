# 簡読み (Kanyomi) for macOS — 0.1.0 beta 7

An independent native Japanese EPUB reader inspired by Hoshi Reader. SwiftUI and AppKit provide the desktop UI; Apple's WebKit renders EPUB chapters, including vertical writing and ruby. Offline Yomitan lookup uses the GPL Hoshi dictionary engine. The existing React web project is left intact.

## Beta fixes

- The app icon and sidebar now use the Japanese kanji 「簡」, on a cream background with a green glyph. The display name is 「簡読み」 and internal project name is Kanyomi.

- Beta 6 uses compact Hoshi-inspired glossary layouts: one collapsible heading per dictionary, numbered entries, synonyms separated by `|`, dictionary-provided name/word tags, smaller mining controls and less prominent examples. All matches still scroll continuously; original glossary indices remain available for mining.

- Beta 5 adds Settings → Appearance → Interface language (Follow system, English, 简体中文). The choice persists across launches; imported book and dictionary text keep their source language. Provider errors and some technical status messages retain their original language.
- All lookup matches now appear in one vertical scrolling document. Choose “Use for mining” on a result, or select definition text within it, to target that word for audio, saving and Anki. Selecting a result keeps the scroll position and expanded cards.

- Beta 3 brings colored dictionary source cards, part-of-speech tags, inline ruby examples and pitch graphs when available. Listen plays the configured audio source with Japanese speech fallback; Japanese voice reads aloud directly.

- Dictionary management stays within the window and scrolls when needed; headers, download links and import controls stay visible.
- Packaging retains only `dist/簡読み.app`, with a visible beta 7 version label. Distribution staging uses a temporary folder that is removed after creating the ZIP.

- Library covers use a portrait ratio and fill the card without padding or leftover background.
- Self-closing EPUB XHTML scripts are stripped before HTML rendering so they cannot swallow illustration pages. Image-only SVG/image pages fit the viewport in either writing mode.
- Dictionary and Settings include ZIP download links for Jitendex (definitions), JMnedict (names), and KANJIDIC (kanji), plus their source pages. Download a ZIP and import it without unzipping.

## Japanese–Chinese dictionaries

The machine-translated Jitendex Chinese download recommendation has been removed. The [publisher-backed Shogakukan Japanese–Chinese dictionary, third edition](https://www.monokakido.jp/ja/dictionaries/cj3/index.html) is available as paid content in [Dictionaries by Monokakido](https://www.monokakido.jp/ja/dictionaries/app/), including on macOS. Both official pages are linked under “Official Japanese–Chinese dictionaries” in Dictionary and Settings. Its official distribution uses that app; no publisher-authorized Yomitan ZIP compatible with Kanyomi has been verified. Buying its app content does not make it importable here.

## Open the beta

Run `dist/簡読み.app` after packaging, or unzip `dist/Kanyomi-macOS-beta.zip`. Requires macOS 14+, built for the architecture of the build machine (this build: Apple Silicon). This development build is ad-hoc signed, without Apple notarization.

1. Import EPUBs with **⌘O**, drag and drop, or the Import button. The sample button imports the included original Japanese book and tiny test dictionary.
2. Import your Yomitan `.zip` dictionaries with **⇧⌘O**. Term, frequency, pitch, and kanji dictionaries can share a ZIP. Enable, disable, reorder, and assign definition categories in Dictionary or Settings. A tiny sample dictionary is available in `Sources/Kanyomi/Resources/SampleDictionary.zip` for testing; it is not a comprehensive Japanese dictionary.
3. Click text or hold Shift while hovering to look up a word. Select text to look up a phrase. Use the dictionary panel for definitions, pronunciation, local vocabulary saving, highlighting, and Anki mining.
4. Settings contains vertical/horizontal writing, themes, typography, custom CSS, imported fonts, audio sources, and Anki templates.
5. Open Contents for chapter navigation, full-book search, bookmarks/highlights and audiobook import/SRT matching. Arrow keys/Space page through the current chapter; ⌘[ / ⌘] change chapters; ⌘D saves a bookmark.

Data lives at `~/Library/Application Support/SimpleReaderMac`. Imports copy originals; deleting a library copy does not delete the source EPUB. Backup/restore includes imported EPUBs, dictionaries, vocabulary, bookmarks, statistics, fonts and settings. Google OAuth tokens and the OAuth client secret are held separately in Keychain. `KANYOMI_DATA_DIR` can isolate a test library; `SIMPLEREADER_DATA_DIR` remains supported for compatibility.

## Anki

Run Anki with AnkiConnect. Set the endpoint (default `http://127.0.0.1:8765`), deck, model and actual field names in Settings → Anki. Connect/refresh lists decks, models and fields. Each field accepts HTML and Hoshi's single-brace markers. The Lapis preset requires the matching note type installed in Anki. Audio, book covers and active audiobook cue audio are uploaded with `storeMediaFile`. Duplicate errors are shown and do not mark a note as successfully added. Local vocabulary can be exported as TSV.

## Audio

The speaker uses the configured direct audio or Yomitan JSON source. `{term}` / `{expression}` and `{reading}` are URL encoded. Local HTTP audio sources (including AnkiConnect Android sources) are supported. The waveform button uses the macOS Japanese speech voice. Audiobooks support local audio import, sequential exact matching of normalized SRT cues, playback position/rate persistence, follow-along navigation and replay. Matching reports the number of matched cues; unmatched cues still play. This beta does not yet reproduce Hoshi's fuzzy matching and sentence expansion for audio clips.

## ッツ and Google Drive

Local bookdata ZIP and progress JSON exchange works without an account. Google sync uses the `ttu-reader-data` folder and Hoshi/ッツ v1_6 bookdata, progress, statistics, cover and audioBook formats. Explicit push/pull directions prevent ambiguous overwrite decisions. Newer daily statistics win when merging. Audiobook files themselves are local; sync transfers the playback position.

Create a **Desktop app** OAuth client in the **same Google Cloud project** used by your ッツ web client. Enable Drive API, configure `drive.file`, and supply the desktop client ID/secret in Sync & Backup. Login opens the system browser with PKCE and a loopback redirect. Disable ッツ password encryption. Sync Browser DB to GDrive in ッツ before pulling; switch back to Browser DB to read. Google live sync requires your credentials and has not been verified against a real account in this build. See [Hoshi's setup guide](https://github.com/Manhhao/Hoshi-Reader/blob/main/TTUSYNC.md) and [Google's installed-app OAuth guide](https://developers.google.com/identity/protocols/oauth2/native-app).

## Build and test

No full Xcode installation or network downloads are needed; all dependency source is vendored.

```sh
./scripts/swift-build.sh test
./scripts/package-app.sh release
open dist/簡読み.app
```

The build script uses writable local caches and an isolated copy of the SwiftPM manifest interface. This also works around an installed Command Line Tools mismatch (old private Swift 5 interface with the newer Swift 6 library) and explicitly points C++ at the SDK's libc++ headers. It does not alter the system tools.

See `FEATURES.md` for scope, verification and remaining differences. Source and third-party licenses are included with the beta package. Hoshi Reader is not affiliated with this application.

Live beta 6 Anki check: adding a dictionary-search word through the app succeeded with the localized Basic note type and correctly mapped front/back fields. Definition content, duplicate prevention and persistence after Anki restart were verified. Select an existing deck, note type and exact field names in Settings → Anki; English defaults may differ from localized Anki names. Audio/media and book-context mining were not included in this live check.

Compatibility: legacy SimpleReader data folders, storage keys, bundle identifier and Keychain identifiers are retained to preserve existing libraries and settings. The GitHub repository URL remains unchanged.

The 「簡」 logo uses the user-supplied 趙孟頫 calligraphy PNG across the native icon/sidebar and web brand/favicon. Its original pixels, transparency and proportions are preserved; no installed font is required.
