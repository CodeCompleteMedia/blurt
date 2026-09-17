// Turning a spreadsheet into questions.
//
// The realistic source is not a .csv file, it is a range copied out of Google
// Sheets or Excel — which arrives tab-separated. So the delimiter is detected,
// and everything here is a pure function of the pasted text: the editor previews
// the result, problems and all, before anything touches the database.

/** RFC 4180 with a detected delimiter: quotes, doubled quotes, newlines in cells. */
export function parseDelimited(text) {
  const source = text.replace(/^﻿/, '')
  const firstLine = source.split(/\r?\n/, 1)[0] ?? ''
  const count = (ch) => firstLine.split(ch).length - 1
  const delimiter = count('\t') > 0 ? '\t' : count(';') > count(',') ? ';' : ','

  const rows = []
  let row = []
  let cell = ''
  let quoted = false

  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i]
    if (quoted) {
      if (ch === '"' && source[i + 1] === '"') {
        cell += '"'
        i += 1
      } else if (ch === '"') quoted = false
      else cell += ch
    } else if (ch === '"' && cell === '') quoted = true
    else if (ch === delimiter) {
      row.push(cell)
      cell = ''
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && source[i + 1] === '\n') i += 1
      row.push(cell)
      rows.push(row)
      row = []
      cell = ''
    } else cell += ch
  }
  if (cell !== '' || row.length) {
    row.push(cell)
    rows.push(row)
  }
  return rows.map((r) => r.map((c) => c.trim())).filter((r) => r.some((c) => c !== ''))
}

const HEADERS = {
  question: ['question', 'text', 'prompt', 'q'],
  type: ['type', 'kind'],
  a: ['a', 'choice a', 'answer a', 'option a', 'choice 1'],
  b: ['b', 'choice b', 'answer b', 'option b', 'choice 2'],
  c: ['c', 'choice c', 'answer c', 'option c', 'choice 3'],
  d: ['d', 'choice d', 'answer d', 'option d', 'choice 4'],
  correct: ['correct', 'answer', 'correct answer', 'key'],
  seconds: ['seconds', 'time', 'time limit', 'secs'],
  recall: ['recall', 'recall seconds'],
  blurt: ['blurt', 'blurtable', 'blurt?'],
}
const POSITIONAL = ['question', 'a', 'b', 'c', 'd', 'correct', 'seconds']

function columnsFor(firstRow) {
  const lowered = firstRow.map((cell) => cell.toLowerCase())
  const found = {}
  for (const [field, names] of Object.entries(HEADERS)) {
    const at = lowered.findIndex((cell) => names.includes(cell))
    if (at >= 0) found[field] = at
  }
  // A header row is one that names the question column. Anything else is data,
  // laid out in the order a teacher would type it.
  if ('question' in found) return { columns: found, hasHeader: true }
  return { columns: Object.fromEntries(POSITIONAL.map((f, i) => [f, i])), hasHeader: false }
}

const TRUE = ['true', 't', 'yes', 'y']
const FALSE = ['false', 'f', 'no', 'n']

function numberIn(value, min, max) {
  if (value === '') return null
  const n = Number(value)
  return Number.isInteger(n) && n >= min && n <= max ? n : NaN
}

/**
 * Returns `{ questions, problems }`. A row with a problem is left out of
 * `questions` and explained in `problems`, by the line a teacher would see in
 * their spreadsheet — never silently dropped, never half-imported.
 */
export function questionsFromText(text) {
  const rows = parseDelimited(text)
  if (!rows.length) return { questions: [], problems: [] }

  const { columns, hasHeader } = columnsFor(rows[0])
  const get = (row, field) => (field in columns ? (row[columns[field]] ?? '') : '')
  const questions = []
  const problems = []

  rows.slice(hasHeader ? 1 : 0).forEach((row, i) => {
    const line = i + (hasHeader ? 2 : 1)
    const fail = (why) => problems.push({ line, why, text: get(row, 'question') })

    const textCell = get(row, 'question')
    if (!textCell) return fail('no question text')

    const choices = ['a', 'b', 'c', 'd'].map((f) => get(row, f))
    while (choices.length && choices[choices.length - 1] === '') choices.pop()
    const correct = get(row, 'correct')
    const low = correct.toLowerCase()

    let kind = get(row, 'type').toLowerCase().replace(/[^a-z]/g, '')
    if (['tf', 'truefalse', 'boolean'].includes(kind)) kind = 'truefalse'
    else if (['text', 'typed', 'type', 'short', 'shortanswer'].includes(kind)) kind = 'text'
    else if (['choice', 'mc', 'multiplechoice', 'multiple'].includes(kind)) kind = 'choice'
    else if (kind) return fail(`unknown type "${get(row, 'type')}"`)
    else if (choices.length >= 2) kind = 'choice'
    else if ([...TRUE, ...FALSE].includes(low)) kind = 'truefalse'
    else kind = 'text'

    const seconds = numberIn(get(row, 'seconds'), 5, 120)
    const recall = numberIn(get(row, 'recall'), 3, 60)
    if (Number.isNaN(seconds)) return fail('seconds must be a whole number from 5 to 120')
    if (Number.isNaN(recall)) return fail('recall must be a whole number from 3 to 60')

    // Off for typed questions, and off if the sheet says so.
    const blurtCell = get(row, 'blurt').toLowerCase()
    const blurtEnabled = blurtCell
      ? !FALSE.includes(blurtCell) && blurtCell !== '0'
      : kind !== 'text'

    const base = { kind, text: textCell, seconds, recallSeconds: recall ?? 8, blurtEnabled }

    if (kind === 'choice') {
      if (choices.length < 2) return fail('needs at least two choices')
      if (choices.some((c) => c === '')) return fail('a choice in the middle is blank')
      let index = 'abcd'.indexOf(low)
      if (low.length !== 1 || index < 0) index = Number(correct) - 1
      // Spelling out the right answer instead of lettering it is the natural
      // thing to do in a spreadsheet, so accept that too.
      if (!Number.isInteger(index) || index < 0) index = choices.findIndex((c) => c.toLowerCase() === low)
      if (!(index >= 0 && index < choices.length)) return fail(`"${correct}" is not one of the choices`)
      questions.push({ ...base, choices, correctIndex: index, accepted: [] })
    } else if (kind === 'truefalse') {
      if (![...TRUE, ...FALSE].includes(low)) return fail('correct must be true or false')
      questions.push({ ...base, choices: ['True', 'False'], correctIndex: TRUE.includes(low) ? 0 : 1, accepted: [] })
    } else {
      const accepted = correct.split('|').map((s) => s.trim()).filter(Boolean)
      if (!accepted.length) return fail('needs an answer (separate alternatives with |)')
      questions.push({ ...base, choices: [], correctIndex: null, accepted })
    }
  })

  return { questions, problems }
}
