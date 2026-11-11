import { createHash, timingSafeEqual, randomUUID } from 'node:crypto'
import { createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from 'node:fs'
import { rm } from 'node:fs/promises'
import { createServer } from 'node:http'
import { basename, extname, join, resolve } from 'node:path'
import { Transform } from 'node:stream'
import { pipeline } from 'node:stream/promises'
import { fileURLToPath } from 'node:url'

const api = '/api/sync/books'
const maxBookBytes = 128 * 1024 * 1024
const mime = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.webmanifest': 'application/manifest+json',
}

class RequestError extends Error {
  constructor(status, message) {
    super(message)
    this.status = status
  }
}

function reply(response, status, value) {
  if (value === undefined) { response.writeHead(status).end(); return }
  response.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(value))
}

async function readRecord(request) {
  const chunks = []
  let size = 0
  for await (const chunk of request.iterator({ destroyOnReturn: false })) {
    size += chunk.length
    if (size > 16 * 1024) throw new RequestError(413, 'Sync record too large')
    chunks.push(chunk)
  }
  let record
  try { record = JSON.parse(Buffer.concat(chunks)) } catch { throw new RequestError(400, 'Invalid sync record') }
  const validTime = value => Number.isSafeInteger(value) && value > 0 && value <= Date.now() + 24 * 60 * 60 * 1000
  if (!record || typeof record.title !== 'string' || !record.title.trim() || record.title.length > 1024 ||
      !validTime(record.addedAt) || (record.removedAt != null && record.removedAt !== 0 && !validTime(record.removedAt))) {
    throw new RequestError(400, 'Invalid book information')
  }
  const { position } = record
  if (position != null && (typeof position.path !== 'string' || !position.path || position.path.length > 2048 ||
      !Number.isSafeInteger(position.offset) || position.offset < 0 || position.offset > 100_000_000 ||
      !validTime(position.updatedAt) || (position.cfi != null && (typeof position.cfi !== 'string' || position.cfi.length > 4096)))) {
    throw new RequestError(400, 'Invalid reading position')
  }
  return { title: record.title, addedAt: record.addedAt, removedAt: record.removedAt ?? 0,
    ...(position && { position: { path: position.path, offset: position.offset, updatedAt: position.updatedAt, cfi: position.cfi } }) }
}

async function upload(request, path, id) {
  if (existsSync(path)) { request.resume(); return }
  const temp = `${path}.${randomUUID()}.part`
  const hash = createHash('sha256')
  let size = 0
  try {
    const output = createWriteStream(temp, { flags: 'wx', mode: 0o600 })
    await pipeline(request, new Transform({ transform(chunk, _encoding, callback) {
      size += chunk.length
      if (size > maxBookBytes) return callback(new RequestError(413, 'EPUB exceeds 128 MiB'))
      hash.update(chunk)
      callback(null, chunk)
    } }), output)
    if (!size || hash.digest('hex') !== id) throw new RequestError(422, 'EPUB checksum mismatch')
    renameSync(temp, path)
  } finally {
    await rm(temp, { force: true })
  }
}

