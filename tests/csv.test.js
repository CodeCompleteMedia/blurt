import assert from 'node:assert/strict'
import { test } from 'node:test'

import { parseDelimited, questionsFromText } from '../src/lib/csv.js'

test('a range pasted from a spreadsheet arrives tab-separated', () => {
  const rows = parseDelimited('Capital of France?\tParis\tLyon\tNice\t\tA\t15\n')
  assert.deepEqual(rows, [['Capital of France?', 'Paris', 'Lyon', 'Nice', '', 'A', '15']])
})

test('quoted cells keep their commas, quotes and line breaks', () => {
  const rows = parseDelimited('"What does ""DRY"" mean, exactly?","Don\'t\nrepeat"\n')
  assert.deepEqual(rows, [['What does "DRY" mean, exactly?', "Don't\nrepeat"]])
})

test('semicolons, a byte order mark and Windows line endings', () => {
  assert.deepEqual(parseDelimited('﻿a;b\r\nc;d\r\n'), [['a', 'b'], ['c', 'd']])
})

test('no header: columns are read in the order a teacher would type them', () => {
  const { questions, problems } = questionsFromText('2+2?,3,4,5,,B,10')
  assert.equal(problems.length, 0)
  assert.deepEqual(questions[0], {
    kind: 'choice', text: '2+2?', seconds: 10, recallSeconds: 8, blurtEnabled: true,
    choices: ['3', '4', '5'], correctIndex: 1, accepted: [],
  })
})

test('a header row can put the columns anywhere', () => {
  const { questions } = questionsFromText('Correct,Question,B,A\nb,Pick,no,yes')
  assert.deepEqual(questions[0].choices, ['yes', 'no'])
  assert.equal(questions[0].correctIndex, 1)
})

test('the correct answer can be a letter, a number, or the answer itself', () => {
  for (const key of ['c', 'C', '3', 'Nice']) {
    const { questions } = questionsFromText(`Where?,Paris,Lyon,Nice,,${key}`)
    assert.equal(questions[0].correctIndex, 2, `correct given as "${key}"`)
  }
})

test('the kind is inferred from what the row contains', () => {
  const { questions } = questionsFromText(
    ['question,a,b,correct', 'Pick one,x,y,a', 'The sky is blue,,,TRUE', 'Tag for a list?,,,<ol>|ordered list'].join('\n'),
  )
  assert.deepEqual(questions.map((q) => q.kind), ['choice', 'truefalse', 'text'])
  assert.equal(questions[1].correctIndex, 0)
  assert.deepEqual(questions[2].accepted, ['<ol>', 'ordered list'])
})

test('a bad row is reported by its spreadsheet line, and the good ones still come in', () => {
  const { questions, problems } = questionsFromText(
    ['question,a,b,correct,seconds', 'Fine,x,y,a,20', 'Wrong key,x,y,q,20', ',x,y,a,20', 'Too long,x,y,a,999'].join('\n'),
  )
  assert.equal(questions.length, 1)
  assert.deepEqual(problems.map((p) => p.line), [3, 4, 5])
  assert.match(problems[0].why, /not one of the choices/)
  assert.match(problems[1].why, /no question text/)
  assert.match(problems[2].why, /seconds/)
})

test('the sheet can turn blurting off per row, and typed rows start off', () => {
  const { questions } = questionsFromText(
    ['question,a,b,correct,blurt', 'Keeps it,x,y,a,', 'Opts out,x,y,a,no', 'Typed,,,<ol>,'].join('\n'),
  )
  assert.deepEqual(questions.map((q) => q.blurtEnabled), [true, false, false])
})

test('blurt is the eighth column when there is no header row', () => {
  const { questions, problems } = questionsFromText(
    [
      'Rounds on\tParis\tLyon\t\t\tA\t15\tyes',
      'Rounds off\tParis\tLyon\t\t\tA\t15\tno',
      'Left empty\tParis\tLyon\t\t\tA\t15',
      'Typed, opted in\t\t\t\t\tParis\t20\tyes',
    ].join('\n'),
  )
  assert.deepEqual(problems, [])
  assert.deepEqual(questions.map((q) => q.blurtEnabled), [true, false, true, true])
  assert.equal(questions[3].kind, 'text')
})

test('a blurt cell that is not a yes or a no is a problem, not a guess', () => {
  const { questions, problems } = questionsFromText(
    ['question,a,b,correct,blurt', 'Clear,x,y,a,Y', 'Number,x,y,a,0', 'Typo,x,y,a,yse'].join('\n'),
  )
  assert.deepEqual(questions.map((q) => q.blurtEnabled), [true, false])
  assert.equal(problems.length, 1)
  assert.equal(problems[0].line, 4)
  assert.match(problems[0].why, /blurt must be yes or no/)
})

test('empty input is not an error', () => {
  assert.deepEqual(questionsFromText('  \n\n'), { questions: [], problems: [] })
})
