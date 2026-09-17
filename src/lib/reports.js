// Reading a game after the bell. Everything here is gated on owning the game
// rather than on holding the host token — the token lives in a browser and will
// be long gone by the time anyone opens a report.

import { db } from './supabase.js'

function fail(error) {
  throw new Error(error.message ?? 'Something went wrong')
}

export async function listGames() {
  const { data, error } = await db.rpc('my_games')
  if (error) fail(error)
  return (data ?? []).map((g) => ({
    id: g.game_id,
    code: g.code,
    playedAt: g.played_at,
    quizTitle: g.quiz_title,
    finished: g.finished,
    players: g.players,
    asked: g.questions_asked,
    total: g.questions_total,
    topName: g.top_name,
  }))
}

export async function loadReport(gameId) {
  const [summary, questions, players] = await Promise.all([
    db.rpc('game_summary', { p_game_id: gameId }),
    db.rpc('game_report', { p_game_id: gameId }),
    db.rpc('game_players', { p_game_id: gameId }),
  ])
  for (const r of [summary, questions, players]) if (r.error) fail(r.error)
  const s = summary.data?.[0]
  if (!s) fail({ message: 'No such game, or it belongs to someone else.' })

  return {
    summary: {
      code: s.code,
      playedAt: s.played_at,
      quizTitle: s.quiz_title,
      finished: s.finished,
      players: s.players,
      asked: s.questions_asked,
      total: s.questions_total,
      blurtEnabled: s.blurt_enabled,
      streakBonus: s.streak_bonus,
    },
    // Already hardest-first from the database; the order is the point.
    questions: (questions.data ?? []).map((q) => ({
      position: q.q_position,
      kind: q.q_kind,
      text: q.q_text,
      answer: q.q_answer,
      answered: q.answered,
      correct: q.correct,
      percent: q.percent_correct,
      medianMs: q.median_ms,
      commonWrong: q.common_wrong,
      commonWrongCount: q.common_wrong_count,
      blurter: q.blurter,
      blurtCorrect: q.blurt_correct,
    })),
    players: (players.data ?? []).map((p) => ({
      id: p.player_id,
      name: p.player_name,
      score: p.score,
      place: p.place,
      answered: p.answered,
      correct: p.correct,
      bestStreak: p.best_streak,
      blurtWins: p.blurt_wins,
      blurtMisses: p.blurt_misses,
      avgMs: p.avg_ms,
      missed: p.missed ?? [],
    })),
  }
}

export async function deleteGame(gameId) {
  const { error } = await db.rpc('delete_game', { p_game_id: gameId })
  if (error) fail(error)
}
