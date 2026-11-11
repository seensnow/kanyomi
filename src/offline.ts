export function watchOfflineAvailability(onChange: (message: string) => void) {
  if (!import.meta.env.PROD) return
  if (!window.isSecureContext || !('serviceWorker' in navigator)) {
    onChange('Offline startup requires HTTPS and a browser with service worker support.')
    return
  }

  const workers = navigator.serviceWorker
  let stopped = false
  let installing: ServiceWorker | null = null
  let registration: ServiceWorkerRegistration | undefined
  const update = () => {
    if (stopped) return
    if (workers.controller) onChange('Ready to open offline')
    else if (installing?.state === 'redundant') onChange('Offline setup failed. Reopen Kanyomi while online to retry.')
    else onChange('Preparing offline access…')
  }
  const watchInstalling = () => {
    installing?.removeEventListener('statechange', update)
    installing = registration?.installing ?? null
    installing?.addEventListener('statechange', update)
    update()
  }
  workers.addEventListener('controllerchange', update)
  update()
  void workers.register('/service-worker.js').then((result) => {
    if (stopped) return
    registration = result
    result.addEventListener('updatefound', watchInstalling)
    watchInstalling()
  }).catch(() => {
    if (!stopped && !workers.controller) onChange('Offline setup failed. Reopen Kanyomi while online to retry.')
  })
  return () => {
    stopped = true
    workers.removeEventListener('controllerchange', update)
    registration?.removeEventListener('updatefound', watchInstalling)
    installing?.removeEventListener('statechange', update)
  }
}

export async function requestPersistentStorage() {
  try {
    await navigator.storage?.persist?.()
  } catch {
    // The browser may decline persistent storage. Local imports still work.
  }
}
