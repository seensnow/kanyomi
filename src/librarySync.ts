import { getSavedBooks, removeImportedBook, saveImportedBook, saveReadingProgress, saveSyncId } from './bookStorage'
import type { ImportedBook, ReadingProgress, SavedBook } from './bookStorage'
import type { ReadingAnchor } from './readingAnchor'

export type SyncedBook = {
  id: string
  title: string
  addedAt: number
  removedAt?: number
  position?: ReadingAnchor & { updatedAt: number; cfi?: string }
}

const api = '/api/sync/books'
const changeEvent = 'kanyomi-library-changed'
const recordsKey = 'kanyomi-sync-books'
const removalsKey = 'kanyomi-sync-removals'
export const syncKeyName = 'kanyomi-sync-key'
export const isOnShelf = (book: SyncedBook) => book.addedAt > (book.removedAt ?? 0)

function readRecords(key: string): SyncedBook[] {
  try { return JSON.parse(localStorage.getItem(key) ?? '[]') } catch { return [] }
}

export function cachedShelf() { return readRecords(recordsKey).filter(isOnShelf) }
export function notifyLibrarySync() { window.dispatchEvent(new Event(changeEvent)) }

async function bookId(book: ImportedBook) {
  if (book.syncId) return book.syncId
  const digest = await crypto.subtle.digest('SHA-256', await book.file.arrayBuffer())
  const id = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('')
  await saveSyncId(book.id, id)
  return id
}

export async function queueShelfRemoval(book: ImportedBook | SyncedBook) {
  const id = 'source' in book ? await bookId(book) : book.id
  const pending = readRecords(removalsKey).filter(item => item.id !== id)
  const record = { id, title: book.title, addedAt: book.addedAt, removedAt: Date.now() }
  localStorage.setItem(removalsKey, JSON.stringify([...pending, record]))
  localStorage.setItem(recordsKey, JSON.stringify(readRecords(recordsKey).filter(item => item.id !== id)))
}

function syncRequest(key: string, path: string, options?: RequestInit) {
  const headers = new Headers(options?.headers)
  headers.set('Authorization', `Bearer ${key}`)
  const timeout = AbortSignal.timeout?.(45_000)
  const signal = options?.signal && timeout && AbortSignal.any
    ? AbortSignal.any([options.signal, timeout]) : options?.signal ?? timeout
  return fetch(`${api}${path}`, { ...options, headers, signal, cache: 'no-store', redirect: 'error' }).then(response => {
    if (response.ok) return response
    if (response.status === 401) throw new Error('Sync key rejected. Check the key for this server.')
    if (response.status === 413) throw new Error('This EPUB exceeds the sync limit of 128 MiB.')
    throw new Error('Sync server unavailable. Changes will retry automatically.')
  })
}

function recordPosition(record: SyncedBook): ReadingProgress | undefined {
  const position = record.position
  if (!position) return
  return { anchor: { path: position.path, offset: position.offset }, cfi: position.cfi,
    sectionIndex: -1, sectionTotal: 0, updatedAt: position.updatedAt }
}

export async function downloadSyncedBook(key: string, record: SyncedBook) {
  const response = await syncRequest(key, `/${record.id}`)
  const data = await response.arrayBuffer()
  const file = new File([data], `${record.id}.epub`, { type: 'application/epub+zip' })
  const { readEpubDetails } = await import('./epubMetadata')
  const { cover } = await readEpubDetails(file, data)
  return saveImportedBook({ id: record.id, syncId: record.id, file, cover, title: record.title,
    addedAt: record.addedAt, progress: recordPosition(record), source: 'imported' })
}

async function reconcile(key: string, openBook: () => string | undefined, signal: AbortSignal) {
  const request = (path: string, options?: RequestInit) => syncRequest(key, path, { ...options, signal })
  const write = async (record: SyncedBook): Promise<SyncedBook> => (await request(`/${record.id}/state`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(record),
  })).json()
  const incoming: SyncedBook[] = await (await request('')).json()
  const shelf = new Map(incoming.map(book => [book.id, book]))

  for (const removal of readRecords(removalsKey)) {
    shelf.set(removal.id, await write(removal))
    localStorage.setItem(removalsKey, JSON.stringify(readRecords(removalsKey).filter(
      item => item.id !== removal.id || item.removedAt !== removal.removedAt,
    )))
  }

  const local = await getSavedBooks()
  let skippedLargeBooks = false
  for (const book of local) {
    if (book.source !== 'imported') continue
    signal.throwIfAborted()
    const id = await bookId(book)
    let remote = shelf.get(id)
    const position = book.progress?.anchor && { ...book.progress.anchor, cfi: book.progress.cfi, updatedAt: book.progress.updatedAt }

    if (!remote) {
      if (book.file.size > 128 * 1024 * 1024) { skippedLargeBooks = true; continue }
      await request(`/${id}`, { method: 'PUT', body: book.file })
    }
    if (!remote || !isOnShelf(remote) && book.addedAt > (remote.removedAt ?? 0) ||
        (position && position.updatedAt > (remote.position?.updatedAt ?? 0) && isOnShelf(remote))) {
      remote = await write({ id, title: book.title, addedAt: book.addedAt, position })
      shelf.set(id, remote)
    }
    if (openBook() === book.id) continue
    if (!isOnShelf(remote)) await removeImportedBook(book.id)
    else if ((remote.position?.updatedAt ?? 0) > (book.progress?.updatedAt ?? 0)) {
      await saveReadingProgress(book.id, recordPosition(remote)!)
    }
  }
  signal.throwIfAborted()
  const records = [...shelf.values()]
  localStorage.setItem(recordsKey, JSON.stringify(records))
  return { local: await getSavedBooks(), remote: records.filter(isOnShelf), skippedLargeBooks }
}

export function watchLibrarySync(key: string, openBook: () => string | undefined,
  onChange: (status: string, local?: SavedBook[], remote?: SyncedBook[]) => void) {
  const controller = new AbortController()
  let running = false
  let pending = false
  let timer: ReturnType<typeof setTimeout>

  function schedule() {
    clearTimeout(timer)
    timer = setTimeout(() => void sync(), 500)
  }

  async function sync() {
    if (controller.signal.aborted || document.hidden) return
    if (!navigator.onLine) { onChange('Offline · changes saved on this device'); return }
    if (running) { pending = true; return }
    running = true
    try {
      const result = await reconcile(key, openBook, controller.signal)
      if (!controller.signal.aborted) onChange(result.skippedLargeBooks
        ? 'Synced · EPUBs over 128 MiB stay on this device' : 'Library synced', result.local, result.remote)
    } catch (error) {
      if (!controller.signal.aborted) onChange(error instanceof Error ? error.message : 'Sync will retry automatically.')
    } finally {
      running = false
      if (pending) { pending = false; schedule() }
    }
  }

  const events = ['online', 'offline', changeEvent]
  for (const event of events) window.addEventListener(event, schedule, { signal: controller.signal })
  document.addEventListener('visibilitychange', schedule, { signal: controller.signal })
  const poll = setInterval(schedule, 10_000)
  schedule()
  return () => { controller.abort(); clearTimeout(timer); clearInterval(poll) }
}