export function createSyncServer({ token, directory, dist }) {
  if (!/^[a-f0-9]{64}$/.test(token ?? '')) throw new Error('KANYOMI_SYNC_TOKEN must be 64 lowercase hexadecimal characters')
  if (!directory) throw new Error('Set KANYOMI_SYNC_DIR to a private directory for EPUBs and sync records')
  const root = resolve(directory)
  const publicRoot = resolve(dist)
  if (root === publicRoot || root.startsWith(`${publicRoot}/`)) throw new Error('Keep sync storage outside the public web root')
  mkdirSync(root, { recursive: true, mode: 0o700 })
  const indexFile = join(root, 'books.json')
  const records = new Map(existsSync(indexFile) ? JSON.parse(readFileSync(indexFile, 'utf8')).map(book => [book.id, book]) : [])
  const secret = Buffer.from(`Bearer ${token}`)

  return createServer(async (request, response) => {
    response.setHeader('X-Content-Type-Options', 'nosniff')
    try {
      const path = new URL(request.url, 'http://localhost').pathname
      if (path === api || path.startsWith(`${api}/`)) {
        response.setHeader('Cache-Control', 'no-store')
        const auth = Buffer.from(request.headers.authorization ?? '')
        if (auth.length !== secret.length || !timingSafeEqual(secret, auth)) return reply(response, 401, { error: 'Sync key rejected' })
        if (path === api && request.method === 'GET') return reply(response, 200, [...records.values()])

        const match = /^\/api\/sync\/books\/([a-f0-9]{64})(\/state)?$/.exec(path)
        if (!match) return reply(response, 404)
        const [, id, statePath] = match
        const file = join(root, `${id}.epub`)
        if (!statePath && request.method === 'PUT') {
          if (Number(request.headers['content-length']) > maxBookBytes) throw new RequestError(413, 'EPUB exceeds 128 MiB')
          await upload(request, file, id)
          return reply(response, 204)
        }
        if (statePath && request.method === 'PUT') {
          const incoming = await readRecord(request)
          const previous = records.get(id)
          const latest = !previous || incoming.addedAt > previous.addedAt ? incoming : previous
          const removedAt = Math.max(incoming.removedAt, previous?.removedAt ?? 0)
          const position = (incoming.position?.updatedAt ?? 0) > (previous?.position?.updatedAt ?? 0) ? incoming.position : previous?.position
          const merged = { id, title: latest.title, addedAt: latest.addedAt, removedAt, position }
          if (merged.addedAt > removedAt && !existsSync(file)) throw new RequestError(409, 'Upload the EPUB before publishing its sync record')
          if (JSON.stringify(merged) !== JSON.stringify(previous)) {
            const next = new Map(records).set(id, merged)
            const temporary = `${indexFile}.part`
            writeFileSync(temporary, JSON.stringify([...next.values()]), { mode: 0o600 })
            renameSync(temporary, indexFile)
            records.set(id, merged)
          }
          return reply(response, 200, merged)
        }
        const book = records.get(id)
        if (!statePath && request.method === 'GET' && book && book.addedAt > book.removedAt && existsSync(file)) {
          response.writeHead(200, { 'Content-Type': 'application/epub+zip', 'Content-Length': statSync(file).size })
          await pipeline(createReadStream(file), response)
          return
        }
        return reply(response, 404)
      }

      if (request.method !== 'GET' && request.method !== 'HEAD') return reply(response, 405)
      const name = path === '/' ? 'index.html' : path.slice(1)
      if (name !== basename(name) && !/^assets\/[\w.-]+$/.test(name)) return reply(response, 404)
      const contentType = mime[extname(name)]
      const file = join(publicRoot, name)
      if (!contentType || !existsSync(file)) return reply(response, 404)
      response.writeHead(200, {
        'Content-Type': contentType,
        'Cache-Control': name.startsWith('assets/') ? 'public, max-age=31536000, immutable' : 'no-cache',
        'Content-Length': statSync(file).size,
      })
      if (request.method === 'HEAD') response.end()
      else await pipeline(createReadStream(file), response)
    } catch (error) {
      if (response.headersSent || response.destroyed) { response.destroy(); return }
      if (!(error instanceof RequestError)) console.error(error)
      reply(response, error instanceof RequestError ? error.status : 500,
        { error: error instanceof RequestError ? error.message : 'Kanyomi sync server error' })
    }
  })
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const { KANYOMI_SYNC_TOKEN, KANYOMI_SYNC_DIR, KANYOMI_SYNC_HOST = '127.0.0.1', PORT = '4173' } = process.env
  createSyncServer({ token: KANYOMI_SYNC_TOKEN, directory: KANYOMI_SYNC_DIR, dist: 'dist' })
    .listen(Number(PORT), KANYOMI_SYNC_HOST, () => console.log(`Kanyomi listening on ${KANYOMI_SYNC_HOST}:${PORT}`))
}
