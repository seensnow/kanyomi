import test from 'node:test'
import assert from 'node:assert/strict'
import { addWordToAnki, defaultAnkiSettings, testAnkiConnection } from '../src/ankiConnect.ts'

test('AnkiConnect checks the service and deck list before reporting a connection', async (t) => {
  const actions = []
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    const payload = JSON.parse(init.body)
    actions.push(payload.action)
    return new Response(JSON.stringify({
      result: payload.action === 'version' ? 6 : ['Default', 'Japanese'],
      error: null,
    }), { status: 200 })
  })

  assert.deepEqual(await testAnkiConnection(defaultAnkiSettings), ['Default', 'Japanese'])
  assert.deepEqual(actions, ['version', 'deckNames'])
})

test('Anki cards escape book text and send the configured fields', async (t) => {
  let sent
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    sent = JSON.parse(init.body)
    return new Response(JSON.stringify({ result: 42, error: null }), { status: 200 })
  })

  const settings = { ...defaultAnkiSettings, deck: 'Reading', wordField: 'Term', definitionField: 'Meaning' }
  assert.equal(await addWordToAnki(settings, {
    word: '<curious>',
    reading: '& sound',
    definitions: ['A "new" idea'],
    sentence: '<p>Example</p>',
    bookTitle: 'Book & Notes',
  }), 42)
  assert.equal(sent.action, 'addNote')
  assert.equal(sent.params.note.deckName, 'Reading')
  assert.equal(sent.params.note.fields.Term, '&lt;curious&gt;<br><small>&amp; sound</small>')
  assert.match(sent.params.note.fields.Meaning, /&lt;p&gt;Example&lt;\/p&gt;/)
  assert.match(sent.params.note.fields.Meaning, /Book &amp; Notes/)
  assert.equal(sent.params.note.options.allowDuplicate, false)
})

test('AnkiConnect errors reach the user instead of being treated as success', async (t) => {
  t.mock.method(globalThis, 'fetch', async () =>
    new Response(JSON.stringify({ result: null, error: 'Deck not found' }), { status: 200 }))

  await assert.rejects(() => addWordToAnki(defaultAnkiSettings, {
    word: 'word', definitions: ['meaning'], sentence: '', bookTitle: 'Book',
  }), /Deck not found/)
})
