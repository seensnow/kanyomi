import { migrateDatabase } from './storageMigration'
type BookDetails = {
  title: string
  cover?: Blob
}

export type ReadingProgress = {
  cfi: string
  sectionIndex: number
  sectionTotal: number
  updatedAt: number
}

type SavedBookBase = BookDetails & {
  id: string
  addedAt: number
  progress?: ReadingProgress
}

export type ImportedBook = SavedBookBase & {
  source: 'imported'
  file: Blob
}

export type LinkedBook = SavedBookBase & {
  source: 'linked'
  fileHandle: FileSystemFileHandle
  directoryId: string
  relativePath: string
}

export type SavedBook = ImportedBook | LinkedBook

export type SavedDirectory = {
  id: string
  name: string
  handle: FileSystemDirectoryHandle
  addedAt: number
}

type LegacyBook = Omit<ImportedBook, 'source'>

const databaseName = 'kanyomi'
const booksStoreName = 'books'
const directoriesStoreName = 'directories'

async function openDatabase() {
  await migrateDatabase()
  return new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(databaseName, 4)

    request.onupgradeneeded = () => {
      const database = request.result

      if (!database.objectStoreNames.contains(booksStoreName)) {
        database.createObjectStore(booksStoreName, { keyPath: 'id' })
      }

      if (!database.objectStoreNames.contains(directoriesStoreName)) {
        database.createObjectStore(directoriesStoreName, { keyPath: 'id' })
      }

      if (!database.objectStoreNames.contains('dictionaryTerms')) {
        const terms = database.createObjectStore('dictionaryTerms', { keyPath: 'id' })
        terms.createIndex('expression', 'expression', { unique: false })
        terms.createIndex('reading', 'reading', { unique: false })
        terms.createIndex('dictionaryId', 'dictionaryId', { unique: false })
      }

      if (!database.objectStoreNames.contains('dictionaries')) {
        database.createObjectStore('dictionaries', { keyPath: 'id' })
      }
    }

    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

function normalizeBook(book: SavedBook | LegacyBook): SavedBook {
  if ('source' in book) {
    return book
  }

  return { ...book, source: 'imported' }
}

export async function getSavedBooks() {
  const database = await openDatabase()

  return new Promise<SavedBook[]>((resolve, reject) => {
    const transaction = database.transaction(booksStoreName, 'readonly')
    const request = transaction.objectStore(booksStoreName).getAll()

    request.onsuccess = () => {
      const books = (request.result as Array<SavedBook | LegacyBook>)
        .map(normalizeBook)
        .sort((first, second) => second.addedAt - first.addedAt)
      resolve(books)
    }
    request.onerror = () => reject(request.error)
    transaction.oncomplete = () => database.close()
  })
}

export async function getSavedDirectories() {
  const database = await openDatabase()

  return new Promise<SavedDirectory[]>((resolve, reject) => {
    const transaction = database.transaction(directoriesStoreName, 'readonly')
    const request = transaction.objectStore(directoriesStoreName).getAll()

    request.onsuccess = () => resolve(request.result as SavedDirectory[])
    request.onerror = () => reject(request.error)
    transaction.oncomplete = () => database.close()
  })
}

export async function saveBook(file: File, title: string, cover?: Blob) {
  const database = await openDatabase()
  const savedBook: ImportedBook = {
    id: `${file.name}-${file.size}-${file.lastModified}`,
    source: 'imported',
    title,
    file,
    cover,
    addedAt: Date.now(),
  }

  return new Promise<ImportedBook>((resolve, reject) => {
    const transaction = database.transaction(booksStoreName, 'readwrite')
    const store = transaction.objectStore(booksStoreName)
    const existingRequest = store.get(savedBook.id)

    existingRequest.onsuccess = () => {
      const existing = existingRequest.result as SavedBook | undefined
      if (existing?.progress) savedBook.progress = existing.progress
      store.put(savedBook)
    }

    transaction.oncomplete = () => {
      database.close()
      resolve(savedBook)
    }
    transaction.onerror = () => { database.close(); reject(transaction.error) }
    transaction.onabort = () => { database.close(); reject(transaction.error) }
  })
}

export async function saveReadingProgress(id: string, progress: ReadingProgress) {
  const database = await openDatabase()

  return new Promise<void>((resolve, reject) => {
    const transaction = database.transaction(booksStoreName, 'readwrite')
    const store = transaction.objectStore(booksStoreName)
    const request = store.get(id)

    request.onsuccess = () => {
      const book = request.result as SavedBook | undefined
      if (book && (!book.progress || book.progress.updatedAt <= progress.updatedAt)) {
        store.put({ ...book, progress })
      }
    }
    transaction.oncomplete = () => { database.close(); resolve() }
    transaction.onerror = () => { database.close(); reject(transaction.error) }
    transaction.onabort = () => { database.close(); reject(transaction.error) }
  })
}

export async function removeImportedBook(id: string) {
  const database = await openDatabase()

  return new Promise<void>((resolve, reject) => {
    const transaction = database.transaction(booksStoreName, 'readwrite')
    transaction.objectStore(booksStoreName).delete(id)
    transaction.oncomplete = () => { database.close(); resolve() }
    transaction.onerror = () => { database.close(); reject(transaction.error) }
    transaction.onabort = () => { database.close(); reject(transaction.error) }
  })
}

export async function unlinkDirectory(directoryId: string) {
  const database = await openDatabase()

  return new Promise<void>((resolve, reject) => {
    const transaction = database.transaction([booksStoreName, directoriesStoreName], 'readwrite')
    const booksStore = transaction.objectStore(booksStoreName)
    const request = booksStore.getAll()
    request.onsuccess = () => {
      for (const book of request.result as SavedBook[]) {
        if (book.source === 'linked' && book.directoryId === directoryId) booksStore.delete(book.id)
      }
      transaction.objectStore(directoriesStoreName).delete(directoryId)
    }
    transaction.oncomplete = () => { database.close(); resolve() }
    transaction.onerror = () => { database.close(); reject(transaction.error) }
    transaction.onabort = () => { database.close(); reject(transaction.error) }
  })
}

export async function saveLinkedLibrary(
  directory: SavedDirectory,
  books: LinkedBook[],
) {
  const database = await openDatabase()

  return new Promise<void>((resolve, reject) => {
    const transaction = database.transaction(
      [booksStoreName, directoriesStoreName],
      'readwrite',
    )
    const booksStore = transaction.objectStore(booksStoreName)
    const existingRequest = booksStore.getAll()

    transaction.objectStore(directoriesStoreName).put(directory)

    existingRequest.onsuccess = () => {
      for (const existingBook of existingRequest.result as SavedBook[]) {
        if (
          existingBook.source === 'linked'
          && existingBook.directoryId === directory.id
        ) {
          booksStore.delete(existingBook.id)
        }
      }

      for (const book of books) {
        const previous = (existingRequest.result as SavedBook[]).find((existing) => existing.id === book.id)
        booksStore.put({ ...book, progress: previous?.progress })
      }
    }

    transaction.oncomplete = () => {
      database.close()
      resolve()
    }
    transaction.onerror = () => reject(transaction.error)
    transaction.onabort = () => reject(transaction.error)
  })
}
