import type JSZip from 'jszip'
import deinja from 'deinja'

export type DictionaryResult = {
  word: string
  reading?: string
  definitions: string[]
  source: string
}

export type DictionarySummary = {
  id: string
  title: string
  entryCount: number
  importedAt: number
}

type TermEntry = {
  id: string
  dictionaryId: string
  expression: string
  reading: string
  score: number
  definitions: string[]
}

type YomitanIndex = {
  title?: string
  format?: number
  revision?: string
}

const databaseName = 'simple-reader'
const databaseVersion = 3
const termStoreName = 'dictionaryTerms'
const dictionaryStoreName = 'dictionaries'

const demoEntries: Record<string, DictionaryResult> = {
  curious: {
    word: 'curious',
    reading: '/ˈkjʊəriəs/',
    definitions: [
      'Eager to know or learn something. · adjective',
      'Strange or unusual. · adjective',
    ],
    source: 'Built-in demo dictionary',
  },
  traveler: {
    word: 'traveler',
    reading: '/ˈtrævələr/',
    definitions: ['A person who is traveling or who often travels. · noun'],
    source: 'Built-in demo dictionary',
  },
  remarkable: {
    word: 'remarkable',
    reading: '/rɪˈmɑːrkəbəl/',
    definitions: ['Worthy of attention; extraordinary. · adjective'],
    source: 'Built-in demo dictionary',
  },
}

