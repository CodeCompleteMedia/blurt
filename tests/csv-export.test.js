import assert from 'node:assert/strict'
import { test } from 'node:test'

import { reportCsv } from '../src/lib/csv-export.js'

const report = {
  summary: {
    code: 'ABC12', playedAt: '2026-09-17T14:00:00.000Z', quizTitle: 'HTML, CSS & "the rest"',
    finished: false, players: 2, asked: 1, total: 3,
  },
  questions: [{
    position: 0, kind: 'choice', text: 'Which tag, exactly?', answer: '<body>',
    answered: 2, correct: 0, percent: 0, medianMs: 4200,
    commonWrong: 'a "wrong" one, comma and all', commonWrongCount: 2,
    blurter: 'Ana', blurtCorrect: false,
  }],
  players: [
    { id: 'a', name: 'Ana', score: 0, place: 1, answered: 1, correct: 0, bestStreak: 0,
      blurtWins: 0, blurtMisses: 1, avgMs: 4200, missed: [0] },
    { id: 'b', name: 'Beñat', score: 0, place: 1, answered: 1, correct: 0, bestStreak: 0,
      blurtWins: 0, blurtMisses: 0, avgMs: 4200, missed: [0] },
  ],
}

test('a field containing a comma or a quote survives the round trip', () => {
  const csv = reportCsv(report)
  assert.match(csv, /"HTML, CSS & ""the rest"""/)
  assert.match(csv, /"a ""wrong"" one, comma and all"/)
})

test('questions and students are both in the file, as separate tables', () => {
  const csv = reportCsv(report)
  assert.match(csv, /^#,Kind,Question,/m)
  assert.match(csv, /^Place,Name,Score,/m)
  assert.match(csv, /\r\n\r\n/)
})

test('question numbers are one-based everywhere, including "missed"', () => {
  const csv = reportCsv(report)
  const students = csv.split(/^Place,/m)[1]
  // Ana missed question index 0, which a teacher reads as question 1.
  assert.match(students, /Ana,0,1,0,0,0,0,1,4\.2,1/)
})

test('an accented name is written as itself', () => {
  assert.match(reportCsv(report), /Beñat/)
})

test('a game that was stopped early says how far it got', () => {
  assert.match(reportCsv(report), /Questions asked,1 of 3/)
  assert.match(reportCsv(report), /Questions 1-1 are the ones this room reached\./)
})
