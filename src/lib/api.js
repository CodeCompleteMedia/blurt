// Everything the three surfaces are allowed to do. Each call maps to one
// function in the database, which is where the rules actually live: this file
// can only ask, it cannot decide.

import { db } from './supabase.js'

/** Postgres messages are already written for a teenager to read; pass them on. */
function fail(error) {
  throw new Error(error.message ?? 'Something went wrong')
}

// ------------------------------------------------------------------ content --

/** The signed-in teacher's quizzes. Row level security does the filtering. */
export async function listQuizzes() {
  const { data, error } = await db
    .from('quizzes')
    .select('id, title, default_seconds, created_at, questions(count)')
    .is('archived_at', null)
    .order('created_at', { ascending: false })
  if (error) fail(error)
  return (data ?? []).map((quiz) => ({
    id: quiz.id,
    title: quiz.title,
    defaultSeconds: quiz.default_seconds,
    questionCount: quiz.questions?.[0]?.count ?? 0,
  }))
}

export async function quizTitle(quizId) {
  const { data, error } = await db.from('quizzes').select('title').eq('id', quizId).maybeSingle()
  if (error) fail(error)
  return data?.title ?? ''
}

/** A new teacher's first quiz: their own copy of the five starter questions. */
export async function copySampleQuiz() {
  const { data, error } = await db.rpc('copy_sample_quiz')
  if (error) fail(error)
  return data
}

export async function duplicateQuiz(quizId) {
  const { data, error } = await db.rpc('duplicate_quiz', { p_quiz_id: quizId })
  if (error) fail(error)
  return data
}

/**
 * The question on screen. `correctIndex` is null until the projector reaches
 * results — the database decides that, not this code.
 */
export async function currentQuestion(code) {
  const { data, error } = await db.rpc('current_question', { p_code: code })
  if (error) fail(error)
  const row = data?.[0]
  if (!row) return null
  return {
    position: row.q_position,
    kind: row.q_kind,
    text: row.q_text,
    choices: row.q_choices,
    seconds: row.q_seconds,
    correctIndex: row.q_correct_index,
    // The answer in words, whatever kind of question it was. Null until results.
    answer: row.q_answer,
    image: imageUrl(row.q_image),
  }
}

/** Pictures are public to read — the wall is not signed in. */
export function imageUrl(path) {
  return path ? db.storage.from('question-images').getPublicUrl(path).data.publicUrl : null
}

/** What the room typed, most common first, already filtered for the wall. */
export async function textDistribution(code) {
  const { data, error } = await db.rpc('text_distribution', { p_code: code })
  if (error) fail(error)
  return (data ?? []).map((row) => ({
    text: row.answer_text,
    count: Number(row.answer_count),
    correct: row.is_correct,
  }))
}

/** Empty until results, so nobody can watch the vote come in and follow it. */
export async function distribution(code) {
  const { data, error } = await db.rpc('distribution', { p_code: code })
  if (error) fail(error)
  if (!data?.length) return []
  return data.map((row) => Number(row.answer_count))
}

// -------------------------------------------------------------------- state --

export async function fetchGame(code) {
  const { data, error } = await db.from('games').select('*').eq('code', code).maybeSingle()
  if (error) fail(error)
  return data
}

export async function fetchPlayers(gameId) {
  const { data, error } = await db
    .from('players')
    .select('id, name, score')
    .eq('game_id', gameId)
    .order('score', { ascending: false })
    .order('joined_at', { ascending: true })
  if (error) fail(error)
  return (data ?? []).map((player, i) => ({ ...player, rank: i + 1 }))
}

// ------------------------------------------------------------------ actions --

export async function createGame(quizId) {
  const { data, error } = await db.rpc('create_game', { p_quiz_id: quizId })
  if (error) fail(error)
  return { code: data[0].code, hostToken: data[0].host_token }
}

export async function joinGame(code, name) {
  const { data, error } = await db.rpc('join_game', {
    p_code: code.trim().toUpperCase(),
    p_name: name.trim(),
  })
  if (error) fail(error)
  return { playerId: data[0].player_id, playerToken: data[0].player_token }
}