function openDatabase() {
  return new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(databaseName, databaseVersion)

    request.onupgradeneeded = () => {
      const database = request.result

      if (!database.objectStoreNames.contains('books')) {
        database.createObjectStore('books', { keyPath: 'id' })
      }
      if (!database.objectStoreNames.contains('directories')) {
        database.createObjectStore('directories', { keyPath: 'id' })
      }
      if (!database.objectStoreNames.contains(termStoreName)) {
        const terms = database.createObjectStore(termStoreName, { keyPath: 'id' })
        terms.createIndex('expression', 'expression', { unique: false })
        terms.createIndex('reading', 'reading', { unique: false })
        terms.createIndex('dictionaryId', 'dictionaryId', { unique: false })
      }
      if (!database.objectStoreNames.contains(dictionaryStoreName)) {
        database.createObjectStore(dictionaryStoreName, { keyPath: 'id' })
      }
    }

    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

function normalizeTerm(value: string) {
  return value.normalize('NFKC').replace(/[\u30a1-\u30f6]/g, (character) =>
    String.fromCharCode(character.charCodeAt(0) - 0x60),
  )
}

function cleanTerm(value: string) {
  return value
    .trim()
    .replace(/^[\s.,!?;:'"“”‘’()[\]{}「」『』、。！？]+|[\s.,!?;:'"“”‘’()[\]{}「」『』、。！？]+$/gu, '')
}

function isJapanese(value: string) {
  return /[\u3040-\u30ff\u3400-\u9fff]/u.test(value)
}

function textFromStructured(value: unknown): string[] {
  if (typeof value === 'string') {
    const text = new DOMParser().parseFromString(value, 'text/html').body.textContent ?? value
    return text.split(/\n+/).map((line) => line.trim()).filter(Boolean)
  }

  if (Array.isArray(value)) {
    return value.flatMap(textFromStructured)
  }

  if (value && typeof value === 'object') {
    const node = value as { content?: unknown; tag?: string }
    const content = textFromStructured(node.content)
    return node.tag === 'br' ? [...content, '\n'] : content
  }

  return []
}

function entryDefinitions(value: unknown) {
  const definitions = textFromStructured(value)
    .map((definition) => definition.replace(/\s+/g, ' ').trim())
    .filter(Boolean)

  return [...new Set(definitions)].slice(0, 12)
}

async function readZipText(zip: JSZip, path: string) {
  const file = zip.file(path)

  if (!file) {
    return undefined
  }

  return file.async('string')
}

export async function importYomitanDictionary(file: File): Promise<DictionarySummary> {
  const { default: Zip } = await import('jszip')
  const zip = await Zip.loadAsync(file)
  const indexPath = Object.keys(zip.files).find((path) => /(^|\/)index\.json$/i.test(path))
  const indexText = indexPath ? await readZipText(zip, indexPath) : undefined

  if (!indexText) {
    throw new Error('This ZIP does not contain a Yomitan index.json.')
  }

  const index = JSON.parse(indexText) as YomitanIndex
  const title = index.title?.trim() || file.name.replace(/\.zip$/i, '')
  const dictionaryId = `${title.toLocaleLowerCase()}-${file.size}`
  const bankPaths = Object.keys(zip.files)
    .filter((path) => /(^|\/)term_bank_\d+\.json$/i.test(path))
    .sort((first, second) => first.localeCompare(second, undefined, { numeric: true }))

  if (bankPaths.length === 0) {
    throw new Error('No Yomitan term banks were found in this ZIP.')
  }

  const entries: TermEntry[] = []
  let entryNumber = 0

  for (const path of bankPaths) {
    const bankText = await readZipText(zip, path)
    if (!bankText) continue

    const bank = JSON.parse(bankText) as unknown[]

    for (const rawEntry of bank) {
      if (!Array.isArray(rawEntry)) continue

      const expression = typeof rawEntry[0] === 'string' ? rawEntry[0] : ''
      const reading = typeof rawEntry[1] === 'string' ? rawEntry[1] : ''
      const definitions = entryDefinitions(rawEntry[5])

      if (!expression || definitions.length === 0) continue

      entries.push({
        id: `${dictionaryId}:${entryNumber++}`,
        dictionaryId,
        expression,
        reading,
        score: typeof rawEntry[4] === 'number' ? rawEntry[4] : 0,
        definitions,
      })
    }
  }

  if (entries.length === 0) {
    throw new Error('The dictionary contains no readable term entries.')
  }

  const database = await openDatabase()
  try {
    const oldEntries = await new Promise<TermEntry[]>((resolve, reject) => {
      const request = database.transaction(termStoreName, 'readonly')
        .objectStore(termStoreName).index('dictionaryId').getAll(dictionaryId)
      request.onsuccess = () => resolve(request.result as TermEntry[])
      request.onerror = () => reject(request.error)
    })

    for (let offset = 0; offset < entries.length; offset += 1000) {
      await new Promise<void>((resolve, reject) => {
        const transaction = database.transaction([termStoreName, dictionaryStoreName], 'readwrite')
        const termStore = transaction.objectStore(termStoreName)

        if (offset === 0) {
          for (const oldEntry of oldEntries) termStore.delete(oldEntry.id)
          transaction.objectStore(dictionaryStoreName).put({
            id: dictionaryId,
            title,
            entryCount: entries.length,
            importedAt: Date.now(),
          } satisfies DictionarySummary)
        }

        for (const entry of entries.slice(offset, offset + 1000)) termStore.put(entry)
        transaction.oncomplete = () => resolve()
        transaction.onerror = () => reject(transaction.error)
        transaction.onabort = () => reject(transaction.error)
      })
    }
  } finally {
    database.close()
  }

  return {
    id: dictionaryId,
    title,
    entryCount: entries.length,
    importedAt: Date.now(),
  }
}

export async function getImportedDictionaries() {
  const database = await openDatabase()

  try {
    return await new Promise<DictionarySummary[]>((resolve, reject) => {
      const transaction = database.transaction(dictionaryStoreName, 'readonly')
      const request = transaction.objectStore(dictionaryStoreName).getAll()
      request.onsuccess = () => resolve(request.result as DictionarySummary[])
      request.onerror = () => reject(request.error)
    })
  } finally {
    database.close()
  }
}

async function queryCandidates(candidates: Array<[string, number, number]>) {
  const database = await openDatabase()

  try {
    return await new Promise<Array<TermEntry & { matchedLength: number; distance: number }>>((resolve, reject) => {
      const transaction = database.transaction(termStoreName, 'readonly')
      const store = transaction.objectStore(termStoreName)
      const matches: Array<TermEntry & { matchedLength: number; distance: number }> = []

      for (const [candidate, matchedLength, distance] of candidates) {
        for (const indexName of ['expression', 'reading'] as const) {
          const request = store.index(indexName).getAll(candidate)
          request.onsuccess = () => {
            for (const entry of request.result as TermEntry[]) {
              matches.push({ ...entry, matchedLength, distance })
            }
          }
        }
      }

      transaction.oncomplete = () => resolve(matches)
      transaction.onerror = () => reject(transaction.error)
      transaction.onabort = () => reject(transaction.error)
    })
  } finally {
    database.close()
  }
}

function lookupCandidates(rawWord: string, offset?: number) {
  const original = cleanTerm(rawWord)
  const normalized = normalizeTerm(original)
  const candidates = new Map<string, { matchedLength: number; distance: number }>()

  function add(candidate: string, matchedLength: number, distance: number) {
    const current = candidates.get(candidate)
    if (
      candidate
      && (!current || distance < current.distance
        || (distance === current.distance && matchedLength > current.matchedLength))
    ) {
      candidates.set(candidate, { matchedLength, distance })
    }
  }

  add(normalized, normalized.length, 0)
  const normalizedCharacters = Array.from(normalized)

  const preferredStart = Math.max(0, Math.min(offset ?? 0, normalizedCharacters.length - 1))
  const startPositions = Array.from(
    { length: Math.min(normalizedCharacters.length, 18) },
    (_, index) => offset === 0 ? index : Math.max(0, preferredStart - 1 + index),
  )

  for (const start of startPositions) {
    const maxLength = Math.min(16, normalizedCharacters.length - start)

    for (let length = maxLength; length > 0; length -= 1) {
      const distance = offset === undefined ? start : Math.abs(start - preferredStart)
      const surface = normalizedCharacters.slice(start, start + length).join('')
      add(surface, length, distance)

      for (const form of deinja.convert(surface).slice(0, 12)) {
        add(normalizeTerm(form), length, distance)
      }
    }
  }

  return [...candidates.entries()]
    .map(([candidate, rank]) => [candidate, rank.matchedLength, rank.distance] as [string, number, number])
    .sort((first, second) => first[2] - second[2] || second[1] - first[1])
    .slice(0, 180)
}

async function lookupImportedJapanese(
  word: string,
  offset?: number,
): Promise<DictionaryResult | undefined> {
  const imported = await getImportedDictionaries()
  if (imported.length === 0) return undefined

  const candidates = lookupCandidates(word, offset)
  let matches = await queryCandidates(candidates)

  if (matches.length === 0) {
    const { unconjugate } = await import('jp-verbs')
    const normalized = normalizeTerm(cleanTerm(word))
    const characters = Array.from(normalized)
    const preferredStart = Math.max(0, Math.min(offset ?? 0, characters.length - 1))
    const starts = Array.from({ length: Math.min(characters.length, 18) }, (_, index) =>
      offset === undefined ? index : Math.max(0, preferredStart - 1 + index),
    )
    const fallbackCandidates = new Map(candidates.map(([candidate, length, distance]) => [
      candidate,
      { matchedLength: length, distance },
    ]))

    for (const start of starts) {
      const maxLength = Math.min(16, characters.length - start)
      for (let length = maxLength; length > 0; length -= 1) {
        const surface = characters.slice(start, start + length).join('')
        for (const form of unconjugate(surface, true, 8).slice(0, 12)) {
          const base = normalizeTerm(form.base)
          const distance = offset === undefined ? start : Math.abs(start - preferredStart)
          const current = fallbackCandidates.get(base)
          if (
            base
            && (!current || distance < current.distance
              || (distance === current.distance && length > current.matchedLength))
          ) {
            fallbackCandidates.set(base, { matchedLength: length, distance })
          }
        }
      }
    }

    matches = await queryCandidates([...fallbackCandidates.entries()]
      .map(([candidate, rank]) => [candidate, rank.matchedLength, rank.distance] as [string, number, number])
      .sort((first, second) => first[2] - second[2] || second[1] - first[1])
      .slice(0, 280))
  }

  const ranked = [...new Map(matches.map((entry) => [entry.id, entry])).values()]
    .sort((first, second) =>
      first.distance - second.distance
      || second.matchedLength - first.matchedLength
      || second.score - first.score,
    )
    .slice(0, 8)

  if (ranked.length === 0) return undefined

  return {
    word: ranked[0].expression,
    reading: ranked[0].reading || undefined,
    definitions: [...new Set(ranked.flatMap((entry) => entry.definitions))].slice(0, 8),
    source: imported.map((dictionary) => dictionary.title).join(', '),
  }
}

async function fetchWithTimeout(url: string) {
  const controller = new AbortController()
  const timeout = window.setTimeout(() => controller.abort(), 8000)

  try {
    return await fetch(url, { signal: controller.signal })
  } finally {
    window.clearTimeout(timeout)
  }
}

async function lookupJapaneseOnline(word: string): Promise<DictionaryResult> {
  const response = await fetchWithTimeout(
    `https://jisho.org/api/v1/search/words?keyword=${encodeURIComponent(word)}`,
  )

  if (!response.ok) throw new Error('Dictionary request failed.')

  const payload = await response.json() as {
    data?: Array<{
      japanese?: Array<{ reading?: string; word?: string }>
      senses?: Array<{ english_definitions?: string[]; parts_of_speech?: string[] }>
    }>
  }
  const entry = payload.data?.[0]
  if (!entry) throw new Error('No definition found.')

  const headword = entry.japanese?.find((item) => item.word)?.word
    ?? entry.japanese?.[0]?.reading
    ?? word
  const reading = entry.japanese?.find((item) => item.reading)?.reading
  const definitions = (entry.senses ?? [])
    .slice(0, 4)
    .map((sense) => {
      const meaning = sense.english_definitions?.join('; ') ?? ''
      const partOfSpeech = sense.parts_of_speech?.[0]
      return partOfSpeech ? `${meaning} · ${partOfSpeech}` : meaning
    })
    .filter(Boolean)

  if (definitions.length === 0) throw new Error('No definition found.')
  return { word: headword, reading, definitions, source: 'Jisho (online fallback)' }
}

async function lookupEnglish(word: string): Promise<DictionaryResult> {
  const response = await fetchWithTimeout(
    `https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`,
  )

  if (!response.ok) throw new Error('No definition found.')

  const payload = await response.json() as Array<{
    word?: string
    phonetic?: string
    meanings?: Array<{
      partOfSpeech?: string
      definitions?: Array<{ definition?: string }>
    }>
  }>
  const entry = payload[0]
  const definitions = (entry?.meanings ?? [])
    .flatMap((meaning) =>
      (meaning.definitions ?? []).slice(0, 2).map((definition) => {
        const text = definition.definition ?? ''
        return meaning.partOfSpeech ? `${text} · ${meaning.partOfSpeech}` : text
      }),
    )
    .filter(Boolean)
    .slice(0, 5)

  if (!entry || definitions.length === 0) throw new Error('No definition found.')
  return {
    word: entry.word ?? word,
    reading: entry.phonetic,
    definitions,
    source: 'Free Dictionary API',
  }
}

export async function lookupWord(rawWord: string, offset?: number) {
  const word = cleanTerm(rawWord)
  if (!word) throw new Error('Select a word first.')

  if (isJapanese(word)) {
    const localResult = await lookupImportedJapanese(word, offset)
    if (localResult) return localResult
    return lookupJapaneseOnline(word)
  }

  const demoEntry = demoEntries[word.toLowerCase()]
  return demoEntry ?? lookupEnglish(word)
}
