// Runs the security properties against whatever database the environment points
// at, using the anon key — the same access a student has after opening devtools.
//
//   npm run verify:db
//
// This exists because the policies are only right until a later migration
// quietly loosens one. A convenience `select` on `questions` would hand every
// phone the answer key, and nothing else in the test suite would notice.

import { createClient } from '@supabase/supabase-js'

import { signInTeacher } from './lib/teacher.mjs'

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

// `db` stays a student throughout: the anon key and nothing else. `teacher` is
// signed in, and is the only one who can open a room.
const { teacher, quizId } = await signInTeacher(url, key)
const quiz = { data: { id: quizId } }

const peek = await db.from('quizzes').select('id').limit(1)
check('anon cannot list quizzes', peek.error !== null, peek.error?.message)

// The hole this closes: a student opening a private room on the teacher's quiz,
// becoming its "host", and reading the answer key out of host_question.
const heist = await db.rpc('create_game', { p_quiz_id: quizId })
check('a student cannot open a room on the teacher\'s quiz', heist.error !== null, heist.error?.message)

const template = await teacher.rpc('create_game', { p_quiz_id: '11111111-1111-1111-1111-111111111111' })
check('nobody can host the ownerless template', template.error !== null, template.error?.message)

const { data: made, error: makeErr } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
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

// The blurter is locked out but counted, so the rival is the only answer the
// room is still waiting on — the question should close itself on their tap
// rather than run the clock down.
const beforeLast = await db.from('games').select('phase').eq('code', code).maybeSingle()
await db.rpc('submit_answer', { p_player_token: rival[0].player_token, p_choice: 0 })
const afterLast = await db.from('games').select('phase').eq('code', code).maybeSingle()
check('the last answer reveals straight away',
  beforeLast.data?.phase === 'question_open' && afterLast.data?.phase === 'results',
  `${beforeLast.data?.phase} -> ${afterLast.data?.phase}`)

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

// A question won outright on a blurt: the reveal must not show four zeroes over
// a scoreboard where somebody clearly scored.
{
  const { data: m2 } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
  const { code: c2, host_token: h2 } = m2[0]
  const { data: s2 } = await db.rpc('join_game', { p_code: c2, p_name: 'Blurter' })
  await db.rpc('advance_game', { p_host_token: h2 })
  await db.rpc('blurt', { p_player_token: s2[0].player_token })
  await db.rpc('judge_blurt', { p_host_token: h2, p_correct: true })

  const q = await db.rpc('current_question', { p_code: c2 })
  const dist = await db.rpc('distribution', { p_code: c2 })
  const counts = (dist.data ?? []).map((r) => Number(r.answer_count))
  const correctIndex = q.data?.[0]?.q_correct_index

  check('a correct blurt counts toward the answer it named',
    counts[correctIndex] === 1 && counts.reduce((a, b) => a + b, 0) === 1,
    `[${counts.join(', ')}] correct=${correctIndex}`)

  const who = await db.rpc('blurter', { p_code: c2 })
  check('the wall can credit the blurter at results',
    who.data?.[0]?.player_name === 'Blurter' && who.data?.[0]?.was_correct === true)
}

// Closing a room is how the wall and the phones learn to go home.
{
  const { data: m3 } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
  const { code: c3, host_token: h3 } = m3[0]
  await db.rpc('join_game', { p_code: c3, p_name: 'Stayer' })

  const studentClose = await db.rpc('close_game', { p_host_token: FORGED })
  check('a student cannot close the room', studentClose.error !== null, studentClose.error?.message)

  await db.rpc('close_game', { p_host_token: h3 })
  const closed = await db.from('games').select('phase, closed_at').eq('code', c3).maybeSingle()
  check('closing marks the room without losing where it stopped',
    closed.data?.closed_at !== null && closed.data?.phase === 'lobby')

  const lateJoin = await db.rpc('join_game', { p_code: c3, p_name: 'Latecomer' })
  check('nobody can join a closed room', lateJoin.error !== null, lateJoin.error?.message)
}

