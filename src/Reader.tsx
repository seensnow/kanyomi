type ReaderProps = {
  title: string
  content: string
}

function Reader(props: ReaderProps) {
  return (
    <main>
      <div className="reader-content">
        <h1>Simple Reader</h1>
        <h2>{props.title}</h2>
        <p>{props.content}</p>
      </div>
    </main>
  )
}

export default Reader
