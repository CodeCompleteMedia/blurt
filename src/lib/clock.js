// Every countdown on every screen is derived from `questionStartedAt` rather
// than from server ticks, so a phone that polls once a second still shows a
// smooth timer — and a phone that missed three polls still shows the right one.

/** Milliseconds left on a question, clamped at zero. */
export function remainingMs(startedAt, limit, now = Date.now()) {
  if (startedAt == null) return limit
  return Math.max(0, startedAt + limit - now)
}

/** Fraction of the question still to run, 1 at the start and 0 at the deadline. */
export function remainingFraction(startedAt, limit, now = Date.now()) {
  if (!limit) return 0
  return remainingMs(startedAt, limit, now) / limit
}

/** Whole seconds to show on screen: 20, 19, ... 1, 0. */
export function remainingSeconds(startedAt, limit, now = Date.now()) {
  return Math.ceil(remainingMs(startedAt, limit, now) / 1000)
}

/**
 * Calls `fn` once per animation frame until the returned function is called.
 * Used for the countdown ring; paused tabs simply stop firing, which is fine
 * because the next frame recomputes from the timestamp rather than accumulating.
 */
export function ticker(fn) {
  let frame = requestAnimationFrame(function loop() {
    fn(Date.now())
    frame = requestAnimationFrame(loop)
  })
  return () => cancelAnimationFrame(frame)
}

/**
 * A timer that survives a backgrounded tab.
 *
 * `ticker` runs on animation frames, which browsers pause outright when a tab is
 * not visible — fine for drawing a countdown nobody is looking at, useless for
 * deciding that a deadline has passed. Anything that must happen on time, whether
 * or not the teacher is looking at this tab, belongs here.
 */
export function heartbeat(fn, ms = 1000) {
  const id = setInterval(() => fn(Date.now()), ms)
  return () => clearInterval(id)
}

/**
 * Which timestamp to count down from.
 *
 * Normally the server's `question_started_at`, so every screen in the room
 * agrees and the deadline the database enforces is the deadline students see.
 *
 * The fallback is only for a device whose clock is actually wrong: one that
 * thinks the question starts in the future, or that is out by an absurd margin.
 * A question sitting past its deadline is NOT evidence of a broken clock — that
 * is just a teacher who has not pressed space yet, and it must keep reading zero
 * rather than springing back to a full timer.
 */
export function clockBase(startedAtIso, limit, learnedAt = Date.now()) {
  const t = Date.parse(startedAtIso)
  if (!Number.isFinite(t)) return learnedAt
  const elapsed = learnedAt - t
  if (elapsed < -2000) return learnedAt
  if (elapsed > 3_600_000) return learnedAt
  return t
}