// Settings are rules, so they are enforced where a client cannot reach them.
{
  const notHost = await db.rpc('update_game_settings', {
    p_host_token: FORGED,
    p_blurt_enabled: false,
  })
  check('a student cannot change the settings', notHost.error !== null, notHost.error?.message)

  // Blurting off: a question opens with its choices up, no recall window.
  const { data: m4 } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
  await db.rpc('update_game_settings', { p_host_token: m4[0].host_token, p_blurt_enabled: false })
  await db.rpc('advance_game', { p_host_token: m4[0].host_token })
  const noBlurt = await db.from('games').select('phase').eq('code', m4[0].code).maybeSingle()
  check('with blurting off a question opens straight into its choices',
    noBlurt.data?.phase === 'question_open', noBlurt.data?.phase)

  // Reveal pace off: all-in stops on the beat instead of revealing.
  const { data: m5 } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
  await db.rpc('update_game_settings', { p_host_token: m5[0].host_token, p_reveal_immediately: false })
  const { data: solo } = await db.rpc('join_game', { p_code: m5[0].code, p_name: 'Solo' })
  await db.rpc('advance_game', { p_host_token: m5[0].host_token })
  await db.rpc('advance_game', { p_host_token: m5[0].host_token })
  await db.rpc('submit_answer', { p_player_token: solo[0].player_token, p_choice: 0 })
  const paused = await db.from('games').select('phase').eq('code', m5[0].code).maybeSingle()
  check('with the pause on, all-in waits on the beat', paused.data?.phase === 'locked',
    paused.data?.phase)

  // Without the lockout a wrong blurt still owes an answer, and must not be
  // counted as done — or the question closes while the room waits on them.
  const { data: m7 } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
  await db.rpc('update_game_settings', {
    p_host_token: m7[0].host_token,
    p_blurt_lockout: false,
    p_blurt_penalty: 250,
  })
  const { data: brave } = await db.rpc('join_game', { p_code: m7[0].code, p_name: 'Brave' })
  await db.rpc('advance_game', { p_host_token: m7[0].host_token })
  await db.rpc('blurt', { p_player_token: brave[0].player_token })
  await db.rpc('judge_blurt', { p_host_token: m7[0].host_token, p_correct: false })

  const stillOpen = await db.from('games').select('phase').eq('code', m7[0].code).maybeSingle()
  check('without the lockout the room still waits for their answer',
    stillOpen.data?.phase === 'question_open', stillOpen.data?.phase)

  const before = await db.from('players').select('score').eq('id', brave[0].player_id).maybeSingle()
  // current_question withholds the answer mid-question — that is the point of it.
  // The referee read is how you learn it.
  const q7 = await db.rpc('host_question', { p_host_token: m7[0].host_token })
  await db.rpc('submit_answer', {
    p_player_token: brave[0].player_token,
    p_choice: q7.data[0].q_correct_index,
  })
  const after = await db.from('players').select('score').eq('id', brave[0].player_id).maybeSingle()
  check('a wrong blurt without the lockout still gets to answer',
    after.data?.score > before.data?.score, `${before.data?.score} -> ${after.data?.score}`)

  // Nobody goes negative, however harsh the setting.
  const { data: m8 } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
  await db.rpc('update_game_settings', { p_host_token: m8[0].host_token, p_blurt_penalty: 500 })
  const { data: broke } = await db.rpc('join_game', { p_code: m8[0].code, p_name: 'Broke' })
  await db.rpc('advance_game', { p_host_token: m8[0].host_token })
  await db.rpc('blurt', { p_player_token: broke[0].player_token })
  await db.rpc('judge_blurt', { p_host_token: m8[0].host_token, p_correct: false })
  const floored = await db.from('players').select('score').eq('id', broke[0].player_id).maybeSingle()
  check('the penalty never takes anyone below zero', floored.data?.score === 0,
    `${floored.data?.score}`)

  // The recall override has to reach the screens, not just the deadline.
  const { data: m6 } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
  await db.rpc('update_game_settings', { p_host_token: m6[0].host_token, p_recall_seconds: 20 })
  await db.rpc('advance_game', { p_host_token: m6[0].host_token })
  const seen = await db.rpc('current_question', { p_code: m6[0].code })
  check('the recall window the screens count down is the one enforced',
    seen.data?.[0]?.q_seconds === 20, `${seen.data?.[0]?.q_seconds}s`)
}

