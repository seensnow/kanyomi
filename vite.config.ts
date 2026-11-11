import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { defineConfig } from 'vite'
import type { Plugin } from 'vite'
import react from '@vitejs/plugin-react'

function offlineBuild(): Plugin {
  return {
    name: 'kanyomi-offline',
    apply: 'build',
    enforce: 'post',
    generateBundle: { order: 'post', async handler(_options, bundle) {
      if (!bundle['index.html']) throw new Error('Offline build is missing index.html')
      const publicFiles = ['manifest.webmanifest', 'favicon.svg', 'brand-mark.svg', 'touch-icon.png']
      const paths = [...Object.keys(bundle), ...publicFiles].sort()
      const hash = createHash('sha256')
      const worker = await readFile(new URL('./web/service-worker.js', import.meta.url), 'utf8')
      hash.update(worker)
      for (const path of paths) {
        const entry = bundle[path]
        hash.update(path)
        hash.update(entry?.type === 'chunk' ? entry.code : entry?.source ??
          await readFile(new URL(`./public/${path}`, import.meta.url)))
      }
      this.emitFile({
        type: 'asset',
        fileName: 'service-worker.js',
        source: `const VERSION = '${hash.digest('hex')}';\nconst FILES = ${JSON.stringify(paths)};\n${worker}`,
      })
    } },
  }
}

export default defineConfig({
  plugins: [react(), offlineBuild()],
})
