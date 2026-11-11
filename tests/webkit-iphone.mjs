// Run after npm run build. Set PLAYWRIGHT_MODULE to an installed Playwright entry point.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { once } from 'node:events'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import JSZip from 'jszip'
import { createSyncServer } from '../web/sync-server.mjs'

const { webkit, devices } = await import(process.env.PLAYWRIGHT_MODULE
  ? pathToFileURL(process.env.PLAYWRIGHT_MODULE).href : 'playwright')
const resources = resolve('macOS/Sources/Kanyomi/Resources')
const sample = join(resources, 'Sample.epub')
const title = '雨の日の喫茶店'
const chapterTwo = '夕方、雨は止んでいた。'
const temp = await mkdtemp(join(tmpdir(), 'kanyomi-iphone-'))
const key = randomBytes(32).toString('hex')
const server = createSyncServer({ token: key, directory: join(temp, 'sync'), dist: resolve('dist') })
const listening = once(server, 'listening')
server.listen(0, '127.0.0.1')
await listening
const base = `http://127.0.0.1:${server.address().port}`
const headers = { Authorization: `Bearer ${key}` }
const shelf = async () => (await fetch(`${base}/api/sync/books`, { headers })).json()
const open = (page, title) => page.getByRole('button', { name: `Open ${title}`, exact: true })
const jump = (page, chapter) => page.getByRole('combobox', { name: 'Jump to chapter' }).selectOption({ index: chapter })
const chapterFrame = (page) => page.frameLocator('iframe[srcdoc*="帰り道"]')

async function waitFor(check, message, seconds = 15) {
  const deadline = Date.now() + seconds * 1_000
  do {
    if (await check()) return
    await new Promise(resolve => setTimeout(resolve, 200))
  } while (Date.now() < deadline)
  throw new Error(message)
}

let context
let native
try {
  context = await webkit.launchPersistentContext(join(temp, 'profile'), devices['iPhone 15'])
  let page = await context.newPage()
  await page.goto(base)
  await page.getByText('Ready to open offline').waitFor()
  await page.close()
  await context.setOffline(true)
  page = await context.newPage()
  let onlineLookups = 0
  page.on('request', request => { if (request.url().startsWith('https://jisho.org/')) onlineLookups++ })
  await page.goto(base)
  assert.equal(await page.evaluate(() => navigator.onLine), false)
  await page.getByRole('heading', { name: 'Your books' }).waitFor()
  await page.locator('input[accept*="epub"]').setInputFiles(sample)
  await page.getByRole('heading', { name: title }).waitFor()
  await page.getByRole('button', { name: 'Reading settings' }).click()
  await page.locator('input[accept*="zip"]').setInputFiles(join(resources, 'SampleDictionary.zip'))
  await page.getByText(/terms available offline/).waitFor()
  await jump(page, 2)
  await chapterFrame(page).getByText(chapterTwo, { exact: true }).waitFor()
  await page.evaluate(text => {
    const frame = document.querySelector('iframe[srcdoc*="帰り道"]')
    const documentInBook = frame.contentDocument
    const paragraph = [...documentInBook.querySelectorAll('p')].find(node => node.textContent === text)
    const range = documentInBook.createRange()
    const offset = paragraph.firstChild.data.indexOf('雨')
    range.setStart(paragraph.firstChild, offset)
    range.setEnd(paragraph.firstChild, offset + 1)
    const selection = documentInBook.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
  }, chapterTwo)
  await page.getByText('rain', { exact: true }).waitFor()
  assert.equal(onlineLookups, 0)
  await page.getByRole('button', { name: '← Library' }).click()
  await page.getByText(/Continue · Chapter 2/).waitFor()
  await page.close()
  page = await context.newPage()
  await page.goto(base)
  await open(page, title).click()
  await chapterFrame(page).getByText(chapterTwo, { exact: true }).waitFor()
  console.log('WebKit iPhone profile passed offline startup, local EPUB and dictionary import, chapter navigation, lookup and reopening.')

  if (!process.argv.includes('--sync')) process.exitCode = 0
  else {
    await context.close()
    context = await webkit.launchPersistentContext(join(temp, 'sync-profile'), devices['iPhone 15'])
    page = await context.newPage()
    const nativeProcess = spawn('./macOS/scripts/swift-build.sh', ['test', '--filter', 'LibrarySyncTests'], {
      stdio: 'inherit', env: { ...process.env, KANYOMI_SYNC_TEST_URL: base, KANYOMI_SYNC_TEST_KEY: key },
    })
    native = nativeProcess
    const nativeExit = once(nativeProcess, 'exit')
    await waitFor(async () => (await shelf()).some(book => book.title === title && book.position?.offset === 12),
      'The native reader did not upload its book and position', 75)
    assert.equal((await fetch(`${base}/api/sync/books`)).status, 401)
    await page.goto(base)
    await page.getByText('Ready to open offline').waitFor()
    await page.locator('.library-sync summary').click()
    await page.getByLabel('Sync key').fill(key)
    await page.getByRole('button', { name: 'Connect', exact: true }).click()
    await open(page, title).click()
    await chapterFrame(page).getByText(chapterTwo, { exact: true }).waitFor()

    await context.setOffline(true)
    await jump(page, 1)
    await page.getByRole('button', { name: '← Library' }).click()
    await page.getByText(/Continue · Chapter 1/).waitFor()
    const zip = await JSZip.loadAsync(await readFile(sample))
    const opf = await zip.file('OEBPS/book.opf').async('string')
    zip.file('OEBPS/book.opf', opf.replace(title, 'iPhone Sync Fixture'))
    await page.locator('input[accept*="epub"]').setInputFiles({
      name: 'iPhone fixture.epub', mimeType: 'application/epub+zip', buffer: await zip.generateAsync({ type: 'nodebuffer' }),
    })
    await page.getByRole('heading', { name: 'iPhone Sync Fixture' }).waitFor()
    const offlineShelf = await shelf()
    assert.equal(offlineShelf.length, 1)
    assert.equal(offlineShelf[0].position.path, 'OEBPS/chapter2.xhtml')

    await page.close()
    page = await context.newPage()
    await page.goto(base)
    await open(page, 'iPhone Sync Fixture').waitFor()
    await context.setOffline(false)
    await waitFor(async () => {
      const records = await shelf()
      return records.some(book => book.title === 'iPhone Sync Fixture') &&
        records.find(book => book.title === title)?.position?.path === 'OEBPS/chapter1.xhtml'
    }, 'The iPhone profile did not upload its book and position on reconnection')
    const [code] = await nativeExit
    assert.equal(code, 0)
    const synced = (await shelf()).find(book => book.title === title)
    const stale = { ...synced, position: offlineShelf[0].position }
    const response = await fetch(`${base}/api/sync/books/${synced.id}/state`, {
      method: 'PUT', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify(stale),
    })
    assert.equal(response.status, 200)
    assert.deepEqual((await response.json()).position, synced.position)
    console.log('Mac and iPhone-profile WebKit passed bidirectional EPUB and position sync, offline writes surviving reopen, and upload on reconnection.')
  }
} finally {
  if (native?.exitCode == null) native?.kill()
  await context?.close()
  await new Promise(resolve => server.close(resolve))
  await rm(temp, { recursive: true, force: true })
}
