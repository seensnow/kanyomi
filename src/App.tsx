import { readPreference } from './storageMigration'
import { lazy, Suspense, useEffect, useRef, useState } from 'react'
import type { ChangeEvent } from 'react'
import BookCover from './BookCover'
import { requestPersistentStorage, watchOfflineAvailability } from './offline'
import { cachedShelf, downloadSyncedBook, notifyLibrarySync, queueShelfRemoval, syncKeyName, watchLibrarySync } from './librarySync'
import type { SyncedBook } from './librarySync'
import {
  getSavedBooks,
  getSavedDirectories,
  removeImportedBook,
  saveBook,
  saveLinkedLibrary,
  saveReadingProgress,
  unlinkDirectory,
} from './bookStorage'
import type {
  LinkedBook,
  ReadingProgress,
  SavedBook,
  SavedDirectory,
} from './bookStorage'
import {
  pickDirectory,
  requestReadPermission,
  supportsDirectoryPicker,
} from './fileSystemAccess'

const EpubReader = lazy(() => import('./EpubReader'))

type ReaderBook = {
  id: string
  title: string
  file: Blob
  progress?: ReadingProgress
}

type FolderEpub = {
  handle: FileSystemFileHandle
  relativePath: string
}

type Theme = 'light' | 'dark'

function getInitialTheme(): Theme {
  try {
    const savedTheme = readPreference('kanyomi-theme')
    if (savedTheme === 'light' || savedTheme === 'dark') return savedTheme
    const legacyAppearance = readPreference('kanyomi-appearance')
    if (legacyAppearance && JSON.parse(legacyAppearance).theme === 'dark') return 'dark'
  } catch {
    // Use the default theme when storage is unavailable or malformed.
  }
  return 'dark'
}

async function findEpubs(
  directory: FileSystemDirectoryHandle,
  parentPath = '',
): Promise<FolderEpub[]> {
  const epubs: FolderEpub[] = []

  for await (const entry of directory.values()) {
    const relativePath = parentPath
      ? `${parentPath}/${entry.name}`
      : entry.name

    if (entry.kind === 'directory') {
      epubs.push(...await findEpubs(entry, relativePath))
    } else if (/\.epub$/i.test(entry.name)) {
      epubs.push({ handle: entry, relativePath })
    }
  }

  return epubs
}

async function findMatchingDirectory(
  handle: FileSystemDirectoryHandle,
  savedDirectories: SavedDirectory[],
) {
  for (const directory of savedDirectories) {
    try {
      if (await directory.handle.isSameEntry(handle)) {
        return directory
      }
    } catch {
      // Ignore a stale handle and treat this as a newly linked folder.
    }
  }
}

function errorName(error: unknown) {
  return error instanceof DOMException ? error.name : ''
}