// Phase 3: the things a class will try in the first five minutes.
{
  const internal = await db.rpc('close_question_if_all_in', { p_game_id: FORGED })
  check('internal helpers are not callable from a phone', internal.error !== null,
    internal.error?.message?.slice(0, 60))

  const { data: m9 } = await teacher.rpc('create_game', { p_quiz_id: quiz.data.id })
  const H9 = m9[0].host_token
  const C9 = m9[0].code

  for (const bad of ['Teacher', 'Mr Patino', 'sh1t', 'xXfuuuckXx']) {
    const r = await db.rpc('join_game', { p_code: C9, p_name: bad })
    check(`"${bad}" is refused as a name`, r.error !== null, r.error?.message)
  }
  for (const fine of ['Shital', 'Nazir', 'Cassandra']) {
    const r = await db.rpc('join_game', { p_code: C9, p_name: fine })
    check(`"${fine}" is not caught by the filter`, r.error === null, r.error?.message)
  }

  const { data: a } = await db.rpc('join_game', { p_code: C9, p_name: 'Anna' })
  const { data: t } = await db.rpc('join_game', { p_code: C9, p_name: 'Holdout' })

  for (const [name, args] of [
    ['kick_player', { p_host_token: FORGED, p_player_id: t[0].player_id }],
    ['rename_player', { p_host_token: FORGED, p_player_id: t[0].player_id, p_name: 'Pwned' }],
    ['set_paused', { p_host_token: FORGED, p_paused: true }],
    ['extend_question', { p_host_token: FORGED, p_seconds: 60 }],
  ]) {
    const r = await db.rpc(name, args)
    check(`a student cannot call ${name}`, r.error !== null, r.error?.message)
  }

  // Everyone but Holdout answers, so Holdout is all the room is waiting on.
  await db.rpc('update_game_settings', { p_host_token: H9, p_blurt_enabled: false })
  await db.rpc('advance_game', { p_host_token: H9 })
  await db.rpc('submit_answer', { p_player_token: a[0].player_token, p_choice: 0 })

  const seat = await db.rpc('my_seat', { p_player_token: a[0].player_token })
  check('a reloaded phone learns it has already answered',
    seat.data?.[0]?.answered_current === true && !('correct' in (seat.data?.[0] ?? {})))

  await db.rpc('set_paused', { p_host_token: H9, p_paused: true })
  const held = await db.rpc('submit_answer', { p_player_token: t[0].player_token, p_choice: 0 })
  check('nothing is accepted while paused', held.error !== null, held.error?.message)
  await db.rpc('set_paused', { p_host_token: H9, p_paused: false })

  const before = await db.rpc('current_question', { p_code: C9 })
  await db.rpc('extend_question', { p_host_token: H9, p_seconds: 15 })
  const after = await db.rpc('current_question', { p_code: C9 })
  check('an extension reaches the screens, not just the deadline',
    after.data?.[0]?.q_seconds === before.data?.[0]?.q_seconds + 15,
    `${before.data?.[0]?.q_seconds}s -> ${after.data?.[0]?.q_seconds}s`)

  await db.rpc('kick_player', { p_host_token: H9, p_player_id: t[0].player_id })
  const gone = await db.rpc('my_seat', { p_player_token: t[0].player_token })
  check('a removed player\'s seat stops resolving', gone.error !== null, gone.error?.message)
  await db.rpc('close_game', { p_host_token: H9 })
}

// Blurting is per question now, and the game setting is a master switch.
{
  const { data: z } = await teacher.from('quizzes').insert({ title: 'per-question blurt' }).select('id').single()
  await teacher.from('questions').insert([
    { quiz_id: z.id, position: 0, kind: 'choice', text: 'Blurtable', choices: ['a', 'b'], correct_index: 0, seconds: 15, blurt_enabled: true },
    { quiz_id: z.id, position: 1, kind: 'choice', text: 'Opted out', choices: ['a', 'b'], correct_index: 0, seconds: 15, blurt_enabled: false },
  ])

  const { data: r } = await teacher.rpc('create_game', { p_quiz_id: z.id })
  const HB = r[0].host_token
  const { data: kid } = await db.rpc('join_game', { p_code: r[0].code, p_name: 'Blurty' })

  await teacher.rpc('advance_game', { p_host_token: HB })
  const first = await db.from('games').select('phase').eq('code', r[0].code).maybeSingle()
  check('a question that wants the window gets it', first.data?.phase === 'recall', first.data?.phase)

  await teacher.rpc('advance_game', { p_host_token: HB })
  await db.rpc('submit_answer', { p_player_token: kid[0].player_token, p_choice: 0 })
  await teacher.rpc('advance_game', { p_host_token: HB })
  const second = await db.from('games').select('phase').eq('code', r[0].code).maybeSingle()
  check('one that opted out opens straight into its choices',
    second.data?.phase === 'question_open', second.data?.phase)

  const claim = await db.rpc('blurt', { p_player_token: kid[0].player_token })
  check('and its floor cannot be claimed', claim.data === false)

  const seen = await teacher.rpc('host_question', { p_host_token: HB })
  check('the teacher screen is told this is not a blurt question', seen.data?.[0]?.q_blurt === false)

  // Master switch off: even the willing question skips its window.
  const { data: r2 } = await teacher.rpc('create_game', { p_quiz_id: z.id })
  await teacher.rpc('update_game_settings', { p_host_token: r2[0].host_token, p_blurt_enabled: false })
  await teacher.rpc('advance_game', { p_host_token: r2[0].host_token })
  const off = await db.from('games').select('phase').eq('code', r2[0].code).maybeSingle()
  check('the game setting still overrules a willing question',
    off.data?.phase === 'question_open', off.data?.phase)

  await teacher.rpc('close_game', { p_host_token: HB })
  await teacher.rpc('close_game', { p_host_token: r2[0].host_token })
  await teacher.from('quizzes').update({ archived_at: new Date().toISOString() }).eq('id', z.id)
}

