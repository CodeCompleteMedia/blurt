// Everything the three surfaces are allowed to do. Each call maps to one
// function in the database, which is where the rules actually live: this file
// can only ask, it cannot decide.

import { db } from './supabase.js'

/** Postgres messages are already written for a teenager to read; pass them on. */
function fail(error) {
  throw new Error(error.message ?? 'Something went wrong')
}

// ------------------------------------------------------------------ content --

export async function firstQuiz() {
  const { data, error } = await db
    .from('quizzes')
    .select('id, title')
    .order('created_at', { ascending: true })
    .limit(1)
  if (error) fail(error)
  return data?.[0] ?? null
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
    text: row.q_text,
    choices: row.q_choices,
    seconds: row.q_seconds,
    correctIndex: row.q_correct_index,
  }
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
    text: row.q_text,
    choices: row.q_choices,
    seconds: row.q_seconds,
    recallSeconds: row.q_recall_seconds,
    correctIndex: row.q_correct_index,
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
