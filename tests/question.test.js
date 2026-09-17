import assert from 'node:assert/strict'
import { test } from 'node:test'

import { blankQuestion, fromRow, problemWith, toRow } from '../src/lib/question.js'

test('a blank question says what it needs first', () => {
  assert.equal(problemWith(blankQuestion('choice')), 'Add the question')
})

test('choices may trail off blank but may not have a gap', () => {
  const q = { ...blankQuestion('choice'), text: 'Pick' }
  assert.equal(problemWith({ ...q, choices: ['a', '', '', ''] }), 'Needs at least two choices')
  assert.equal(problemWith({ ...q, choices: ['a', 'b', '', ''] }), null)
  assert.equal(problemWith({ ...q, choices: ['a', '', 'c', ''] }), 'Fill the choices in order, no gaps')
})

test('the correct choice must be one that exists', () => {
  const q = { ...blankQuestion('choice'), text: 'Pick', choices: ['a', 'b', '', ''] }
  assert.equal(problemWith({ ...q, correctIndex: 3 }), 'Mark the correct choice')
})

test('a typed question needs something to match against', () => {
  const q = { ...blankQuestion('text'), text: 'Tag?' }
  assert.equal(problemWith({ ...q, accepted: ['  '] }), 'Add at least one accepted answer')
  assert.equal(problemWith({ ...q, accepted: ['<ol>'] }), null)
})

test('saving drops the blank choices and the fields another kind would use', () => {
  const q = { ...blankQuestion('choice'), text: ' Pick ', choices: ['a', 'b', '', ''], correctIndex: 1 }
  assert.deepEqual(toRow(q, 'quiz', 3), {
    quiz_id: 'quiz', position: 3, kind: 'choice', text: 'Pick', choices: ['a', 'b'],
    correct_index: 1, accepted: null, seconds: null, recall_seconds: 8,
    blurt_enabled: true, image_path: null,
  })
  const typed = { ...blankQuestion('text'), text: 'Tag?', accepted: ['<ol>', ' '] }
  const row = toRow(typed, 'quiz', 0)
  assert.equal(row.choices, null)
  assert.equal(row.correct_index, null)
  assert.deepEqual(row.accepted, ['<ol>'])
})

test('blurting is on by default, except where it would be the same act twice', () => {
  assert.equal(blankQuestion('choice').blurtEnabled, true)
  assert.equal(blankQuestion('truefalse').blurtEnabled, true)
  // Typed: produce it from memory, then produce it again. Only a race.
  assert.equal(blankQuestion('text').blurtEnabled, false)
})

test('the blurt setting survives a round trip through a row', () => {
  const off = { ...blankQuestion('choice'), text: 'Pick', choices: ['a', 'b', '', ''], blurtEnabled: false }
  assert.equal(toRow(off, 'quiz', 0).blurt_enabled, false)
  assert.equal(fromRow({ ...toRow(off, 'quiz', 0), id: 'x' }).blurtEnabled, false)
  // A row written before the column existed reads as on, which is how it behaved.
  assert.equal(fromRow({ id: 'x', kind: 'choice', text: 'Pick', choices: ['a'], correct_index: 0 }).blurtEnabled, true)
})

test('a saved row comes back with four choice boxes to type into', () => {
  const back = fromRow({ id: 'x', kind: 'choice', text: 'Pick', choices: ['a', 'b'], correct_index: 0,
    accepted: null, seconds: 15, recall_seconds: 8, image_path: null })
  assert.deepEqual(back.choices, ['a', 'b', '', ''])
  assert.equal(back.key, 'x')
})
