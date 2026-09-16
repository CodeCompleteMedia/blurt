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

export async function advanceGame(hostToken) {
  const { error } = await db.rpc('advance_game', { p_host_token: hostToken })
  if (error) fail(error)
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
