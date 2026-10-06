# Hoshi feature comparison and beta verification

Reference: Hoshi Reader README plus reader, settings, sync and Sasayaki source inspected on 2026-10-04.

| Capability | macOS beta | Verification / limits |
| --- | --- | --- |
| EPUB library and shelves | Native library, copied EPUBs, covers, search, sort, named shelves, import/drop | EPUB 2 NCX + EPUB 3 navigation, nested contents and assets covered by tests |
| Vertical / horizontal, ruby | WebKit with native appearance controls | Native window verified with vertical Japanese, ruby and dictionary lookup |
| Book navigation | Contents, full-book search, keyboard paging, progress restore | EPUB count and persisted offsets tested |
| Bookmarks and highlights | Saved location, selected passages, editable notes; transient matched-word highlight | Lookup highlights span ruby/text nodes and retain visibility without selection focus; saved highlights cannot span arbitrary nested elements |
| Popup dictionary equivalent | Docked lookup inspector; click, selection and Shift hover; compact grouped dictionary sources, numbered entries, inline synonyms and name tags; all matches scroll vertically with explicit mining selection | Hoshi engine; glyph-rectangle scanning rejects whitespace/readings, matched surface text is highlighted, and Shift scans deduplicate per glyph |
| Deinflection | Same upstream Yomitan-based engine | Ichidan and godan conjugations tested |
| Yomitan terms / frequency / pitch / kanji | ZIP import, enable/disable, order, structured glossary and images | Upstream engine supports only a subset of the full pitch metadata specification |
| Dictionary search | Offline terms/readings/kanji | Search/media tested using fixture dictionary; installed Jitendex queries measured 1–5 ms, glossary document is reused; large commercial dictionary performance not benchmarked |
| Online and local word audio | Direct URL / Yomitan JSON + macOS speech | Network/provider availability varies; live providers not guaranteed |
| Anki mining | Desktop AnkiConnect, deck/model fields, duplicate handling, local vocab TSV | Mock API coverage plus live beta 6 add/duplicate/persistence checks in a dedicated test deck; live audio/media and Lapis remain unverified |
| Hoshi/Lapis markers | All core markers listed in Settings, glossary categories, pitch SVGs, media | Marker replacement tested; selected glossary picker and kana-boundary furigana segmentation; unusual readings may use a whole-expression fallback |
| Reading statistics | Daily time/characters/lookups/cards, goal, charts, per book | Foreground + 90-second inactivity pause; forward scroll heuristic, not exact pages read |
| Japanese–Chinese dictionaries | Import compatible Yomitan ZIPs; official Shogakukan product and Monokakido app links in Dictionary/Settings | Links are labeled as separate paid app content; publisher-backed Shogakukan content is available through Monokakido; a publisher-authorized importable ZIP has not been verified |
| Interface language | Follow system / English / 简体中文 in Settings → Appearance; persists across launches | Book and dictionary content retain their language; provider errors and some technical status messages remain untranslated |
| Themes/fonts/CSS | Paper/white/night/custom colors, system/imported fonts, custom CSS | Per-application reading appearance |
| ッツ sync | Bookdata ZIP, progress JSON; Google Drive push/pull, daily stats merge, cover, audio position | Local bookdata round trip tested; real OAuth/Drive integration unverified without credentials; no automatic background sync |
| Backup/restore | Full local ZIP plus recovery copy, validated restored paths | ZIP path checks tested; Keychain credentials separate |
| Sasayaki-style audiobooks | Audio + SRT, follow text, replay, rate, delay persistence, cue clip mining | SRT/UTF-16 matching tested; exact sequential normalized matching, no fuzzy sentence expansion |
| iOS sharing / AnkiMobile | Replaced with native file import and desktop AnkiConnect | Platform-specific iOS features intentionally translated for desktop |

This is an initial beta, not a claim of exact Hoshi parity. Remaining work: large-dictionary performance profiling; fuzzy audiobook matching; automatic sync with conflict handling; audio-source prioritization; cross-device live tests; notarized distributable releases.

Validation: 22 automated tests pass, including EPUB import, archive safety, dictionary deinflection/media, TTU round trip, mining markers, SRT matching and Anki API handling, including self-closing XHTML scripts and real WebKit SVG/image loading in both writing modes, plus narrow glossary rendering with inline ruby, colored tags/examples and pitch graphs in both themes. Glyph scanning, cross-ruby highlighting and glossary document reuse have WebKit regression coverage. Beta 6 additionally verifies source grouping with preserved mining indices and inline synonym layout at 320 px in both themes. Beta 5 also tests language fallback and eight matching entries in a narrow WebKit viewport, vertical overflow without horizontal overflow, and mining selection retaining scroll position and expanded-card state. Dictionary management layout and portrait covers were checked in beta 3; original-book matched highlighting and switching dictionary entries were checked in the packaged beta 4 app. Packaged beta 5 was checked in Simplified Chinese with the existing Jitendex が lookup and all eight matches in one scroll area. Packaged beta 6 was checked with installed Jitendex/JMnedict 学 entries, confirming inline synonyms and six tagged name rows under one heading. The packaged Apple Silicon app has an ad-hoc signature; it is not notarized.

Live Anki validation (beta 6): the packaged app adds a dictionary-search word through AnkiConnect v6 using localized Basic fields. Term/reading, definitions, example, source, tags and generated card HTML were verified; duplicate addition is rejected without a second note, and persistence was checked after Anki restart. Live audio/media upload, Lapis and book-context mining are not covered by this check.

Brand mark: Japanese kanji 「簡」 in the macOS icon/sidebar and web brand/favicon. Native icon generation was visually checked at 512 px; packaged beta 7 retains the existing library, dictionaries and Chinese interface settings, and 学 lookup works; the display name is 「簡読み」 and internal project name is Kanyomi.

Compatibility: legacy SimpleReader data folders, storage keys, bundle identifier and Keychain identifiers are retained to preserve existing libraries and settings. The GitHub repository URL remains unchanged.

The 「簡」 logo uses the user-supplied 趙孟頫 calligraphy PNG across the native icon/sidebar and web brand/favicon. The original source pixels, transparency and proportions are preserved; rendered marks use sage green (#4d6657) and shift left to center the visible ink. No installed font is required.
