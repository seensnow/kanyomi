import { useCallback, useEffect, useRef, useState } from 'react'
import type { ChangeEvent } from 'react'
import ePub from '@likecoin/epub-ts'
import type { Contents, NavItem, Rendition } from '@likecoin/epub-ts'
import type { ReadingProgress } from './bookStorage'
import {
  addWordToAnki,
  defaultAnkiSettings,
  testAnkiConnection,
} from './ankiConnect'
import type { AnkiSettings } from './ankiConnect'
import {
  getImportedDictionaries,
  importYomitanDictionary,
  lookupWord,
} from './dictionary'
import type { DictionaryResult, DictionarySummary } from './dictionary'

type EpubReaderProps = {
  title: string
  file: Blob
  progress?: ReadingProgress
  onProgress: (progress: ReadingProgress) => void
  onClose: () => void
  theme: 'light' | 'dark'
}

type Selection = {
  word: string
  sentence: string
  offset?: number
}

function storedValue<T>(key: string, fallback: T): T {
  try {
    const value = localStorage.getItem(key)
    return value ? { ...fallback, ...JSON.parse(value) } : fallback
  } catch {
    return fallback
  }
}

function EpubReader(props: EpubReaderProps) {
  const viewerRef = useRef<HTMLDivElement>(null)
  const dictionaryInputRef = useRef<HTMLInputElement>(null)
  const renditionRef = useRef<Rendition | null>(null)
  const wiredContentsRef = useRef(new WeakSet<Contents>())
  const onProgressRef = useRef(props.onProgress)
  const initialProgressRef = useRef(props.progress)
  const pendingProgressRef = useRef<ReadingProgress | null>(null)
  const progressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lookupRequestRef = useRef(0)
  const [error, setError] = useState('')
  const [isOpening, setIsOpening] = useState(true)
  const [chapters, setChapters] = useState<NavItem[]>([])
  const [currentSection, setCurrentSection] = useState<number | null>(null)
  const [sectionTotal, setSectionTotal] = useState(0)
  const [selection, setSelection] = useState<Selection | null>(null)
  const [dictionaryResult, setDictionaryResult] = useState<DictionaryResult | null>(null)
  const [lookupStatus, setLookupStatus] = useState('')
  const [ankiStatus, setAnkiStatus] = useState('')
  const [dictionaryStatus, setDictionaryStatus] = useState('')
  const [dictionaries, setDictionaries] = useState<DictionarySummary[]>([])
  const [showReaderSettings, setShowReaderSettings] = useState(false)
  const [showAnkiSettings, setShowAnkiSettings] = useState(false)
  const [fontSize, setFontSize] = useState(() => {
    try {
      const savedFontSize = localStorage.getItem('simple-reader-font-size')
      if (savedFontSize) {
        const parsedSize = Number(savedFontSize)
        if (Number.isFinite(parsedSize)) return Math.min(36, Math.max(12, parsedSize))
      }
      const legacy = localStorage.getItem('simple-reader-appearance')
      const savedSize = legacy ? Number(JSON.parse(legacy).fontSize) : 18
      return Number.isFinite(savedSize) ? Math.min(36, Math.max(12, savedSize)) : 18
    } catch {
      return 18
    }
  })
  const appearanceRef = useRef({ theme: props.theme, fontSize })
  const hoveredWordRef = useRef<{ key: string; query: string; sentence: string; offset?: number; displayWord: string } | null>(null)
  const lastShiftLookupRef = useRef('')
  const [ankiSettings, setAnkiSettings] = useState<AnkiSettings>(() => storedValue(
    'simple-reader-anki-settings', defaultAnkiSettings,
  ))

  useEffect(() => {
    onProgressRef.current = props.onProgress
  }, [props.onProgress])

  function flushProgress() {
    if (progressTimerRef.current) clearTimeout(progressTimerRef.current)
    progressTimerRef.current = null
    if (pendingProgressRef.current) {
      onProgressRef.current(pendingProgressRef.current)
      pendingProgressRef.current = null
    }
  }

  function saveAnkiSettings(nextSettings: AnkiSettings) {
    setAnkiSettings(nextSettings)
    localStorage.setItem('simple-reader-anki-settings', JSON.stringify(nextSettings))
  }

  function saveFontSize(nextFontSize: number) {
    const size = Math.min(36, Math.max(12, nextFontSize))
    setFontSize(size)
    appearanceRef.current = { ...appearanceRef.current, fontSize: size }
    localStorage.setItem('simple-reader-font-size', String(size))
  }

  const applyAppearance = useCallback((rendition: Rendition) => {
    rendition.themes.registerRules('readerLight', {
      body: { color: '#263143', background: '#ffffff' },
    })
    rendition.themes.registerRules('readerDark', {
      body: { color: '#e8e5e2', background: '#252525' },
    })
    rendition.themes.select(appearanceRef.current.theme === 'dark' ? 'readerDark' : 'readerLight')
    rendition.themes.fontSize(`${appearanceRef.current.fontSize}px`)
  }, [])

  const showLookup = useCallback(async (
    word: string,
    sentence: string,
    offset?: number,
    displayWord = word,
  ) => {
    const request = ++lookupRequestRef.current
    setSelection({ word: displayWord, sentence, offset })
    setDictionaryResult(null)
    setAnkiStatus('')
    setLookupStatus('Looking up…')

    try {
      const result = await lookupWord(word, offset)
      if (request !== lookupRequestRef.current) return
      setDictionaryResult(result)
      setLookupStatus('')
    } catch {
      if (request === lookupRequestRef.current) {
        setLookupStatus('No definition found. Japanese lookup works offline after importing a Yomitan dictionary.')
      }
    }
  }, [])

  const lookupHoveredWord = useCallback(() => {
    const hovered = hoveredWordRef.current
    if (!hovered || hovered.key === lastShiftLookupRef.current) return
    lastShiftLookupRef.current = hovered.key
    void showLookup(hovered.query, hovered.sentence, hovered.offset, hovered.displayWord)
  }, [showLookup])

  const installReaderInteractions = useCallback((contents: Contents) => {
    if (wiredContentsRef.current.has(contents)) return
    wiredContentsRef.current.add(contents)
    const document = contents.document

    const lookupSelection = () => {
      const selected = document.getSelection()
      const word = selected?.toString().replace(/\s+/g, ' ').trim() ?? ''
      if (!word || word.length > 80) return
      const parent = selected?.anchorNode?.parentElement
      const paragraph = parent?.closest('p, li, blockquote, h1, h2, h3, div')
      const sentence = (paragraph?.textContent ?? word).replace(/\s+/g, ' ').trim().slice(0, 500)
      void showLookup(word, sentence)
    }

    document.addEventListener('mouseup', lookupSelection)
    document.addEventListener('touchend', () => window.setTimeout(lookupSelection, 0), { passive: true })

    document.addEventListener('mousemove', (event) => {
      const pointer = event as MouseEvent
      const caretDocument = document as Document & {
        caretRangeFromPoint?: (x: number, y: number) => Range | null
        caretPositionFromPoint?: (x: number, y: number) => { offsetNode: Node; offset: number } | null
      }
      const caret = caretDocument.caretRangeFromPoint?.(pointer.clientX, pointer.clientY)
      const position = caret
        ? { node: caret.startContainer, offset: caret.startOffset }
        : (() => {
            const fallback = caretDocument.caretPositionFromPoint?.(pointer.clientX, pointer.clientY)
            return fallback ? { node: fallback.offsetNode, offset: fallback.offset } : null
          })()
      if (!position || position.node.nodeType !== Node.TEXT_NODE) {
        hoveredWordRef.current = null
        return
      }
      const element = position.node.parentElement
      const paragraph = element?.closest('p, li, blockquote, h1, h2, h3, div')
      if (!paragraph) {
        hoveredWordRef.current = null
        return
      }
      const prefixRange = document.createRange()
      prefixRange.selectNodeContents(paragraph)
      try {
        prefixRange.setEnd(position.node, position.offset)
      } catch {
        hoveredWordRef.current = null
        return
      }
      const rawText = paragraph.textContent ?? ''
      const sentence = rawText.replace(/\s+/g, ' ').trim()
      const offset = Array.from(prefixRange.toString().replace(/\s+/g, ' ').trimStart()).length
      if (!sentence) return

      let query = ''
      let displayWord = ''
      let lookupOffset: number | undefined
      if (/[\u3040-\u30ff\u3400-\u9fff]/u.test(sentence)) {
        const chars = Array.from(sentence)
        const cleanOffset = Math.max(0, Math.min(offset, chars.length - 1))
        if (!/[\u3040-\u30ff\u3400-\u9fff]/u.test(chars[cleanOffset])) {
          hoveredWordRef.current = null
          return
        }
        query = sentence
        displayWord = chars[cleanOffset]
        lookupOffset = cleanOffset
      } else {
        const wordPattern = /[\p{L}\p{M}\p{N}'’-]+/gu
        for (const match of sentence.matchAll(wordPattern)) {
          const start = match.index ?? 0
          if (offset >= start && offset <= start + match[0].length) {
            query = match[0]
            displayWord = query
            break
          }
        }
      }
      if (!query) {
        hoveredWordRef.current = null
        return
      }
      const key = `${query}:${lookupOffset ?? ''}:${sentence}`
      hoveredWordRef.current = { key, query, sentence: sentence.slice(0, 500), offset: lookupOffset, displayWord }
      if (pointer.shiftKey) lookupHoveredWord()
    })

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Shift' && !event.repeat) lookupHoveredWord()
    })
    document.addEventListener('keyup', (event) => {
      if (event.key === 'Shift') lastShiftLookupRef.current = ''
    })

  }, [lookupHoveredWord, showLookup])

  useEffect(() => {
    void getImportedDictionaries().then(setDictionaries).catch(() => {
      setDictionaryStatus('Could not read the local dictionary library.')
    })
  }, [])

  useEffect(() => {
    const viewer = viewerRef.current
    if (!viewer) return

    let book: ReturnType<typeof ePub> | null = null
    let cancelled = false

    async function displayBook(viewerElement: HTMLDivElement) {
      try {
        const data = await props.file.arrayBuffer()
        if (cancelled) return

        book = ePub(data)
        await book.opened
        if (cancelled) return
        setSectionTotal(book.spine.length)
        try {
          const navigation = await book.loaded.navigation
          if (cancelled) return
          const flatten = (items: NavItem[]): NavItem[] => items.flatMap((item) => [item, ...flatten(item.subitems ?? [])])
          setChapters(flatten(navigation.toc))
        } catch {
          // A missing navigation file should not stop the book from opening.
        }
        const rendition = book.renderTo(viewerElement, {
          width: '100%',
          height: '100%',
          flow: 'scrolled-continuous',
          manager: 'continuous',
        })
        renditionRef.current = rendition
        rendition.on('relocated', (location) => {
          const cfi = location.start?.cfi
          if (!cfi || cancelled) return
          const progress: ReadingProgress = {
            cfi,
            sectionIndex: location.start.index,
            sectionTotal: book?.spine.length ?? 0,
            updatedAt: Date.now(),
          }
          setCurrentSection(progress.sectionIndex)
          pendingProgressRef.current = progress
          if (progressTimerRef.current) clearTimeout(progressTimerRef.current)
          progressTimerRef.current = setTimeout(flushProgress, 800)
        })
        rendition.on('rendered', (_section, view) => {
          if (view.contents) {
            applyAppearance(rendition)
            installReaderInteractions(view.contents)
          }
        })
        applyAppearance(rendition)
        const savedCfi = initialProgressRef.current?.cfi
        if (savedCfi) {
          try {
            await rendition.display(savedCfi)
          } catch {
            await rendition.display()
          }
        } else {
          await rendition.display()
        }
        if (!cancelled) setIsOpening(false)
      } catch {
        if (!cancelled) {
          setError('Could not open this EPUB file.')
          setIsOpening(false)
        }
      }
    }

    void displayBook(viewer)

    return () => {
      cancelled = true
      flushProgress()
      book?.destroy()
      renditionRef.current = null
      viewer.replaceChildren()
    }
  }, [props.file, applyAppearance, installReaderInteractions])

  async function jumpToChapter(href: string) {
    if (!href || !renditionRef.current) return
    try {
      await renditionRef.current.display(href)
      setSelection(null)
    } catch {
      setError('Could not open that chapter in this EPUB.')
    }
  }

  useEffect(() => {
    appearanceRef.current = { theme: props.theme, fontSize }
    if (renditionRef.current) applyAppearance(renditionRef.current)
  }, [props.theme, fontSize, applyAppearance])

  useEffect(() => {
    const resetShiftLookup = (event: KeyboardEvent) => {
      if (event.key === 'Shift') lastShiftLookupRef.current = ''
    }
    const triggerShiftLookup = (event: KeyboardEvent) => {
      if (event.key === 'Shift' && !event.repeat) lookupHoveredWord()
    }
    window.addEventListener('keydown', triggerShiftLookup)
    window.addEventListener('keyup', resetShiftLookup)
    return () => {
      window.removeEventListener('keydown', triggerShiftLookup)
      window.removeEventListener('keyup', resetShiftLookup)
    }
  }, [lookupHoveredWord])

  async function handleDictionaryImport(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    if (!file) return
    setDictionaryStatus(`Importing “${file.name}”…`)

    try {
      const summary = await importYomitanDictionary(file)
      setDictionaries((current) => [summary, ...current.filter((dictionary) => dictionary.id !== summary.id)])
      setDictionaryStatus(`Imported ${summary.title}: ${summary.entryCount.toLocaleString()} terms available offline.`)
    } catch (importError) {
      setDictionaryStatus(importError instanceof Error ? importError.message : 'Could not import this dictionary.')
    }

    event.target.value = ''
  }

  async function handleTestAnki() {
    setAnkiStatus('Connecting to Anki…')
    try {
      const decks = await testAnkiConnection(ankiSettings)
      setAnkiStatus(`Connected. Found ${decks.length} deck${decks.length === 1 ? '' : 's'}.`)
    } catch {
      setAnkiStatus('Could not connect. Start Anki, install AnkiConnect, and allow this site origin.')
    }
  }

  async function handleAddToAnki() {
    if (!selection || !dictionaryResult) return
    setAnkiStatus('Adding card…')
    try {
      await addWordToAnki(ankiSettings, {
        ...dictionaryResult,
        sentence: selection.sentence,
        bookTitle: props.title,
      })
      setAnkiStatus('Added to Anki successfully.')
    } catch (ankiError) {
      const reason = ankiError instanceof Error ? ankiError.message : 'Unknown error'
      setAnkiStatus(`Could not add card: ${reason}`)
    }
  }

  return (
    <main className={`reader-page ${props.theme === 'dark' ? 'reader-dark' : ''}`}>
      <div className="reader-content">
        <div className="reader-heading">
          <button className="back-button" onClick={props.onClose}>← Library</button>
          <h1>{props.title}</h1>
          {chapters.length > 0 && (
            <select
              className="chapter-picker"
              aria-label="Jump to chapter"
              defaultValue=""
              onChange={(event) => { void jumpToChapter(event.target.value); event.target.value = '' }}
            >
              <option value="">Contents…</option>
              {chapters.map((chapter, index) => (
                <option key={`${chapter.href}-${index}`} value={chapter.href}>{chapter.label || `Chapter ${index + 1}`}</option>
              ))}
            </select>
          )}
          <button
            className="reader-tool-button"
            type="button"
            onClick={() => setShowReaderSettings((current) => !current)}
          >
            Reading settings
          </button>
          <button
            className="reader-tool-button"
            type="button"
            onClick={() => setShowAnkiSettings((current) => !current)}
          >
            Anki settings
          </button>
        </div>

        {showReaderSettings && (
          <section className="reader-settings-panel">
            <div className="reader-setting-group font-size-setting">
              <span>Font size</span>
              <div className="reader-setting-options">
                <button
                  type="button"
                  aria-label="Decrease font size"
                  disabled={fontSize <= 12}
                  onClick={() => saveFontSize(fontSize - 1)}
                >
                  A−
                </button>
                <output>{fontSize}px</output>
                <button
                  type="button"
                  aria-label="Increase font size"
                  disabled={fontSize >= 36}
                  onClick={() => saveFontSize(fontSize + 1)}
                >
                  A＋
                </button>
              </div>
            </div>
            <div className="dictionary-import-group">
              <button
                className="dictionary-import-button"
                type="button"
                onClick={() => dictionaryInputRef.current?.click()}
              >
                Import Yomitan dictionary
              </button>
              <input
                ref={dictionaryInputRef}
                className="visually-hidden-input"
                type="file"
                accept=".zip,application/zip"
                onChange={handleDictionaryImport}
              />
              {dictionaries.length > 0 && (
                <span>{dictionaries.length} {dictionaries.length === 1 ? 'local dictionary' : 'local dictionaries'}</span>
              )}
              {dictionaryStatus && <p aria-live="polite">{dictionaryStatus}</p>}
            </div>
          </section>
        )}

        {showAnkiSettings && (
          <section className="anki-settings-panel">
            <div className="anki-settings-heading">
              <div>
                <strong>AnkiConnect</strong>
                <p>Anki must be running on this computer.</p>
              </div>
              <button type="button" onClick={() => setShowAnkiSettings(false)}>×</button>
            </div>
            <div className="anki-settings-grid">
              {([
                ['endpoint', 'Endpoint'],
                ['deck', 'Deck'],
                ['model', 'Note type'],
                ['wordField', 'Word field'],
                ['definitionField', 'Definition field'],
                ['apiKey', 'API key (optional)'],
              ] as Array<[keyof AnkiSettings, string]>).map(([key, label]) => (
                <label key={key}>
                  <span>{label}</span>
                  <input
                    type={key === 'apiKey' ? 'password' : 'text'}
                    value={ankiSettings[key]}
                    onChange={(event) => saveAnkiSettings({ ...ankiSettings, [key]: event.target.value })}
                  />
                </label>
              ))}
            </div>
            <button className="anki-test-button" type="button" onClick={handleTestAnki}>Test connection</button>
            {ankiStatus && <p className="anki-status" aria-live="polite">{ankiStatus}</p>}
          </section>
        )}

        {error && <p className="reader-error" role="alert">{error}</p>}
        <p className="reader-hint">
          {currentSection === null
            ? props.progress ? 'Restoring your reading position…' : 'Scroll to read.'
            : `Chapter ${currentSection + 1}${sectionTotal ? ` of ${sectionTotal}` : ''} · Position saved automatically.`}
          {' '}Select text to look it up, or hover a word and press Shift.
        </p>
        {isOpening && <p className="reader-loading" role="status">Opening EPUB…</p>}
        <div className="reader-workspace">
          <div className="epub-viewer" ref={viewerRef} />
          {selection && (
            <aside className="dictionary-panel">
              <div className="dictionary-heading">
                <span className="dictionary-label">QUICK LOOKUP</span>
                <button
                  type="button"
                  aria-label="Close dictionary"
                  onClick={() => setSelection(null)}
                >×</button>
              </div>
              <h2>{dictionaryResult?.word ?? selection.word}</h2>
              {dictionaryResult?.reading && <p className="dictionary-reading">{dictionaryResult.reading}</p>}
              {lookupStatus && <p className="dictionary-message">{lookupStatus}</p>}
              {dictionaryResult && (
                <>
                  <ol className="definition-list">
                    {dictionaryResult.definitions.map((definition) => <li key={definition}>{definition}</li>)}
                  </ol>
                  <p className="dictionary-source">Source: {dictionaryResult.source}</p>
                </>
              )}
              <div className="sentence-context">
                <span>Context</span>
                <p>{selection.sentence}</p>
              </div>
              <button
                className="add-to-anki-button"
                type="button"
                disabled={!dictionaryResult}
                onClick={handleAddToAnki}
              >
                ＋ Add to Anki
              </button>
              {ankiStatus && <p className="anki-status" aria-live="polite">{ankiStatus}</p>}
            </aside>
          )}
        </div>
      </div>
    </main>
  )
}

export default EpubReader
