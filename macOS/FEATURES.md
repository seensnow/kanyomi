# Hoshi feature comparison and beta verification

Reference: Hoshi Reader README plus reader, settings, sync and Sasayaki source inspected on 2026-10-04.

| Capability | macOS beta | Verification / limits |
| --- | --- | --- |
| EPUB library and shelves | Native library, copied EPUBs, covers, search, sort, named shelves, import/drop | EPUB 2 NCX + EPUB 3 navigation, nested contents and assets covered by tests |
| Vertical / horizontal, ruby | WebKit with native appearance controls | Native window verified with vertical Japanese, ruby and dictionary lookup |
| Book navigation | Contents, full-book search, keyboard paging, progress restore | EPUB count and persisted offsets tested |
| Bookmarks and highlights | Saved location, selected passages, editable notes | Local persistence; one text-node highlight ranges in this beta |
| Popup dictionary equivalent | Docked lookup inspector; click, selection and Shift hover | Hoshi engine; a docked inspector fits mouse/keyboard reading |
| Deinflection | Same upstream Yomitan-based engine | Ichidan and godan conjugations tested |
| Yomitan terms / frequency / pitch / kanji | ZIP import, enable/disable, order, structured glossary and images | Upstream engine supports only a subset of the full pitch metadata specification |
| Dictionary search | Offline terms/readings/kanji | Search and media tested using fixture dictionary; large commercial dictionary performance not benchmarked |
| Online and local word audio | Direct URL / Yomitan JSON + macOS speech | Network/provider availability varies; live providers not guaranteed |
| Anki mining | Desktop AnkiConnect, deck/model fields, duplicate handling, local vocab TSV | Mock API protocol tested; real user's Anki collection not modified during testing |
| Hoshi/Lapis markers | All core markers listed in Settings, glossary categories, pitch SVGs, media | Marker replacement tested; selected glossary picker and kana-boundary furigana segmentation; unusual readings may use a whole-expression fallback |
| Reading statistics | Daily time/characters/lookups/cards, goal, charts, per book | Foreground + 90-second inactivity pause; forward scroll heuristic, not exact pages read |
| Themes/fonts/CSS | Paper/white/night/custom colors, system/imported fonts, custom CSS | Per-application reading appearance |
| ッツ sync | Bookdata ZIP, progress JSON; Google Drive push/pull, daily stats merge, cover, audio position | Local bookdata round trip tested; real OAuth/Drive integration unverified without credentials; no automatic background sync |
| Backup/restore | Full local ZIP plus recovery copy, validated restored paths | ZIP path checks tested; Keychain credentials separate |
| Sasayaki-style audiobooks | Audio + SRT, follow text, replay, rate, delay persistence, cue clip mining | SRT/UTF-16 matching tested; exact sequential normalized matching, no fuzzy sentence expansion |
| iOS sharing / AnkiMobile | Replaced with native file import and desktop AnkiConnect | Platform-specific iOS features intentionally translated for desktop |

This is an initial beta, not a claim of exact Hoshi parity. Remaining work: large-dictionary performance profiling; fuzzy audiobook matching; automatic sync with conflict handling; audio-source prioritization; cross-device live tests; notarized distributable releases.

Validation: 15 automated tests pass, including EPUB import, archive safety, dictionary deinflection/media, TTU round trip, mining markers, SRT matching and Anki API handling, including self-closing XHTML scripts and real WebKit SVG/image loading in both writing modes. Dictionary management layout and portrait covers were checked in the packaged beta 2 app. The packaged Apple Silicon app has an ad-hoc signature; it is not notarized.
