import { useState } from 'react'
import BookButton from './BookButton'
import Reader from './Reader'

const books = [
  {
    title: 'The Little Prince',
    content: 'A young traveler meets a mysterious prince from a distant asteroid.',
  },
  {
    title: 'Alice in Wonderland',
    content: 'Alice follows a white rabbit into a strange and surprising world.',
  },
]

function App() {
  const [selectedBook, setSelectedBook] = useState({
    title: 'No book selected',
    content: 'Choose a book and start reading.',
  })

  return (
    <div className="app">
      <aside>
        <h2>Bookshelf</h2>
        <BookButton
          title={books[0].title}
          isSelected={selectedBook.title === books[0].title}
          onClick={() => setSelectedBook(books[0])}
        />
        <BookButton
          title={books[1].title}
          isSelected={selectedBook.title === books[1].title}
          onClick={() => setSelectedBook(books[1])}
        />
      </aside>

      <Reader
        title={selectedBook.title}
        content={selectedBook.content}
      />
    </div>
  )
}

export default App
