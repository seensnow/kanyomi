import ePub from '@likecoin/epub-ts'

export type EpubDetails = {
  title: string
  cover?: Blob
}

export async function readEpubDetails(file: File, data?: ArrayBuffer): Promise<EpubDetails> {
  const book = ePub(data ?? await file.arrayBuffer())

  try {
    await book.opened

    const title = book.packaging.metadata.title?.trim()
      || file.name.replace(/\.epub$/i, '')
    const cover = book.cover ? await book.archive?.getBlob(book.cover) : undefined
    return { title, cover }
  } finally {
    book.destroy()
  }
}