// Phase 4: a teacher can write quizzes, and nobody else can touch them.
{
  const planted = await db.from('quizzes').insert({ title: 'planted by a student' }).select('id')
  check('a student cannot create a quiz', planted.error !== null, planted.error?.message)

  const { data: made, error: makeErr } = await teacher.from('quizzes').insert({ title: 'verify-db scratch' }).select('id').single()
  check('a teacher can', !makeErr, makeErr?.message)
  const Z = made.id

  const bad = await teacher.from('questions').insert({
    quiz_id: Z, position: 0, kind: 'text', text: 'No accepted answers', accepted: [],
  })
  check('an unanswerable question is refused by the database', bad.error !== null, bad.error?.message?.slice(0, 50))

  const { data: qs, error: qErr } = await teacher.from('questions').insert([
    { quiz_id: Z, position: 0, kind: 'truefalse', text: 'T/F', choices: ['True', 'False'], correct_index: 0, seconds: 15 },
    { quiz_id: Z, position: 1, kind: 'text', text: 'Typed', accepted: ['<ol>', 'ordered list'], seconds: 15 },
  ]).select('id, position')
  check('true/false and typed questions save', !qErr && qs?.length === 2, qErr?.message)

  const peek = await db.from('questions').select('id').eq('quiz_id', Z)
  check('a student cannot read them', peek.error !== null, peek.error?.message)

  const swapped = await teacher.rpc('reorder_questions', { p_quiz_id: Z, p_ids: [...qs].reverse().map((q) => q.id) })
  check('questions reorder in one statement', swapped.error === null, swapped.error?.message)
  const theirs = await db.rpc('reorder_questions', { p_quiz_id: Z, p_ids: qs.map((q) => q.id) })
  check('a student cannot reorder them', theirs.error !== null, theirs.error?.message?.slice(0, 50))
  await teacher.rpc('reorder_questions', { p_quiz_id: Z, p_ids: qs.map((q) => q.id) })

  // Play it: true/false takes two choices, typed answers forgive the right things.
  const { data: room } = await teacher.rpc('create_game', { p_quiz_id: Z })
  const HZ = room[0].host_token
  await teacher.rpc('update_game_settings', { p_host_token: HZ, p_blurt_enabled: false })
  const { data: ana } = await db.rpc('join_game', { p_code: room[0].code, p_name: 'Ana' })
  const { data: ben } = await db.rpc('join_game', { p_code: room[0].code, p_name: 'Ben' })
  await teacher.rpc('advance_game', { p_host_token: HZ })

  const seatTf = await db.rpc('my_seat', { p_player_token: ana[0].player_token })
  check('the phone is told to draw two shapes for true/false',
    seatTf.data?.[0]?.question_kind === 'truefalse' && seatTf.data?.[0]?.choice_count === 2)
  const third = await db.rpc('submit_answer', { p_player_token: ana[0].player_token, p_choice: 2 })
  check('a third choice on a two-choice question is refused', third.error !== null, third.error?.message)
  await db.rpc('submit_answer', { p_player_token: ana[0].player_token, p_choice: 0 })
  await db.rpc('submit_answer', { p_player_token: ben[0].player_token, p_choice: 1 })

  await teacher.rpc('advance_game', { p_host_token: HZ }) // results -> typed question
  const tap = await db.rpc('submit_answer', { p_player_token: ana[0].player_token, p_choice: 0 })
  check('a typed question cannot be answered with a tap', tap.error !== null, tap.error?.message)
  await db.rpc('submit_text_answer', { p_player_token: ana[0].player_token, p_text: '  OL. ' })
  await db.rpc('submit_text_answer', { p_player_token: ben[0].player_token, p_text: 'ul' })

  const mineA = await db.rpc('my_result', { p_player_token: ana[0].player_token })
  const mineB = await db.rpc('my_result', { p_player_token: ben[0].player_token })
  check('"  OL. " matches "<ol>", "ul" does not',
    mineA.data?.[0]?.correct === true && mineB.data?.[0]?.correct === false)
  const wall = await db.rpc('text_distribution', { p_code: room[0].code })
  check('the wall gets what was typed', wall.data?.length === 2, JSON.stringify(wall.data?.map((r) => r.answer_text)))

  await teacher.rpc('close_game', { p_host_token: HZ })
  // Hosted once, so it can only be archived: the game still points at it.
  const hard = await teacher.from('quizzes').delete().eq('id', Z)
  check('a hosted quiz cannot be hard-deleted out from under its games', hard.error !== null)
  await teacher.from('quizzes').update({ archived_at: new Date().toISOString() }).eq('id', Z)
  const again = await teacher.rpc('create_game', { p_quiz_id: Z })
  check('an archived quiz cannot be hosted', again.error !== null, again.error?.message)
}

console.log(`\n  ${failures ? `${failures} failed` : 'all checks passed'}  (test room ${code})\n`)
process.exit(failures ? 1 : 0)
