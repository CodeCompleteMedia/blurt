// The editor's side of the database. A teacher is trusted with their own content,
// so these are plain row reads and writes — row level security keeps each account
// to its own quizzes, and the shape of a question is enforced by a constraint.

import { imageUrl } from './api.js'
import { fromRow, toRow } from './question.js'
import { db } from './supabase.js'

const BUCKET = 'question-images'

function fail(error) {
  throw new Error(error.message ?? 'Something went wrong')
}

// ------------------------------------------------------------------ quizzes --

export async function createQuiz(title) {
  const { data, error } = await db.from('quizzes').insert({ title }).select('id').single()
  if (error) fail(error)
  return data.id
}

export async function loadQuiz(id) {
  const { data, error } = await db
    .from('quizzes')
    .select('id, title, default_seconds, questions(*)')
    .eq('id', id)
    .maybeSingle()
  if (error) fail(error)
  if (!data) return null
  return {
    id: data.id,
    title: data.title,
    defaultSeconds: data.default_seconds,
    questions: data.questions.sort((a, b) => a.position - b.position).map(fromRow),
  }
}

export async function saveQuizMeta(id, { title, defaultSeconds }) {
  const { error } = await db
    .from('quizzes')
    .update({ title: title.trim() || 'Untitled quiz', default_seconds: defaultSeconds })
    .eq('id', id)
  if (error) fail(error)
}

/**
 * Archives rather than deletes. A quiz that has been hosted is pointed at by every
 * game played from it, and later reports need the questions a class was actually
 * asked — so it disappears from the list and can no longer be hosted, and stays.
 */
export async function deleteQuiz(id) {
  const { error } = await db.from('quizzes').update({ archived_at: new Date().toISOString() }).eq('id', id)
  if (error) fail(error)
}

// ---------------------------------------------------------------- questions --

/** Inserts or updates, and returns the question's id. */
export async function saveQuestion(q, quizId, position) {
  const row = toRow(q, quizId, position)
  if (q.id) {
    // Position is owned by reorder_questions; an ordinary save must not move it.
    delete row.position
    const { error } = await db.from('questions').update(row).eq('id', q.id)
    if (error) fail(error)
    return q.id
  }
  const { data, error } = await db.from('questions').insert(row).select('id').single()
  if (error) fail(error)
  return data.id
}

export async function addQuestions(questions, quizId, startAt) {
  const rows = questions.map((q, i) => toRow(q, quizId, startAt + i))
  const { data, error } = await db.from('questions').insert(rows).select('*')
  if (error) fail(error)
  return data.sort((a, b) => a.position - b.position).map(fromRow)
}

export async function deleteQuestion(id) {
  const { error } = await db.from('questions').delete().eq('id', id)
  if (error) fail(error)
}

export async function reorderQuestions(quizId, ids) {
  const { error } = await db.rpc('reorder_questions', { p_quiz_id: quizId, p_ids: ids })
  if (error) fail(error)
}

// ------------------------------------------------------------------- images --

export { imageUrl }

/** Stores under the teacher's own folder, which is the only place they may write. */
export async function uploadImage(blob, userId, quizId) {
  const ext = blob.type === 'image/webp' ? 'webp' : blob.type === 'image/png' ? 'png' : 'jpg'
  const path = `${userId}/${quizId}/${crypto.randomUUID()}.${ext}`
  const { error } = await db.storage.from(BUCKET).upload(path, blob, {
    contentType: blob.type,
    cacheControl: '31536000',
  })
  if (error) fail(error)
  return path
}

export async function removeImage(path) {
  if (!path) return
  await db.storage.from(BUCKET).remove([path])
}
