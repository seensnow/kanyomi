import ePub from '@likecoin/epub-ts'

export type EpubDetails = {
  title: string
  cover?: Blob
}

export async function readEpubDetails(file: File): Promise<EpubDetails> {
  const data = await file.arrayBuffer()
  const book = ePub(data)

  try {
    await book.opened

    const title = book.packaging.metadata.title?.trim()
      || file.name.replace(/\.epub$/i, '')
    const coverUrl = await book.coverUrl()

    if (!coverUrl) {
      return { title }
    }

    const response = await fetch(coverUrl)

    if (!response.ok) {
      return { title }
    }

    return {
      title,
      cover: await response.blob(),
    }
  } finally {
    book.destroy()
  }
}
