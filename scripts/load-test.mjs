// A full class hitting the database in the same instant.
//
//   npm run load            # 40 players
//   npm run load -- 60      # or however many
//
// Answers do not arrive spread across the window. They cluster the moment a
// question appears and again on the deadline, and blurt is worse: every phone
// goes for the same row at once. Each of those calls takes a row lock on the
// game, so this is the one place where "works with three phones" says nothing
// about thirty.
//
// What has to hold: exactly one blurt wins, nobody's answer is lost, and the
// scores add up — under real concurrency, against the real database.

import { createClient } from '@supabase/supabase-js'

import { signInTeacher } from './lib/teacher.mjs'

const url = process.env.VITE_SUPABASE_URL
const key = process.env.VITE_SUPABASE_ANON_KEY
if (!url || !key) {
  console.error('Run: node --env-file=.env.local scripts/load-test.mjs')
  process.exit(2)
}

const N = Number(process.argv[2] ?? 40)
let failures = 0

const check = (label, pass, note = '') => {
  if (!pass) failures += 1
  console.log(`  ${pass ? 'ok  ' : 'FAIL'}  ${label}${note ? `  — ${note}` : ''}`)
}

const percentile = (values, p) => {
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))]
}

/** Fires every call at once and times each one. */
async function volley(calls) {
  const started = performance.now()
  const results = await Promise.all(
    calls.map(async (call) => {
      const t0 = performance.now()
      const result = await call()
      return { ...result, ms: performance.now() - t0 }
    }),
  )
  return { results, wallMs: performance.now() - started }
}

const timing = ({ results, wallMs }) => {
  const ms = results.map((r) => r.ms)
  return `p50 ${Math.round(percentile(ms, 50))}ms · p95 ${Math.round(percentile(ms, 95))}ms · all done in ${Math.round(wallMs)}ms`
}

console.log(`\nblurt — load test, ${N} players\n`)

const { teacher: host, quizId } = await signInTeacher(url, key)
const { data: made } = await host.rpc('create_game', { p_quiz_id: quizId })
const { code, host_token: H } = made[0]

// One client per phone, as it would be in the room.
const phones = Array.from({ length: N }, () =>
  createClient(url, key, { auth: { persistSession: false } }),
)

// ------------------------------------------------------------------ joining
const joins = await volley(
  phones.map((db, i) => async () => {
    const { data, error } = await db.rpc('join_game', { p_code: code, p_name: `Player ${i + 1}` })
    return { token: data?.[0]?.player_token, error }
  }),
)
const tokens = joins.results.map((r) => r.token)
check(`${N} players join at once`, joins.results.every((r) => r.token), timing(joins))

// -------------------------------------------------------------------- blurt
await host.rpc('advance_game', { p_host_token: H }) // -> recall

const claims = await volley(
  phones.map((db, i) => async () => {
    const { data, error } = await db.rpc('blurt', { p_player_token: tokens[i] })
    return { won: data === true, error }
  }),
)
const winners = claims.results.filter((r) => r.won).length
check('exactly one phone wins the floor', winners === 1, `${winners} winners · ${timing(claims)}`)
check('no claim errored under contention', claims.results.every((r) => !r.error))

// Judged wrong, so the room gets the choices and everyone else answers.
await host.rpc('judge_blurt', { p_host_token: H, p_correct: false })
const { data: q } = await host.rpc('host_question', { p_host_token: H })
const correct = q[0].q_correct_index

// ---------------------------------------------------------------- answering
const loser = claims.results.findIndex((r) => r.won)
const answers = await volley(
  phones.map((db, i) => async () => {
    // A third of the room is wrong, so the scores have something to add up to.
    const choice = i % 3 === 0 ? (correct + 1) % 4 : correct
    const { error } = await db.rpc('submit_answer', { p_player_token: tokens[i], p_choice: choice })
    return { error, choice }
  }),
)
check('every answer is accepted', answers.results.every((r) => !r.error), timing(answers))

const { data: game } = await host.from('games').select('phase, answered_count').eq('code', code).maybeSingle()
check('the last answer closed the question', game.phase === 'results', game.phase)
check('nobody was double-counted or dropped', game.answered_count === N,
  `${game.answered_count} of ${N}`)

const { data: dist } = await host.rpc('distribution', { p_code: code })
const tallied = dist.reduce((sum, row) => sum + Number(row.answer_count), 0)
// The wrong blurter is locked out: counted as done, but with no tapped answer.
check('the tally matches the room', tallied === N - 1, `${tallied} votes + 1 locked out`)

const { data: players } = await host.from('players').select('score').eq('game_id',
  (await host.from('games').select('id').eq('code', code).maybeSingle()).data.id)
const scorers = players.filter((p) => p.score > 0).length
const expected = answers.results.filter((r, i) => r.choice === correct && i !== loser).length
check('exactly the right players scored', scorers === expected, `${scorers} of ${expected}`)

await host.rpc('close_game', { p_host_token: H })
console.log(`\n  ${failures ? `${failures} failed` : 'held up'}  (room ${code})\n`)
process.exit(failures ? 1 : 0)
