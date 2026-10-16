import test from 'node:test'
import assert from 'node:assert/strict'
import { IDBFactory } from 'fake-indexeddb'
import { readPreference } from '../src/storageMigration.ts'

globalThis.localStorage = undefined
globalThis.indexedDB = undefined

function open(factory, name, version, setup) {
  return new Promise((resolve, reject) => {
    const request = factory.open(name, version)
    request.onupgradeneeded = () => setup?.(request.result)
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}
function complete(tx) {
  return new Promise((resolve, reject) => {
    tx.oncomplete = resolve
    tx.onerror = tx.onabort = () => reject(tx.error)
  })
}
function rows(db, name) {
  return new Promise((resolve, reject) => {
    const request = db.transaction(name).objectStore(name).getAll()
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

test('preferences migrate and respect current values, including when writes fail', t => {
  const values = new Map([['simple-reader-theme', 'light']])
  t.mock.property(globalThis, 'localStorage', { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value) })
  assert.equal(readPreference('kanyomi-theme'), 'light')
  values.set('kanyomi-theme', 'dark')
  assert.equal(readPreference('kanyomi-theme'), 'dark')
  assert.equal(values.get('simple-reader-theme'), 'light')
  values.set('simple-reader-font-size', '20')
  t.mock.method(globalThis.localStorage, 'setItem', () => { throw new Error('quota') })
  assert.equal(readPreference('kanyomi-font-size'), '20')
})

test('database upgrade preserves every store, blobs and legacy records; does not reimport', async t => {
  const factory = new IDBFactory()
  t.mock.property(globalThis, 'indexedDB', factory)
  const names = ['books', 'directories', 'dictionaryTerms', 'dictionaries']
  const old = await open(factory, 'simple-reader', 3, db => names.forEach(name => db.createObjectStore(name, { keyPath: 'id' })))
  const tx = old.transaction(names, 'readwrite')
  for (const name of names) tx.objectStore(name).put({ id: name, value: name, ...(name === 'books' ? { file: new Blob(['epub']) } : {}) })
  await complete(tx)
  const { migrateDatabase } = await import('../src/storageMigration.ts?populated')
  await Promise.all([migrateDatabase(), migrateDatabase()])
  const current = await open(factory, 'kanyomi', 4)
  for (const name of names) {
    const saved = await rows(current, name)
    assert.equal(saved[0].value, name)
    assert.equal((await rows(old, name))[0].value, name)
    if (name === 'books') assert.equal(await saved[0].file.text(), 'epub')
  }
  const remove = current.transaction('books', 'readwrite')
  remove.objectStore('books').delete('books')
  await complete(remove)
  const fresh = await import('../src/storageMigration.ts?relaunch')
  await fresh.migrateDatabase()
  assert.deepEqual(await rows(current, 'books'), [])
  current.close(); old.close()
})

test('fresh installations create only the new database', async t => {
  const factory = new IDBFactory()
  t.mock.property(globalThis, 'indexedDB', factory)
  const { migrateDatabase } = await import('../src/storageMigration.ts?fresh')
  await migrateDatabase()
  assert.deepEqual((await factory.databases()).map(db => db.name), ['kanyomi'])
})
