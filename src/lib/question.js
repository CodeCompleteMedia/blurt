// A question, as the editor holds it: its shape, its blank forms, what makes it
// unsaveable, and how it maps to a database row. No imports, on purpose — this is
// the part worth unit-testing, and the Supabase client cannot load outside Vite.
//
// `problemWith` repeats the database's own constraint in words. The database would
// refuse a bad question anyway; checking first is how the teacher finds out *why*
// before they have moved on to the next one.

export const KINDS = {
  choice: 'Multiple choice',
  truefalse: 'True or false',
  text: 'Type the answer',
}

export function blankQuestion(kind = 'choice') {
  return {
    id: null,
    key: crypto.randomUUID(),
    kind,
    text: '',
    choices: kind === 'choice' ? ['', '', '', ''] : kind === 'truefalse' ? ['True', 'False'] : [],
    correctIndex: kind === 'text' ? null : 0,
    accepted: kind === 'text' ? [''] : [],
    seconds: null,
    recallSeconds: 8,
    // On by default, except where it would be the same act twice: a typed answer
    // is already produced from memory, so a window to say it out loud first adds
    // only a race. The teacher can still switch it on.
    blurtEnabled: kind !== 'text',
    imagePath: null,
  }
}

/** Why this question cannot be saved yet, or null when it can. */
export function problemWith(q) {
  if (!q.text.trim()) return 'Add the question'
  if (q.kind === 'choice') {
    const filled = q.choices.map((c) => c.trim())
    const used = filled.filter(Boolean)
    if (used.length < 2) return 'Needs at least two choices'
    // Blank choices may only trail: a gap in the middle would shift the correct
    // answer onto a different tile once they are dropped.
    if (filled.slice(0, used.length).some((c) => !c)) return 'Fill the choices in order, no gaps'
    if (!(q.correctIndex >= 0 && q.correctIndex < used.length)) return 'Mark the correct choice'
  } else if (q.kind === 'text') {
    if (!q.accepted.some((a) => a.trim())) return 'Add at least one accepted answer'
  }
  return null
}

export function toRow(q, quizId, position) {
  const choices = q.kind === 'choice' ? q.choices.map((c) => c.trim()).filter(Boolean) : q.choices
  return {
    quiz_id: quizId,
    position,
    kind: q.kind,
    text: q.text.trim(),
    choices: q.kind === 'text' ? null : choices,
    correct_index: q.kind === 'text' ? null : q.correctIndex,
    accepted: q.kind === 'text' ? q.accepted.map((a) => a.trim()).filter(Boolean) : null,
    seconds: q.seconds || null,
    recall_seconds: q.recallSeconds || 8,
    blurt_enabled: q.blurtEnabled !== false,
    image_path: q.imagePath,
  }
}

export function fromRow(row) {
  const choices = row.choices ?? []
  return {
    id: row.id,
    key: row.id,
    kind: row.kind,
    text: row.text,
    // The choice editor always shows four boxes; the blanks are dropped on save.
    choices: row.kind === 'choice' ? [...choices, '', '', '', ''].slice(0, 4) : choices,
    correctIndex: row.correct_index,
    accepted: row.accepted ?? [],
    seconds: row.seconds,
    recallSeconds: row.recall_seconds,
    blurtEnabled: row.blurt_enabled !== false,
    imagePath: row.image_path,
  }
}