function App() {
  const importInputRef = useRef<HTMLInputElement>(null)
  const [books, setBooks] = useState<SavedBook[]>([])
  const [readerBook, setReaderBook] = useState<ReaderBook | null>(null)
  const [searchText, setSearchText] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const [isScanning, setIsScanning] = useState(false)
  const [isImporting, setIsImporting] = useState(false)
  const [openingBookId, setOpeningBookId] = useState('')
  const [managingBookId, setManagingBookId] = useState('')
  const [message, setMessage] = useState('')
  const [offlineStatus, setOfflineStatus] = useState('')
  const [syncKey, setSyncKey] = useState(() => {
    try { return localStorage.getItem(syncKeyName) ?? '' } catch { return '' }
  })
  const [keyInput, setKeyInput] = useState('')
  const [syncStatus, setSyncStatus] = useState('')
  const [remoteBooks, setRemoteBooks] = useState(cachedShelf)
  const readerId = useRef<string | undefined>(undefined)
  const [theme, setTheme] = useState<Theme>(getInitialTheme)

  function changeTheme(nextTheme: Theme) {
    setTheme(nextTheme)
    try { localStorage.setItem('kanyomi-theme', nextTheme) } catch { /* Preference is optional. */ }
  }

  useEffect(() => {
    getSavedBooks()
      .then(setBooks)
      .catch(() => setMessage('Could not load your local library.'))
      .finally(() => setIsLoading(false))
  }, [])

  useEffect(() => watchOfflineAvailability(setOfflineStatus), [])

  useEffect(() => {
    readerId.current = readerBook?.id
    if (!readerBook) notifyLibrarySync()
  }, [readerBook])

  useEffect(() => {
    if (!syncKey) return
    return watchLibrarySync(syncKey, () => readerId.current, (status, local, remote) => {
      setSyncStatus(status)
      if (local) setBooks(local)
      if (remote) setRemoteBooks(remote)
    })
  }, [syncKey])

  function changeSyncKey(key: string) {
    if (key && !/^[a-f0-9]{64}$/.test(key)) {
      setSyncStatus('Enter the 64-character sync key for your Kanyomi server.')
      return
    }
    try {
      if (key) localStorage.setItem(syncKeyName, key)
      else localStorage.removeItem(syncKeyName)
      setSyncKey(key)
      setKeyInput('')
      setSyncStatus(key ? 'Connecting…' : '')
    } catch {
      setSyncStatus('This browser could not save the sync settings.')
    }
  }

  async function handleImport(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]

    if (!file) {
      return
    }

    setIsImporting(true)
    void requestPersistentStorage()
    setMessage('Importing EPUB…')
    try {
      const { readEpubDetails } = await import('./epubMetadata')
      const data = await file.arrayBuffer()
      const details = await readEpubDetails(file, data)
      const savedBook = await saveBook(file, details.title, details.cover, data)
      setBooks((currentBooks) => [
        savedBook,
        ...currentBooks.filter((book) => book.id !== savedBook.id),
      ])
      setReaderBook({ id: savedBook.id, title: savedBook.title, file: savedBook.file, progress: savedBook.progress })
      notifyLibrarySync()
      setMessage('Imported into this browser for offline reading.')
    } catch (error) {
      setMessage(error instanceof DOMException && error.name === 'QuotaExceededError'
        ? 'Browser storage is full. Remove an imported book or free browser storage, then try again.'
        : 'Could not import this EPUB. Check that the file is a valid EPUB and try again.')
    } finally {
      setIsImporting(false)
      event.target.value = ''
    }
  }

  async function handleOpenFolder() {
    if (!supportsDirectoryPicker) {
      setMessage('Open Folder is not supported in this browser. Use Import EPUB instead.')
      return
    }

    setIsScanning(true)
    setMessage('Choose a folder to scan for EPUB files…')

    try {
      const handle = await pickDirectory()
      const savedDirectories = await getSavedDirectories()
      const existingDirectory = await findMatchingDirectory(handle, savedDirectories)
      const directory: SavedDirectory = existingDirectory ?? {
        id: crypto.randomUUID(),
        name: handle.name,
        handle,
        addedAt: Date.now(),
      }
      const folderEpubs = await findEpubs(handle)
      const { readEpubDetails } = await import('./epubMetadata')
      const linkedBooks: LinkedBook[] = []
      let failedCount = 0

      setMessage(`Reading ${folderEpubs.length} EPUB ${folderEpubs.length === 1 ? 'file' : 'files'}…`)

      for (const folderEpub of folderEpubs) {
        try {
          const file = await folderEpub.handle.getFile()
          const details = await readEpubDetails(file)
          linkedBooks.push({
            id: `linked-${directory.id}-${folderEpub.relativePath}`,
            source: 'linked',
            title: details.title,
            cover: details.cover,
            addedAt: existingDirectory?.addedAt ?? Date.now(),
            fileHandle: folderEpub.handle,
            directoryId: directory.id,
            relativePath: folderEpub.relativePath,
          })
        } catch {
          failedCount += 1
        }
      }

      let persisted = true

      try {
        await saveLinkedLibrary(directory, linkedBooks)
      } catch {
        persisted = false
      }

      setBooks((currentBooks) => [
        ...linkedBooks,
        ...currentBooks.filter(
          (book) => book.source !== 'linked' || book.directoryId !== directory.id,
        ),
      ])

      if (folderEpubs.length === 0) {
        setMessage(`No EPUB files were found in “${handle.name}”.`)
      } else {
        const skipped = failedCount > 0 ? ` ${failedCount} could not be read.` : ''
        const persistenceNote = persisted
          ? ''
          : ' This browser could not remember the folder link, but it will work for this session.'
        setMessage(
          `Linked ${linkedBooks.length} ${linkedBooks.length === 1 ? 'book' : 'books'} from “${handle.name}”.${skipped}${persistenceNote}`,
        )
      }
    } catch (error) {
      if (errorName(error) === 'AbortError') {
        setMessage('Folder selection was cancelled. No files were accessed.')
      } else if (errorName(error) === 'NotAllowedError') {
        setMessage('Folder permission was not granted. You can try again or use Import EPUB.')
      } else {
        setMessage('Could not read that folder. You can try again or use Import EPUB.')
      }
    } finally {
      setIsScanning(false)
    }
  }

  async function handleOpenBook(book: SavedBook | SyncedBook) {
    if (!('source' in book)) {
      setOpeningBookId(book.id)
      try {
        const downloaded = await downloadSyncedBook(syncKey, book)
        setBooks(current => [downloaded, ...current.filter(item => item.id !== downloaded.id)])
        setReaderBook(downloaded)
      } catch {
        setMessage('Connect to the internet to download this EPUB for offline reading.')
      } finally {
        setOpeningBookId('')
      }
      return
    }
    if (book.source === 'imported') {
      setReaderBook({ id: book.id, title: book.title, file: book.file, progress: book.progress })
      return
    }

    setOpeningBookId(book.id)

    try {
      const hasPermission = await requestReadPermission(book.fileHandle)

      if (!hasPermission) {
        setMessage('File permission was not granted. Open the linked folder again or use Import EPUB.')
        return
      }

      const file = await book.fileHandle.getFile()
      setReaderBook({ id: book.id, title: book.title, file, progress: book.progress })
      setMessage('')
    } catch (error) {
      if (errorName(error) === 'NotAllowedError') {
        setMessage('File permission was not granted. Open the linked folder again to restore access.')
      } else if (errorName(error) === 'NotFoundError') {
        setMessage('This linked EPUB was moved or deleted. Open its folder again to refresh the library.')
      } else {
        setMessage('Could not open this linked EPUB. Open its folder again to refresh access.')
      }
    } finally {
      setOpeningBookId('')
    }
  }

  function handleProgress(id: string, progress: ReadingProgress) {
    setBooks((currentBooks) => currentBooks.map((book) => book.id === id ? { ...book, progress } : book))
    void saveReadingProgress(id, progress).then(notifyLibrarySync).catch(() => {
      setMessage('Reading position could not be saved in this browser.')
    })
  }

  async function handleRemoveBook(book: SavedBook | SyncedBook) {
    const linked = 'source' in book && book.source === 'linked' ? book : undefined
    const folderName = linked
      ? (await getSavedDirectories().catch(() => [])).find((folder) => folder.id === linked.directoryId)?.name ?? 'this folder'
      : ''
    const confirmed = linked
      ? window.confirm(`Unlink “${folderName}” and remove all its books from this library? The files on disk will stay untouched.`)
      : window.confirm(syncKey ? `Remove “${book.title}” from your synced shelf?`
        : `Remove “${book.title}” from this browser? Its imported EPUB and saved position will be deleted.`)
    if (!confirmed) return

    setManagingBookId(book.id)
    try {
      if (linked) {
        await unlinkDirectory(linked.directoryId)
        setBooks((current) => current.filter((item) => item.source !== 'linked' || item.directoryId !== linked.directoryId))
        setMessage(`Unlinked “${folderName}”. Files on disk were not changed.`)
      } else if (!('source' in book) || book.source === 'imported') {
        if (syncKey) {
          await queueShelfRemoval(book)
          setRemoteBooks(cachedShelf())
        }
        if ('source' in book) await removeImportedBook(book.id)
        setBooks((current) => current.filter((item) => item.id !== book.id))
        setMessage(`Removed “${book.title}”.`)
        notifyLibrarySync()
      }
    } catch {
      setMessage('Could not update the library. Please try again.')
    } finally {
      setManagingBookId('')
    }
  }

  const availableBooks = [...books, ...(syncKey ? remoteBooks.filter(remote => !books.some(
    book => book.source === 'imported' && (book.syncId === remote.id || book.id === remote.id),
  )) : [])]
  const filteredBooks = availableBooks.filter((book) =>
    book.title.toLowerCase().includes(searchText.toLowerCase()),
  )

  return (
    <div className={`app-shell ${theme === 'dark' ? 'app-dark' : ''}`}>
      <header className="top-bar">
        <button className="brand" onClick={() => setReaderBook(null)}>
          <span className="brand-mark" aria-hidden="true"><img src="/brand-mark.svg" alt="" /></span>
          <span>Kanyomi</span>
        </button>
        <button
          className="global-theme-button"
          type="button"
          aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`}
          onClick={() => changeTheme(theme === 'dark' ? 'light' : 'dark')}
        >
          {theme === 'dark' ? '☀ Light' : '☾ Dark'}
        </button>
      </header>

      {readerBook ? (
        <Suspense fallback={<main className="reader-page">Opening book…</main>}>
          <EpubReader
            key={readerBook.id}
            title={readerBook.title}
            file={readerBook.file}
            progress={readerBook.progress}
            theme={theme}
            onProgress={(progress) => handleProgress(readerBook.id, progress)}
            onClose={() => setReaderBook(null)}
          />
        </Suspense>
      ) : (
        <main className="library-page">
          <section className="library-toolbar">
            <div>
              <p className="eyebrow">MY LIBRARY</p>
              <h1>Your books</h1>
              <p className="library-summary">
                {syncKey ? 'Imported books sync with your Mac.' : 'Linked books stay in their folder; imported books stay privately in this browser.'}
              </p>
            </div>

            <div className="library-actions">
              <input
                className="library-search"
                type="search"
                placeholder="Search your library"
                value={searchText}
                onChange={(event) => setSearchText(event.target.value)}
              />
              <button
                className="folder-button"
                type="button"
                disabled={!supportsDirectoryPicker || isScanning}
                title={supportsDirectoryPicker
                  ? 'Link EPUBs from a folder without copying them'
                  : 'Not supported in this browser; use Import EPUB'}
                onClick={handleOpenFolder}
              >
                <span>⌁</span> {isScanning ? 'Scanning…' : 'Open Folder'}
              </button>
              <button
                className={`import-button ${isImporting ? 'is-busy' : ''}`}
                type="button"
                disabled={isImporting}
                onClick={() => importInputRef.current?.click()}
              >
                <span>＋</span> {isImporting ? 'Importing…' : 'Import EPUB'}
              </button>
              <input
                ref={importInputRef}
                className="visually-hidden-input"
                type="file"
                accept=".epub,application/epub+zip"
                disabled={isImporting}
                onChange={handleImport}
              />
            </div>
          </section>

          {!supportsDirectoryPicker && (
            <p className="compatibility-note">
              Folder linking is unavailable in this browser. Import EPUB still works.
            </p>
          )}

          {offlineStatus && <p className="compatibility-note" role="status">{offlineStatus}</p>}
          <details className="library-sync">
            <summary>Sync with Mac{syncKey && syncStatus ? ` · ${syncStatus}` : ''}</summary>
            {syncKey ? <button type="button" onClick={() => changeSyncKey('')}>Disconnect sync</button> : (
              <form onSubmit={event => { event.preventDefault(); changeSyncKey(keyInput.trim()) }}>
                <label>Sync key <input type="password" value={keyInput} onChange={event => setKeyInput(event.target.value)} autoComplete="off" /></label>
                <button type="submit">Connect</button>
                {syncStatus && <p role="status">{syncStatus}</p>}
              </form>
            )}
          </details>
          {message && <p className="status-message" aria-live="polite">{message}</p>}

          {isLoading ? (
            <p className="empty-library">Loading your library…</p>
          ) : filteredBooks.length === 0 ? (
            <div className="empty-library">
              <div className="empty-book">EPUB</div>
              <h2>{availableBooks.length === 0 ? 'Your library is empty' : 'No books found'}</h2>
              <p>
                {availableBooks.length === 0
                  ? 'Open a folder or import your first EPUB to start reading.'
                  : 'Try a different search.'}
              </p>
            </div>
          ) : (
            <section className="book-grid">
              {filteredBooks.map((book) => {
                const local = 'source' in book ? book : undefined
                return (
                <article className="book-card" key={book.id}>
                  <button
                    className="book-open-button"
                    type="button"
                    aria-label={`Open ${book.title}`}
                    disabled={openingBookId === book.id || managingBookId === book.id}
                    onClick={() => handleOpenBook(book)}
                  >
                  <span className="book-cover">
                    <span className="file-type">EPUB</span>
                    <BookCover title={book.title} cover={local?.cover} />
                  </span>
                  <span className="card-title">{book.title}</span>
                  <span className={`source-badge ${local?.source ?? 'synced'}`}>
                    {local?.source === 'linked' ? 'Linked folder' : local ? 'Imported' : 'Download to read'}
                  </span>
                  <span className="card-date">
                    {local?.progress
                      ? local.progress.sectionIndex < 0 ? 'Continue reading' : `Continue · Chapter ${local.progress.sectionIndex + 1} of ${local.progress.sectionTotal}`
                      : local?.source === 'linked'
                        ? local.relativePath
                        : `Added ${new Date(book.addedAt).toLocaleDateString()}`}
                  </span>
                  </button>
                  <button
                    className="book-manage-button"
                    type="button"
                    disabled={managingBookId === book.id}
                    onClick={() => void handleRemoveBook(book)}
                  >
                    {local?.source === 'linked' ? 'Unlink folder' : 'Remove book'}
                  </button>
                </article>
                )
              })}
            </section>
          )}
        </main>
      )}
    </div>
  )
}

export default App
