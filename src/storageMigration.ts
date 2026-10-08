// Legacy names are confined to upgrade compatibility; all new writes use kanyomi.
export function readPreference(key: string): string | null {
  const current = localStorage.getItem(key)
  if (current !== null) return current
  const legacy = localStorage.getItem(key.replace(/^kanyomi-/, 'simple-reader-'))
  if (legacy !== null) {
    try { localStorage.setItem(key, legacy) } catch { /* Still use the old value if storage is full. */ }
  }
  return legacy
}

const stores = ['books', 'directories', 'dictionaryTerms', 'dictionaries']
let migration: Promise<void> | undefined

function openLegacy(): Promise<IDBDatabase | null> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('simple-reader')
    let absent = false
    request.onupgradeneeded = () => { absent = true; request.transaction!.abort() }
    request.onerror = () => absent ? resolve(null) : reject(request.error)
    request.onsuccess = () => resolve(request.result)
  })
}

function openCurrent(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('kanyomi', 4)
    request.onupgradeneeded = () => {
      const db = request.result
      for (const name of stores) {
        if (!db.objectStoreNames.contains(name)) {
          const store = db.createObjectStore(name, { keyPath: 'id' })
          if (name === 'dictionaryTerms') {
            for (const key of ['expression', 'reading', 'dictionaryId']) store.createIndex(key, key)
          }
        }
      }
      if (!db.objectStoreNames.contains('migration')) db.createObjectStore('migration')
    }
    request.onerror = () => reject(request.error)
    request.onblocked = () => reject(new Error('Close other Kanyomi tabs to upgrade browser storage.'))
    request.onsuccess = () => resolve(request.result)
  })
}

async function migrate() {
  const current = await openCurrent()
  let legacy: IDBDatabase | null = null
  try {
    const completed = await new Promise((resolve, reject) => {
      const request = current.transaction('migration').objectStore('migration').get('complete')
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
    if (completed) return
    legacy = await openLegacy()
    const rows = legacy ? await Promise.all(stores.map(name => new Promise<unknown[]>((resolve, reject) => {
      if (!legacy!.objectStoreNames.contains(name)) { resolve([]); return }
      const request = legacy!.transaction(name).objectStore(name).getAll()
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    }))) : stores.map(() => [])
    // The marker and all records commit together. Keep the old database intact.
    await new Promise<void>((resolve, reject) => {
      const tx = current.transaction([...stores, 'migration'], 'readwrite')
      const marker = tx.objectStore('migration').get('complete')
      marker.onsuccess = () => {
        if (marker.result) return
        stores.forEach((name, index) => rows[index].forEach(row => tx.objectStore(name).put(row)))
        tx.objectStore('migration').put(true, 'complete')
      }
      tx.oncomplete = () => resolve()
      tx.onerror = tx.onabort = () => reject(tx.error)
    })
  } finally { legacy?.close(); current.close() }
}

export function migrateDatabase(): Promise<void> {
  migration ??= migrate().catch(error => { migration = undefined; throw error })
  return migration
}
