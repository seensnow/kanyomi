import { useEffect, useState } from 'react'

type BookCoverProps = {
  title: string
  cover?: Blob
}

function BookCover(props: BookCoverProps) {
  const [coverUrl, setCoverUrl] = useState('')

  useEffect(() => {
    if (!props.cover) {
      return
    }

    const reader = new FileReader()

    reader.onload = () => {
      if (typeof reader.result === 'string') {
        setCoverUrl(reader.result)
      }
    }

    reader.readAsDataURL(props.cover)

    return () => reader.abort()
  }, [props.cover])

  if (coverUrl) {
    return <img className="book-cover-image" src={coverUrl} alt="" />
  }

  return <span className="cover-title">{props.title}</span>
}

export default BookCover
