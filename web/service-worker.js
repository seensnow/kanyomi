const prefix = 'kanyomi-app-'
const cacheName = prefix + VERSION
const scope = new URL(self.registration.scope)
const files = new Set(FILES.map((file) => new URL(file, scope).href))
const index = new URL('index.html', scope).href

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(cacheName).then((cache) => cache.addAll(
    [...files].map((url) => new Request(url, { cache: 'reload' })),
  )))
})

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(prefix) && name !== cacheName) await caches.delete(name)
    }
    await self.clients.claim()
  })())
})

self.addEventListener('fetch', (event) => {
  const { request } = event
  if (request.method !== 'GET') return
  const url = new URL(request.url)
  const home = request.mode === 'navigate' && url.origin === scope.origin &&
    (url.pathname === scope.pathname || url.pathname === new URL(index).pathname)
  if (!home && !files.has(request.url)) return
  event.respondWith((async () => {
    const cache = await caches.open(cacheName)
    const key = home ? index : request.url
    return await cache.match(key) ?? fetch(request)
  })())
})
