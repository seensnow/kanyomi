type BookButtonProps = {
  title: string
  onClick: () => void
  isSelected: boolean
}

function BookButton(props: BookButtonProps) {
  return (
    <button
      type="button"
      className={props.isSelected ? 'selected' : ''}
      onClick={props.onClick}
    >
      {props.title}
    </button>
  )
}

export default BookButton
