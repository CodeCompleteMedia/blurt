// Runs the security properties against whatever database the environment points
// at, using the anon key — the same access a student has after opening devtools.
//
//   npm run verify:db
//
// This exists because the policies are only right until a later migration
// quietly loosens one. A convenience `select` on `questions` would hand every
// phone the answer key, and nothing else in the test suite would notice.

import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL
const key = process.env.VITE_SUPABASE_ANON_KEY

if (!url || !key) {
  console.error('Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY.')
  console.error('Run: node --env-file=.env.local scripts/verify-db.mjs')
  process.exit(2)
}

const db = createClient(url, key, { auth: { persistSession: false } })
const FORGED = '00000000-0000-0000-0000-000000000000'
let failures = 0

function check(label, pass, note = '') {
  if (!pass) failures += 1
  console.log(`  ${pass ? 'ok  ' : 'FAIL'}  ${label}${note ? `  — ${note}` : ''}`)
}

const denied = async (table) => {
  const { error, data } = await db.from(table).select('*').limit(1)
  return { ok: error !== null, note: error?.message ?? `read ${data?.length} rows` }
}

console.log('\nblurt — database security checks\n')

for (const table of ['questions', 'answers', 'game_secrets', 'player_secrets']) {
  const { ok, note } = await denied(table)
  check(`anon cannot read ${table}`, ok, note)
}

const games = await db.from('games').select('code').limit(1)
check('anon can read games (Realtime needs it)', games.error === null, games.error?.message)

const quiz = await db.from('quizzes').select('id').limit(1).maybeSingle()
if (!quiz.data) {
  check('a quiz exists to test against', false, 'run `npx supabase db push`')
  process.exit(1)
}

const { data: made, error: makeErr } = await db.rpc('create_game', { p_quiz_id: quiz.data.id })
check('create_game', !makeErr && Boolean(made?.[0]?.code), makeErr?.message)
if (makeErr) process.exit(1)
const { code, host_token: hostToken } = made[0]

const { data: seat } = await db.rpc('join_game', { p_code: code, p_name: 'Verify' })
check('join_game issues a seat token', Boolean(seat?.[0]?.player_token))

const { data: rival } = await db.rpc('join_game', { p_code: code, p_name: 'Rival' })

const dup = await db.rpc('join_game', { p_code: code, p_name: 'verify' })
check('duplicate name refused', dup.error !== null, dup.error?.message)

const early = await db.rpc('submit_answer', { p_player_token: seat[0].player_token, p_choice: 1 })
check('cannot answer before the question opens', early.error !== null, early.error?.message)

await db.rpc('advance_game', { p_host_token: hostToken }) // -> recall

// The recall window is the point of the whole mechanic, so the choices have to
// be withheld by the database rather than merely hidden by the screen.
const recall = await db.rpc('current_question', { p_code: code })
check('choices withheld during recall', recall.data?.[0]?.q_choices === null,
  `got ${JSON.stringify(recall.data?.[0]?.q_choices)}`)

const studentPeek = await db.rpc('host_question', { p_host_token: FORGED })
check('a student cannot read the answer key', studentPeek.error !== null, studentPeek.error?.message)

const refCard = await db.rpc('host_question', { p_host_token: hostToken })
check('the host can read the answer key during recall',
  Number.isInteger(refCard.data?.[0]?.q_correct_index) && Array.isArray(refCard.data?.[0]?.q_choices))

const firstClaim = await db.rpc('blurt', { p_player_token: seat[0].player_token })
check('first blurt claims the floor', firstClaim.data === true)

const secondClaim = await db.rpc('blurt', { p_player_token: rival[0].player_token })
check('a second blurt finds it taken', secondClaim.data === false)

const studentJudge = await db.rpc('judge_blurt', { p_host_token: FORGED, p_correct: true })
check('a student cannot judge a blurt', studentJudge.error !== null, studentJudge.error?.message)

await db.rpc('judge_blurt', { p_host_token: hostToken, p_correct: false })

const lockedOut = await db.from('players').select('score').eq('id', seat[0].player_id).maybeSingle()
await db.rpc('submit_answer', { p_player_token: seat[0].player_token, p_choice: 0 })
const stillLocked = await db.from('players').select('score').eq('id', seat[0].player_id).maybeSingle()
check('a wrong blurt locks that player out of the question',
  lockedOut.data?.score === stillLocked.data?.score,
  `${lockedOut.data?.score} -> ${stillLocked.data?.score}`)

const open = await db.rpc('current_question', { p_code: code })
check('choices appear once the blurt is judged wrong', Array.isArray(open.data?.[0]?.q_choices))
check('correct answer withheld while open', open.data?.[0]?.q_correct_index === null,
  `got ${JSON.stringify(open.data?.[0]?.q_correct_index)}`)

const dist = await db.rpc('distribution', { p_code: code })
check('distribution empty before results', (dist.data?.length ?? 0) === 0)

// A player learning they were right mid-question could tell the person next to
// them, so their own result is withheld until the room reaches results too.
const peekMine = await db.rpc('my_result', { p_player_token: rival[0].player_token })
check('own result withheld before results', (peekMine.data?.length ?? 0) === 0)

const notHost = await db.rpc('advance_game', { p_host_token: FORGED })
check('a student cannot advance the game', notHost.error !== null, notHost.error?.message)

await db.rpc('submit_answer', { p_player_token: rival[0].player_token, p_choice: 0 })
await db.rpc('advance_game', { p_host_token: hostToken })
await db.rpc('advance_game', { p_host_token: hostToken })

const shown = await db.rpc('current_question', { p_code: code })
check('correct answer released at results', Number.isInteger(shown.data?.[0]?.q_correct_index))

const after = await db.rpc('distribution', { p_code: code })
check('distribution appears at results', (after.data?.length ?? 0) === 4)

const mine = await db.rpc('my_result', { p_player_token: rival[0].player_token })
check('own result released at results',
  mine.data?.[0]?.answered === true && typeof mine.data?.[0]?.correct === 'boolean',
  `correct ${mine.data?.[0]?.correct}, awarded ${mine.data?.[0]?.awarded}`)

const notMine = await db.rpc('my_result', { p_player_token: FORGED })
check('a forged token gets no result', notMine.error !== null, notMine.error?.message)

console.log(`\n  ${failures ? `${failures} failed` : 'all checks passed'}  (test room ${code})\n`)
process.exit(failures ? 1 : 0)
