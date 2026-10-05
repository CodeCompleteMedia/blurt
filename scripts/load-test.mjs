// A full class hitting the database in the same instant.
//
//   npm run load            # 40 players in one room
//   npm run load -- 60      # or however many (a room holds 60)
//   npm run load -- 10x30   # 10 rooms of 30, every room in the same instant
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

// "10x30" is ten rooms of thirty; a bare number is one room of that many.
const shape = String(process.argv[2] ?? '40').match(/^(?:(\d+)x)?(\d+)$/i)
if (!shape) {
  console.error('Usage: npm run load -- 40   or   npm run load -- 10x30')
  process.exit(2)
}
const ROOMS = Number(shape[1] ?? 1)
const N = Number(shape[2])
const TOTAL = ROOMS * N
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

console.log(
  ROOMS === 1
    ? `\nblurt — load test, ${N} players\n`
    : `\nblurt — load test, ${ROOMS} rooms of ${N} (${TOTAL} players), every room at once\n`,
)

const { teacher: host, quizId } = await signInTeacher(url, key)

// Each phase fires across every room at once: all the joins together, then
// all the blurts, then all the answers. Ten classes doing the same thing in
// the same second is the worst case for a database that locks per room.
const rooms = []
for (let r = 0; r < ROOMS; r += 1) {
  const { data: made, error } = await host.rpc('create_game', { p_quiz_id: quizId })
  if (error) {
    console.error(`\n  Could not open room ${r + 1}: ${error.message}\n`)
    process.exit(1)
  }
  rooms.push({
    code: made[0].code,
    H: made[0].host_token,
    // One client per phone, as it would be in the room.
    phones: Array.from({ length: N }, () => createClient(url, key, { auth: { persistSession: false } })),
  })
}

const each = (fn) => rooms.flatMap((room, r) => room.phones.map((db, i) => () => fn(room, db, i, r)))
const perRoom = (results) => rooms.map((_, r) => results.slice(r * N, (r + 1) * N))
const roomsWhere = (test) => rooms.filter(test).length
const tally = (ok) => (ROOMS === 1 ? '' : `${ok} of ${ROOMS} rooms · `)

// ------------------------------------------------------------------ joining
const joins = await volley(
  each(async (room, db, i, r) => {
    const { data, error } = await db.rpc('join_game', { p_code: room.code, p_name: `Player ${i + 1}` })
    return { token: data?.[0]?.player_token, error }
  }),
)
perRoom(joins.results).forEach((results, r) => (rooms[r].tokens = results.map((x) => x.token)))
check(`${TOTAL} players join at once`, joins.results.every((r) => r.token), timing(joins))

// -------------------------------------------------------------------- blurt
await Promise.all(rooms.map((room) => host.rpc('advance_game', { p_host_token: room.H }))) // -> recall

const claims = await volley(
  each(async (room, db, i) => {
    const { data, error } = await db.rpc('blurt', { p_player_token: room.tokens[i] })
    return { won: data === true, error }
  }),
)
perRoom(claims.results).forEach((results, r) => (rooms[r].claims = results))
const oneWinner = roomsWhere((room) => room.claims.filter((c) => c.won).length === 1)
const winners = claims.results.filter((r) => r.won).length
check(
  ROOMS === 1 ? 'exactly one phone wins the floor' : 'exactly one phone wins the floor in every room',
  oneWinner === ROOMS,
  `${tally(oneWinner)}${winners} winners · ${timing(claims)}`,
)
check('no claim errored under contention', claims.results.every((r) => !r.error))

// Judged wrong, so each room gets the choices and everyone else answers.
await Promise.all(rooms.map((room) => host.rpc('judge_blurt', { p_host_token: room.H, p_correct: false })))
await Promise.all(
  rooms.map(async (room) => {
    const { data: q } = await host.rpc('host_question', { p_host_token: room.H })
    room.correct = q[0].q_correct_index
  }),
)

// ---------------------------------------------------------------- answering
const answers = await volley(
  each(async (room, db, i) => {
    // A third of the room is wrong, so the scores have something to add up to.
    const choice = i % 3 === 0 ? (room.correct + 1) % 4 : room.correct
    const { error } = await db.rpc('submit_answer', { p_player_token: room.tokens[i], p_choice: choice })
    return { error, choice }
  }),
)
perRoom(answers.results).forEach((results, r) => (rooms[r].answers = results))
check('every answer is accepted', answers.results.every((r) => !r.error), timing(answers))

// The tables are shut; a room is read by its code, exactly as a phone reads it.
// Each room is checked on its own, so an answer counted in the wrong room
// fails here rather than averaging out.
await Promise.all(
  rooms.map(async (room) => {
    const loser = room.claims.findIndex((c) => c.won)
    const [{ data: g }, { data: dist }, { data: players }] = await Promise.all([
      host.rpc('game_state', { p_code: room.code }),
      host.rpc('distribution', { p_code: room.code }),
      host.rpc('roster', { p_code: room.code }),
    ])
    room.game = g?.[0]
    room.tallied = (dist ?? []).reduce((sum, row) => sum + Number(row.answer_count), 0)
    room.scorers = (players ?? []).filter((p) => p.score > 0).length
    room.expected = room.answers.filter((a, i) => a.choice === room.correct && i !== loser).length
  }),
)

const closed = roomsWhere((room) => room.game?.phase === 'results')
check('the last answer closed the question', closed === ROOMS,
  ROOMS === 1 ? rooms[0].game?.phase : `${closed} of ${ROOMS} rooms`)

const counted = roomsWhere((room) => room.game?.answered_count === N)
const answered = rooms.reduce((sum, room) => sum + (room.game?.answered_count ?? 0), 0)
check('nobody was double-counted or dropped', counted === ROOMS, `${tally(counted)}${answered} of ${TOTAL}`)

// The wrong blurter is locked out: counted as done, but with no tapped answer.
const tallies = roomsWhere((room) => room.tallied === N - 1)
check('the tally matches the room', tallies === ROOMS,
  ROOMS === 1 ? `${rooms[0].tallied} votes + 1 locked out` : `${tallies} of ${ROOMS} rooms`)

const scored = roomsWhere((room) => room.scorers === room.expected)
const scorers = rooms.reduce((sum, room) => sum + room.scorers, 0)
const expected = rooms.reduce((sum, room) => sum + room.expected, 0)
check('exactly the right players scored', scored === ROOMS, `${tally(scored)}${scorers} of ${expected}`)

await Promise.all(rooms.map((room) => host.rpc('close_game', { p_host_token: room.H })))
const codes = rooms.map((room) => room.code).join(', ')
console.log(`\n  ${failures ? `${failures} failed` : 'held up'}  (${ROOMS === 1 ? 'room' : 'rooms'} ${codes})\n`)
process.exit(failures ? 1 : 0)