export async function submitTextAnswer(playerToken, text) {
  const { error } = await db.rpc('submit_text_answer', { p_player_token: playerToken, p_text: text })
  if (error) fail(error)
}

/** Sends a seat token and a choice. Deliberately nothing else. */
export async function submitAnswer(playerToken, choice) {
  const { error } = await db.rpc('submit_answer', {
    p_player_token: playerToken,
    p_choice: choice,
  })
  if (error) fail(error)
}

/** How the teacher wants this round to run. Takes effect from the next question. */
export async function updateGameSettings(hostToken, settings) {
  const { error } = await db.rpc('update_game_settings', {
    p_host_token: hostToken,
    p_blurt_enabled: settings.blurtEnabled,
    p_reveal_immediately: settings.revealImmediately,
    p_auto_next_seconds: settings.autoNextSeconds,
    p_recall_seconds: settings.recallSeconds,
    p_allow_late_join: settings.allowLateJoin,
    p_blurt_lockout: settings.blurtLockout,
    p_blurt_penalty: settings.blurtPenalty,
  })
  if (error) fail(error)
}

/**
 * Where this phone stands, so a refresh or a lock screen puts it back exactly
 * where it was. Throws once the seat is gone — which is how a phone finds out it
 * has been removed.
 */
export async function mySeat(playerToken) {
  const { data, error } = await db.rpc('my_seat', { p_player_token: playerToken })
  if (error) fail(error)
  const row = data?.[0]
  return row
    ? {
        playerId: row.player_id,
        name: row.player_name,
        answeredCurrent: row.answered_current,
        lockedOut: row.locked_out,
        // All the phone learns about the question: what to draw.
        questionKind: row.question_kind,
        choiceCount: row.choice_count,
      }
    : null
}

export async function kickPlayer(hostToken, playerId) {
  const { error } = await db.rpc('kick_player', { p_host_token: hostToken, p_player_id: playerId })
  if (error) fail(error)
}

export async function renamePlayer(hostToken, playerId, name) {
  const { error } = await db.rpc('rename_player', {
    p_host_token: hostToken,
    p_player_id: playerId,
    p_name: name,
  })
  if (error) fail(error)
}

export async function setPaused(hostToken, paused) {
  const { error } = await db.rpc('set_paused', { p_host_token: hostToken, p_paused: paused })
  if (error) fail(error)
}

export async function extendQuestion(hostToken, seconds) {
  const { error } = await db.rpc('extend_question', { p_host_token: hostToken, p_seconds: seconds })
  if (error) fail(error)
}

/** Ends a room. The wall and the phones are watching for this. */
export async function closeGame(hostToken) {
  const { error } = await db.rpc('close_game', { p_host_token: hostToken })
  if (error) fail(error)
}

export async function advanceGame(hostToken) {
  const { error } = await db.rpc('advance_game', { p_host_token: hostToken })
  if (error) fail(error)
}

/** Claims the floor. False means someone else got there first. */
export async function blurt(playerToken) {
  const { data, error } = await db.rpc('blurt', { p_player_token: playerToken })
  if (error) fail(error)
  return data === true
}

/** The teacher's verdict on a spoken answer. */
export async function judgeBlurt(hostToken, correct) {
  const { error } = await db.rpc('judge_blurt', { p_host_token: hostToken, p_correct: correct })
  if (error) fail(error)
}

/**
 * Who claimed the floor, for the wall — during the claim, and again at results so
 * the reveal can name whoever won the question outright. A name and whether they
 * got it; nothing else about them is anyone's business.
 */
export async function blurter(code) {
  const { data, error } = await db.rpc('blurter', { p_code: code })
  if (error) fail(error)
  const row = data?.[0]
  return row ? { id: row.player_id, name: row.player_name, wasCorrect: row.was_correct } : null
}

