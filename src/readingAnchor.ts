import type { Contents, Rendition } from '@likecoin/epub-ts'

export type ReadingAnchor = { path: string; offset: number }

const excluded = 'rt,rp,script,style,head,noscript,[aria-hidden="true"]'
const clean = (text: string) => text.replace(/\s/g, '')

function chapterPath(rendition: Rendition, index: number) {
  const url = rendition.book.spine.get(index)?.canonical
  if (!url) return ''
  const path = new URL(url, location.origin).pathname.slice(1)
  try { return decodeURIComponent(path) } catch { return path }
}

function textNodes(document: Document) {
  return document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => node.parentElement?.closest(excluded) || !clean(node.textContent ?? '')
      ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
  })
}

export function anchorFromCfi(rendition: Rendition, cfi: string, index: number): ReadingAnchor | undefined {
  const contents = rendition.getContents().find(item => item.sectionIndex === index)
  const range = contents?.range(cfi)
  return range && anchorFromRange(rendition, range, index)
}

export function anchorFromRange(rendition: Rendition, range: Range, index: number): ReadingAnchor | undefined {
  const path = chapterPath(rendition, index)
  if (!path) return
  const document = range.startContainer.ownerDocument
  if (!document?.body) return

  let offset = 0
  const walker = textNodes(document)
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const text = node.textContent ?? ''
    if (node === range.startContainer) return { path, offset: offset + clean(text.slice(0, range.startOffset)).length }
    if (range.comparePoint(node, 0) >= 0) break
    offset += clean(text).length
  }
  return { path, offset }
}

function cfiAt(contents: Contents, offset: number) {
  const walker = textNodes(contents.document)
  const range = contents.document.createRange()
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const text = node.textContent ?? ''
    for (let index = 0; index < text.length; index++) {
      if (/\s/.test(text[index])) continue
      if (offset-- === 0) {
        range.setStart(node, index)
        range.collapse(true)
        return contents.cfiFromRange(range)
      }
    }
  }
}

export async function displayAnchor(rendition: Rendition, anchor: ReadingAnchor) {
  for (let index = 0; index < rendition.book.spine.length; index++) {
    if (chapterPath(rendition, index) !== anchor.path) continue
    await rendition.display(index)
    const contents = rendition.getContents().find(item => item.sectionIndex === index)
    const cfi = contents && cfiAt(contents, anchor.offset)
    if (cfi && anchor.offset > 0) await rendition.display(cfi)
    return true
  }
  return false
}
