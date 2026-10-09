export type AnkiSettings = {
  endpoint: string
  apiKey: string
  deck: string
  model: string
  wordField: string
  definitionField: string
}

export const defaultAnkiSettings: AnkiSettings = {
  endpoint: 'http://127.0.0.1:8765',
  apiKey: '',
  deck: 'Default',
  model: 'Basic',
  wordField: 'Front',
  definitionField: 'Back',
}

type AnkiResponse<T> = {
  result: T
  error: string | null
}

async function invoke<T>(settings: AnkiSettings, action: string, params?: object) {
  const response = await fetch(settings.endpoint.replace(/\/$/, ''), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      action,
      version: 6,
      ...(settings.apiKey ? { key: settings.apiKey } : {}),
      ...(params ? { params } : {}),
    }),
  })

  if (!response.ok) {
    throw new Error(`AnkiConnect returned HTTP ${response.status}.`)
  }

  const payload = await response.json() as AnkiResponse<T>

  if (payload.error) {
    throw new Error(payload.error)
  }

  return payload.result
}

export async function testAnkiConnection(settings: AnkiSettings) {
  await invoke<number>(settings, 'version')
  return invoke<string[]>(settings, 'deckNames')
}

function escapeHtml(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}

export async function addWordToAnki(
  settings: AnkiSettings,
  entry: {
    word: string
    reading?: string
    definitions: string[]
    sentence: string
    bookTitle: string
  },
) {
  const front = entry.reading
    ? `${escapeHtml(entry.word)}<br><small>${escapeHtml(entry.reading)}</small>`
    : escapeHtml(entry.word)
  const definitionList = entry.definitions
    .map((definition) => `<li>${escapeHtml(definition)}</li>`)
    .join('')
  const back = [
    `<ol>${definitionList}</ol>`,
    entry.sentence ? `<p>${escapeHtml(entry.sentence)}</p>` : '',
    `<small>From: ${escapeHtml(entry.bookTitle)}</small>`,
  ].join('')

  return invoke<number>(settings, 'addNote', {
    note: {
      deckName: settings.deck,
      modelName: settings.model,
      fields: {
        [settings.wordField]: front,
        [settings.definitionField]: back,
      },
      options: { allowDuplicate: false },
      tags: ['kanyomi'],
    },
  })
}