/**
 * How the caller did on the question just shown — and nobody else. Empty until
 * the room reaches results, so nobody learns they were right while the question
 * is still open and the person beside them is still deciding.
 */
export async function myResult(playerToken) {
  const { data, error } = await db.rpc('my_result', { p_player_token: playerToken })
  if (error) fail(error)
  const row = data?.[0]
  if (!row) return null
  return {
    answered: row.answered,
    correct: row.correct,
    awarded: row.awarded,
    blurted: row.blurted,
    streak: row.streak,
  }
}

/**
 * The same question the wall is showing, but never withheld — the referee has
 * to know the answer while a student is saying it out loud.
 */
export async function hostQuestion(hostToken) {
  const { data, error } = await db.rpc('host_question', { p_host_token: hostToken })
  if (error) fail(error)
  const row = data?.[0]
  if (!row) return null
  return {
    position: row.q_position,
    kind: row.q_kind,
    text: row.q_text,
    choices: row.q_choices,
    seconds: row.q_seconds,
    recallSeconds: row.q_recall_seconds,
    correctIndex: row.q_correct_index,
    accepted: row.q_accepted ?? [],
    // What to listen for when a student says it out loud.
    answer: row.q_kind === 'text' ? (row.q_accepted ?? []).join('  ·  ') : row.q_choices?.[row.q_correct_index],
  }
}

/**
 * The teacher's read of the room. Gated on the host token because it is built
 * from `answers`, which no client may read directly.
 */
export async function rosterStats(hostToken) {
  const { data, error } = await db.rpc('roster_stats', { p_host_token: hostToken })
  if (error) fail(error)
  return (data ?? []).map((row, i) => ({
    id: row.player_id,
    name: row.player_name,
    score: row.score,
    answered: row.answered,
    correct: row.correct,
    streak: row.streak,
    avgMs: row.avg_ms,
    blurtWins: row.blurt_wins,
    answeredCurrent: row.answered_current,
    quietFor: row.quiet_for,
    rank: i + 1,
  }))
}

// ------------------------------------------------------------------- watch ---

/**
 * Pushes game and roster changes to the caller.
 *
 * Realtime carries it normally. The poll underneath is not redundancy for its
 * own sake: school networks block or idle out websockets, and a projector that
 * silently stops advancing mid-lesson is the worst failure this app has. Two
 * small queries every few seconds is a cheap insurance premium.
 */
// Supabase hands back the *existing* channel when a name is reused, and adding
// listeners to an already-subscribed channel throws. Removal is asynchronous, so
// a teardown and a re-subscribe can overlap — a fresh name each time sidesteps
// the race entirely.
let channelSeq = 0

export function watchGame({ code, gameId, onGame, onPlayers, intervalMs = 2500 }) {
  let live = false

  const refresh = async () => {
    try {
      const [game, players] = await Promise.all([fetchGame(code), fetchPlayers(gameId)])
      if (game) onGame?.(game)
      if (players) onPlayers?.(players)
    } catch {
      // A dropped read is not worth interrupting a lesson over.
    }
  }

  const channel = db
    .channel(`blurt:${gameId}:${(channelSeq += 1)}`)
    .on(
      'postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'games', filter: `id=eq.${gameId}` },
      ({ new: row }) => onGame?.(row),
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'players', filter: `game_id=eq.${gameId}` },
      async () => onPlayers?.(await fetchPlayers(gameId)),
    )
    .subscribe((status) => {
      live = status === 'SUBSCRIBED'
    })

  const timer = setInterval(refresh, intervalMs)

  // A backgrounded tab has its timers throttled to a crawl, so a phone that was
  // locked mid-question comes back stale. Catch up the moment it is visible
  // again rather than waiting for the next tick.
  const onVisible = () => {
    if (document.visibilityState === 'visible') refresh()
  }
  document.addEventListener('visibilitychange', onVisible)
  window.addEventListener('focus', onVisible)

  return {
    stop() {
      db.removeChannel(channel)
      clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('focus', onVisible)
    },
    get live() {
      return live
    },
  }
}
