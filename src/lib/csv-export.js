// Turning a report into a file. No imports, on purpose: this is the part worth
// unit-testing, and anything that pulls in the Supabase client cannot load
// outside Vite.

const cell = (value) => {
  const s = value === null || value === undefined ? '' : String(value)
  return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s
}
const rows = (lines) => lines.map((r) => r.map(cell).join(',')).join('\r\n')

/**
 * Two tables in one file, separated by a blank line — questions then students.
 * A spreadsheet opens it happily, and a teacher who wanted one of them can delete
 * the other far more easily than they could join two downloads back together.
 */
export function reportCsv({ summary, questions, players }) {
  const asked = questions.length
  return [
    rows([
      ['blurt report'],
      ['Quiz', summary.quizTitle],
      ['Room', summary.code],
      ['Played', new Date(summary.playedAt).toLocaleString()],
      ['Questions asked', `${summary.asked} of ${summary.total}`],
      ['Students', summary.players],
    ]),
    '',
    rows([
      ['#', 'Kind', 'Question', 'Answer', 'Answered', 'Correct', '% correct', 'Median seconds', 'Most common wrong', 'Times chosen', 'Blurted by', 'Blurt correct'],
      ...questions.map((q) => [
        q.position + 1, q.kind, q.text, q.answer, q.answered, q.correct, q.percent,
        (q.medianMs / 1000).toFixed(1), q.commonWrong ?? '', q.commonWrongCount ?? '',
        q.blurter ?? '', q.blurter ? (q.blurtCorrect ? 'yes' : 'no') : '',
      ]),
    ]),
    '',
    rows([
      ['Place', 'Name', 'Score', 'Answered', 'Correct', '% correct', 'Best streak', 'Blurts won', 'Blurts missed', 'Average seconds', 'Missed questions'],
      ...players.map((p) => [
        p.place, p.name, p.score, p.answered, p.correct,
        p.answered ? Math.round((100 * p.correct) / p.answered) : 0,
        p.bestStreak, p.blurtWins, p.blurtMisses, (p.avgMs / 1000).toFixed(1),
        // One-based, to match the numbers on the questions table above.
        p.missed.map((i) => i + 1).join(' '),
      ]),
    ]),
    '',
    rows([[`Questions 1-${asked} are the ones this room reached.`]]),
  ].join('\r\n')
}

export function downloadCsv(filename, text) {
  // A BOM, or Excel reads a name with an accent in it as mojibake.
  const blob = new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = Object.assign(document.createElement('a'), { href: url, download: filename })
  document.body.append(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
}
